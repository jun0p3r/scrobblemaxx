import SwiftUI

/// Square "now playing" card: blurred cover behind, track info on top,
/// progress in the middle, account + dropdown at the bottom.
struct MenuView: View {
    @EnvironmentObject var engine: ScrobbleEngine
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
                if !engine.status.isEmpty || !engine.queue.isEmpty {
                    statusLine.padding(.bottom, 8)
                }
                bottomBar
            }
            .padding(22)

            if showingCard {
                // Tap outside the card to dismiss.
                Color.black.opacity(0.3)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleCard() }
                    .transition(.opacity)
                OptionsCard(close: { toggleCard() })
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 64)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: Self.size, height: Self.size)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .onAppear { engine.loadAvatarIfNeeded() }
        .onDisappear { showingCard = false }
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            if let art = engine.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.size, height: Self.size)
                    .blur(radius: 6, opaque: true)
                    .clipped()
            } else {
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.08)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            // Bright covers get a heavier scrim so white text stays readable.
            let lum = engine.artwork == nil ? 0 : engine.artworkLuminance
            LinearGradient(colors: [.black.opacity(0.45 + 0.35 * lum),
                                    .black.opacity(0.30 + 0.35 * lum),
                                    .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: Track info

    @ViewBuilder private var trackInfo: some View {
        if let track = engine.currentTrack {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text("by \(track.artist)")
                    .font(.system(size: 19, weight: .light))
                    .lineLimit(1)
                if let album = track.album, !album.isEmpty {
                    Text("on \(album)")
                        .font(.system(size: 19, weight: .light))
                        .lineLimit(1)
                }
                if engine.playerState != .playing || !engine.enabled {
                    Text(!engine.enabled ? "Scrobbling paused" : engine.playerState == .paused ? "Paused" : "Stopped")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .padding(.top, 4)
                }
            }
            .shadow(color: .black.opacity(0.6), radius: 4)
            .shadow(color: .black.opacity(0.3), radius: 1)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing playing")
                    .font(.system(size: 26, weight: .semibold))
                Text("Play something in Music")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
    }

    @ViewBuilder private var progress: some View {
        if let track = engine.currentTrack, track.duration > 0 {
            TrackProgressBar(position: engine.position,
                             duration: track.duration,
                             marker: engine.thresholdFraction,
                             scrobbled: engine.currentScrobbled)
                .opacity(engine.enabled ? 1 : 0.5)
                .shadow(color: .black.opacity(0.5), radius: 3)
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
        .foregroundStyle(Color.white.opacity(0.7))
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if let user = engine.credentials.username {
                avatar
                Text(user)
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
            } else {
                Button { AuxWindow.showSettings(engine) } label: {
                    Label("Log in to Last.fm", systemImage: "person.crop.circle.badge.plus")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button(action: toggleCard) {
                Image(systemName: "chevron.up.circle.fill")
                    .font(.system(size: 24))
                    .rotationEffect(.degrees(showingCard ? 180 : 0))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Edit, settings and more")
        }
        .zIndex(1)
    }

    private func toggleCard() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showingCard.toggle() }
    }

    private var avatar: some View {
        Group {
            if let img = engine.avatar {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.crop.circle.fill").resizable()
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.25)))
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
}

// MARK: - Options card

private struct OptionsCard: View {
    @EnvironmentObject var engine: ScrobbleEngine
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardRow(icon: "pencil", title: "Edit current track") {
                close()
                AuxWindow.showEdit(.current, engine: engine)
            }
            .disabled(engine.currentTrack == nil)
            .opacity(engine.currentTrack == nil ? 0.4 : 1)

            divider

            Text("RECENT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.horizontal, 8)
            if engine.history.isEmpty {
                Text("Nothing scrobbled yet")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            ForEach(engine.history.prefix(3)) { item in
                RecentRow(item: item) {
                    close()
                    AuxWindow.showEdit(.history(item.id), engine: engine)
                }
            }

            divider

            HStack(spacing: 8) {
                Toggle(isOn: $engine.enabled) {
                    Text("Scrobbling").font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                Spacer()
                IconButton(icon: "gearshape", help: "Settings") {
                    close()
                    AuxWindow.showSettings(engine)
                }
                IconButton(icon: "person", help: "Open Last.fm profile") {
                    if let url = engine.profileURL { NSWorkspace.shared.open(url) }
                }
                .disabled(engine.profileURL == nil)
                IconButton(icon: "power", help: "Quit") { NSApp.terminate(nil) }
            }
            .padding(.leading, 8)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1).padding(.horizontal, 4)
    }
}

/// A full-width row with a hover highlight.
private struct CardRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18)
                Text(title).font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovering ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct RecentRow: View {
    let item: HistoryItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                thumb
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.scrobble.track.title)
                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(item.scrobble.track.artist)
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.7)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: hovering ? "pencil" : MenuView.icon(for: item.status))
                    .font(.system(size: 11))
                    .foregroundStyle(hovering ? Color.white : statusColor)
                    .frame(width: 16)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(hovering ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Edit this scrobble")
    }

    private var thumb: some View {
        Group {
            if let img = ArtworkProvider.shared.cached(for: item.scrobble.track) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.6))
                }
            }
        }
        .frame(width: 26, height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var statusColor: Color {
        switch item.status {
        case .queued: return .white.opacity(0.6)
        case .sent: return .green
        case .resent: return .blue
        case .ignored: return .orange
        case .rejected: return .red
        }
    }
}

private struct IconButton: View {
    let icon: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 30, height: 26)
                .background(Color.white.opacity(hovering ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
