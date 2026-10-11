import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var engine: ScrobbleEngine
    @State private var apiKey = ""
    @State private var apiSecret = ""
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                TextField("API key", text: $apiKey)
                SecureField("Shared secret", text: $apiSecret)
                HStack {
                    Link("Get an API account…", destination: URL(string: "https://www.last.fm/api/account/create")!)
                        .font(.caption)
                    Spacer()
                    Button("Save") { engine.saveAPIKeys(key: apiKey, secret: apiSecret) }
                        .disabled(apiKey.isEmpty || apiSecret.isEmpty)
                }
            } header: {
                Text("Last.fm API")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Scrobble after") {
                        Text("\(Int((engine.scrobblePercent * 100).rounded()))% of the track")
                            .monospacedDigit()
                    }
                    Slider(value: $engine.scrobblePercent, in: 0.5...1, step: 0.05)
                        .labelsHidden()
                }
                Toggle("Or after 4 minutes, whichever comes first", isOn: $engine.capAtFourMinutes)
            } header: {
                Text("Scrobble Point")
            } footer: {
                Text("Last.fm requires at least half the track (or 4 minutes) to be played.")
                    .font(.caption).foregroundStyle(.secondary)
            }

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
                            engine.saveAPIKeys(key: apiKey, secret: apiSecret)
                            run { await engine.beginLogin() }
                        }
                        .disabled(apiKey.isEmpty || apiSecret.isEmpty)
                    }
                }
                if !engine.status.isEmpty {
                    Text(engine.status).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Account")
            }
        }
        .formStyle(.grouped)
        .disabled(busy)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            apiKey = engine.credentials.apiKey
            apiSecret = engine.credentials.apiSecret
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        Task { await work(); busy = false }
    }
}
