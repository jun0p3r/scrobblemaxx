import SwiftUI

/// Appearance preferences shared by the panel and the Appearance settings tab.
enum AppearanceKey {
    static let showArtwork = "showArtworkBackground"
    static let autoDim = "autoDim"
    static let dimAmount = "dimAmount"
    static let blurRadius = "blurRadius"
}

/// Square "now playing" panel: blurred cover behind, track info on top,
/// progress in the middle, account + options card at the bottom.
struct MenuView: View {
    @EnvironmentObject var engine: ScrobbleEngine
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(AppearanceKey.showArtwork) private var showArtwork = true
    @AppStorage(AppearanceKey.autoDim) private var autoDim = true
    @AppStorage(AppearanceKey.dimAmount) private var dimAmount = 0.5
    @AppStorage(AppearanceKey.blurRadius) private var blurRadius = 6.0

    @State private var showingCard = false

    static let size: CGFloat = 340

    var body: some View {
        ZStack {
            background
            VStack(alignment: .leading, spacing: 0) {
                trackInfo
                    .opacity(showingCard ? 0 : 1)
                Spacer(minLength: 12)
                progress
                    .opacity(showingCard ? 0 : 1)
                Spacer(minLength: 12)
                if !showingCard, !engine.status.isEmpty || !engine.queue.isEmpty {
                    statusLine.padding(.bottom, 8)
                }
                bottomBar
            }
            .padding(20)

            if showingCard {
                // Click outside the card to dismiss.
                Color.black.opacity(0.3)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleCard() }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                OptionsCard(close: { toggleCard() })
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 62)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: Self.size, height: Self.size)
        .environment(\.colorScheme, .dark)
        .onAppear { engine.panelOpened() }
        .onDisappear { showingCard = false }
    }

    // MARK: Background

    private var useArtwork: Bool { showArtwork && !reduceTransparency && engine.artwork != nil }

    private var background: some View {
        ZStack {
            if useArtwork, let art = engine.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.size, height: Self.size)
                    .blur(radius: blurRadius, opaque: true)
                    .clipped()
            } else {
                Color(white: 0.13)
            }
            if useArtwork {
                LinearGradient(colors: scrimColors, startPoint: .top, endPoint: .bottom)
            }
        }
        .accessibilityHidden(true)
    }

    /// Darker at the top (title) and bottom (account row) so white text stays readable.
    private var scrimColors: [Color] {
        if autoDim {
            // Bright covers get a heavier scrim.
            let lum = engine.artworkLuminance
            return [.black.opacity(0.45 + 0.35 * lum), .black.opacity(0.30 + 0.35 * lum), .black.opacity(0.85)]
        }
        return [.black.opacity(dimAmount), .black.opacity(dimAmount * 0.8), .black.opacity(min(1, dimAmount + 0.35))]
    }

    // MARK: Track info

    @ViewBuilder private var trackInfo: some View {
        if let track = engine.currentTrack {
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(.largeTitle).weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
                Text("by \(track.artist)")
                    .font(.system(.title2).weight(.light))
                    .lineLimit(1)
                if let album = track.album, !album.isEmpty {
                    Text("on \(album)")
                        .font(.system(.title2).weight(.light))
                        .lineLimit(1)
                }
                if let state = stateLabel {
                    Text(state)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .foregroundStyle(.primary)
            .shadow(color: .black.opacity(useArtwork ? 0.6 : 0), radius: 4)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("Nothing Playing")
                    .font(.system(.largeTitle).weight(.semibold))
                Text("Play something in Music")
                    .font(.system(.title3).weight(.light))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stateLabel: String? {
        if !engine.enabled { return "Scrobbling paused" }
        switch engine.playerState {
        case .playing: return nil
        case .paused: return "Paused"
        case .stopped: return "Stopped"
        }
    }

    @ViewBuilder private var progress: some View {
        if let track = engine.currentTrack, track.duration > 0 {
            VStack(alignment: .leading, spacing: 8) {
                TrackProgressBar(position: engine.position,
                                 duration: track.duration,
                                 marker: engine.thresholdFraction,
                                 scrobbled: engine.currentScrobbled)
                    .opacity(engine.enabled ? 1 : 0.5)
                    .shadow(color: .black.opacity(useArtwork ? 0.5 : 0), radius: 3)
                if engine.musicAccess == .denied {
                    Button {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    } label: {
                        Label("Time is estimated. Allow access to Music…", systemImage: "exclamationmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(.secondary)
                    .help("Open Privacy & Security → Automation and turn on Music for Last.fm Scrobbler")
                }
            }
        }
    }

    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !engine.queue.isEmpty {
                Label("\(engine.queue.count) waiting to send", systemImage: "clock.arrow.circlepath")
            }
            if !engine.status.isEmpty {
                Text(engine.status).lineLimit(2)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if let user = engine.credentials.username {
                avatar
                Text(user)
                    .font(.headline)
                    .lineLimit(1)
            } else {
                Button { AuxWindow.showSettings(engine, tab: .account) } label: {
                    Label("Log In to Last.fm…", systemImage: "person.crop.circle.badge.plus")
                        .font(.headline)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button(action: toggleCard) {
                Image(systemName: "chevron.up.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .rotationEffect(.degrees(showingCard ? 180 : 0))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Edit, recent scrobbles and settings")
            .accessibilityLabel(showingCard ? "Hide options" : "Show options")
        }
        .zIndex(1)
    }

    private var avatar: some View {
        Group {
            if let img = engine.avatar {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.crop.circle.fill").resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.2)))
        .accessibilityHidden(true)
    }

    private func toggleCard() {
        if reduceMotion {
            showingCard.toggle()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showingCard.toggle() }
        }
    }

    static func icon(for status: HistoryItem.Status) -> String {
        switch status {
        case .queued: return "clock"
        case .sent: return "checkmark"
        case .resent: return "arrow.triangle.2.circlepath"
        case .ignored: return "exclamationmark.triangle"
        case .rejected: return "xmark.octagon"
        }
    }

    static func description(for status: HistoryItem.Status) -> String {
        switch status {
        case .queued: return "Waiting to send"
        case .sent: return "Scrobbled"
        case .resent: return "Correction sent"
        case .ignored: return "Ignored by Last.fm"
        case .rejected: return "Rejected by Last.fm"
        }
    }
}

// MARK: - Options card

private struct OptionsCard: View {
    @EnvironmentObject var engine: ScrobbleEngine
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            MenuRow(close: close) {
                AuxWindow.showEdit(.current, engine: engine)
            } label: {
                Label("Edit Current Track…", systemImage: "pencil")
            }
            .disabled(engine.currentTrack == nil)

            Divider().padding(.vertical, 4).padding(.horizontal, 6)

            Text("Recent Scrobbles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
            if engine.history.isEmpty {
                Text("Nothing scrobbled yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            ForEach(engine.history.prefix(3)) { item in
                MenuRow(close: close) {
                    AuxWindow.showEdit(.history(item.id), engine: engine)
                } label: {
                    RecentRowLabel(item: item)
                }
                .help("Edit this scrobble")
            }

            Divider().padding(.vertical, 4).padding(.horizontal, 6)

            HStack(spacing: 6) {
                Toggle("Scrobbling", isOn: $engine.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.callout)
                Spacer()
                IconButton(icon: "gearshape", label: "Settings") {
                    close()
                    AuxWindow.showSettings(engine)
                }
                IconButton(icon: "person.crop.circle", label: "Open Last.fm Profile") {
                    if let url = engine.profileURL { NSWorkspace.shared.open(url) }
                }
                .disabled(engine.profileURL == nil)
                IconButton(icon: "power", label: "Quit Last.fm Scrobbler") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
        .padding(6)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }

    @ViewBuilder private var cardBackground: some View {
        if reduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }
}

/// A menu-style row: accent-colour highlight on hover, like a native menu item.
private struct MenuRow<Label: View>: View {
    let close: () -> Void
    let action: () -> Void
    @ViewBuilder let label: Label
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    init(close: @escaping () -> Void, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.close = close
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button {
            close()
            action()
        } label: {
            label
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(highlighted ? .white : .primary)
                .background(highlighted ? Color.accentColor : .clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
    }

    private var highlighted: Bool { hovering && isEnabled }
}

private struct RecentRowLabel: View {
    let item: HistoryItem

    var body: some View {
        HStack(spacing: 8) {
            thumb
            VStack(alignment: .leading, spacing: 0) {
                Text(item.scrobble.track.title).lineLimit(1)
                Text(item.scrobble.track.artist)
                    .font(.caption)
                    .opacity(0.7)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: MenuView.icon(for: item.status))
                .font(.caption)
                .opacity(0.8)
                .frame(width: 16)
                .accessibilityLabel(MenuView.description(for: item.status))
        }
    }

    private var thumb: some View {
        Group {
            if let img = ArtworkProvider.shared.cached(for: item.scrobble.track) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note").font(.caption).opacity(0.6)
                }
            }
        }
        .frame(width: 26, height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct IconButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 28, height: 24)
                .background(.white.opacity(hovering && isEnabled ? 0.15 : 0),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
