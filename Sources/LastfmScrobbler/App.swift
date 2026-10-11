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

    /// Standard macOS settings window: toolbar tabs, title follows the selected tab.
    static func showSettings(_ engine: ScrobbleEngine, tab: SettingsTab? = nil) {
        let window = windows["settings"] ?? {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            for t in SettingsTab.allCases {
                let host: NSViewController
                switch t {
                case .general: host = hosting(GeneralSettingsView().environmentObject(engine))
                case .appearance: host = hosting(AppearanceSettingsView())
                case .account: host = hosting(AccountSettingsView().environmentObject(engine))
                }
                host.title = t.title
                let item = NSTabViewItem(viewController: host)
                item.label = t.title
                item.image = NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.title)
                tabs.addTabViewItem(item)
            }
            let w = NSWindow(contentViewController: tabs)
            w.styleMask = [.titled, .closable]
            w.toolbarStyle = .preference
            w.isReleasedWhenClosed = false
            w.center()
            windows["settings"] = w
            return w
        }()
        if let tab, let tabs = window.contentViewController as? NSTabViewController {
            tabs.selectedTabViewItemIndex = tab.rawValue
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func hosting<V: View>(_ view: V) -> NSViewController {
        let host = NSHostingController(rootView: view)
        host.sizingOptions = .preferredContentSize
        return host
    }

    static func showEdit(_ target: EditTarget, engine: ScrobbleEngine) {
        guard let (track, sent) = engine.editable(target) else { return }
        show(id: "edit", title: "Edit Scrobble", replace: true) {
            EditScrobbleView(target: target, track: track, alreadySent: sent).environmentObject(engine)
        }
    }
}
