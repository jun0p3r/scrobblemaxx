import AppKit
import ServiceManagement
import SwiftUI

enum SettingsTab: Int, CaseIterable {
    case general, appearance, account

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .account: return "Account"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .account: return "person.crop.circle"
        }
    }
}

private let settingsWidth: CGFloat = 460

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject var engine: ScrobbleEngine
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    private var percent: Binding<Double> {
        Binding(get: { (engine.scrobblePercent * 100).rounded() },
                set: { engine.scrobblePercent = min(max($0.rounded(), 0), 100) / 100 })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Scrobble tracks played in Music", isOn: $engine.enabled)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin($0) }
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent("Scrobble at") {
                    HStack(spacing: 8) {
                        SnappingSlider(value: percent)
                            .frame(minWidth: 160)
                        Text("\(Int(percent.wrappedValue))%")
                            .monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                        Stepper("Scrobble percentage", value: percent, in: 0...100, step: 1)
                            .labelsHidden()
                    }
                }
                Toggle("Or after 4 minutes, whichever comes first", isOn: $engine.capAtFourMinutes)
            } header: {
                Text("Scrobble Point")
            } footer: {
                if engine.scrobblePercent < 0.5 {
                    Label("Last.fm’s guidelines ask for at least half the track (or 4 minutes).",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Tracks of 30 seconds or less are never scrobbled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth)
        .fixedSize()
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// An NSSlider with tick marks every 10% that moves in whole-percent steps.
struct SnappingSlider: NSViewRepresentable {
    @Binding var value: Double   // 0...100

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: 0, maxValue: 100,
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.numberOfTickMarks = 11
        slider.tickMarkPosition = .below
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true
        slider.setAccessibilityLabel("Scrobble percentage")
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        if slider.doubleValue != value { slider.doubleValue = value }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: SnappingSlider
        init(_ parent: SnappingSlider) { self.parent = parent }

        @objc func changed(_ slider: NSSlider) {
            let snapped = slider.doubleValue.rounded()
            slider.doubleValue = snapped
            if snapped != parent.value { parent.value = snapped }
        }
    }
}

// MARK: - Appearance

struct AppearanceSettingsView: View {
    @AppStorage(AppearanceKey.showArtwork) private var showArtwork = true
    @AppStorage(AppearanceKey.autoDim) private var autoDim = true
    @AppStorage(AppearanceKey.dimAmount) private var dimAmount = 0.5
    @AppStorage(AppearanceKey.blurRadius) private var blurRadius = 6.0

    var body: some View {
        Form {
            Section {
                Toggle("Show album art behind the panel", isOn: $showArtwork)
                Toggle("Adjust dimming automatically", isOn: $autoDim)
                    .disabled(!showArtwork)
                LabeledContent("Dimming") {
                    HStack {
                        Slider(value: $dimAmount, in: 0...1) {
                            Text("Dimming")
                        } minimumValueLabel: {
                            Image(systemName: "sun.max")
                        } maximumValueLabel: {
                            Image(systemName: "moon")
                        }
                        .labelsHidden()
                        Text("\(Int((dimAmount * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                .disabled(!showArtwork || autoDim)
                LabeledContent("Blur") {
                    HStack {
                        Slider(value: $blurRadius, in: 0...30) {
                            Text("Blur")
                        } minimumValueLabel: {
                            Image(systemName: "circle")
                        } maximumValueLabel: {
                            Image(systemName: "circle.dotted")
                        }
                        .labelsHidden()
                        Text("\(Int(blurRadius.rounded()))")
                            .monospacedDigit()
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                .disabled(!showArtwork)
            } header: {
                Text("Background")
            } footer: {
                Text(autoDim
                     ? "Bright artwork is darkened more so text stays readable."
                     : "Higher dimming makes text easier to read over bright artwork.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Restore Defaults") {
                    showArtwork = true
                    autoDim = true
                    dimAmount = 0.5
                    blurRadius = 6
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth)
        .fixedSize()
    }
}

// MARK: - Account

struct AccountSettingsView: View {
    @EnvironmentObject var engine: ScrobbleEngine
    @State private var apiKey = ""
    @State private var apiSecret = ""
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                if let user = engine.credentials.username {
                    LabeledContent("Logged in as") {
                        HStack {
                            Text(user).bold()
                            Button("Log Out") { engine.logout() }
                        }
                    }
                } else if engine.pendingToken != nil {
                    LabeledContent("Approve access in your browser, then") {
                        Button("Finish Login") { run { await engine.finishLogin() } }
                            .keyboardShortcut(.defaultAction)
                    }
                } else {
                    LabeledContent("Not logged in") {
                        Button("Log In with Last.fm…") {
                            saveKeys()
                            run { await engine.beginLogin() }
                        }
                        .disabled(apiKey.isEmpty || apiSecret.isEmpty)
                    }
                }
                if !engine.status.isEmpty {
                    Text(engine.status).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Last.fm Account")
            }

            Section {
                TextField("API key", text: $apiKey)
                    .onSubmit(saveKeys)
                SecureField("Shared secret", text: $apiSecret)
                    .onSubmit(saveKeys)
            } header: {
                Text("API Credentials")
            } footer: {
                HStack {
                    Text("Stored securely in your Keychain.")
                    Spacer()
                    Link("Get an API account…", destination: URL(string: "https://www.last.fm/api/account/create")!)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .disabled(busy)
        .frame(width: settingsWidth)
        .fixedSize()
        .onAppear {
            apiKey = engine.credentials.apiKey
            apiSecret = engine.credentials.apiSecret
        }
        .onDisappear(perform: saveKeys)
    }

    private func saveKeys() {
        guard !apiKey.isEmpty, !apiSecret.isEmpty else { return }
        engine.saveAPIKeys(key: apiKey, secret: apiSecret)
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        Task { await work(); busy = false }
    }
}
