import AppKit
import SwiftUI

@main
struct LastfmScrobblerApp: App {
    @StateObject private var engine = ScrobbleEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(engine)
        } label: {
            Image(systemName: engine.playerState == .playing && engine.enabled ? "music.note" : "music.note.list")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Plain NSWindows for Settings / Edit — reliable for LSUIElement apps, and unlike popovers
/// they survive the menu-bar panel closing.
@MainActor
enum AuxWindow {
    private static var windows: [String: NSWindow] = [:]

    static func show<V: View>(id: String, title: String, replace: Bool = false, content: () -> V) {
        if replace, let old = windows.removeValue(forKey: id) { old.close() }
        let window = windows[id] ?? {
            let w = NSWindow(contentViewController: NSHostingController(rootView: content()))
            w.title = title
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            windows[id] = w
            return w
        }()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func close(_ id: String) {
        windows.removeValue(forKey: id)?.close()
    }

    static func showSettings(_ engine: ScrobbleEngine) {
        show(id: "settings", title: "Last.fm Scrobbler Settings") {
            SettingsView().environmentObject(engine)
        }
    }

    static func showEdit(_ target: EditTarget, engine: ScrobbleEngine) {
        guard let (track, sent) = engine.editable(target) else { return }
        show(id: "edit", title: "Edit Scrobble", replace: true) {
            EditScrobbleView(target: target, track: track, alreadySent: sent).environmentObject(engine)
        }
    }
}
