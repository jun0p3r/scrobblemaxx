import AppKit
import SwiftUI

@main
struct ScrobblemaxxApp: App {
    @StateObject private var engine = ScrobbleEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(engine)
        } label: {
            Image(nsImage: MenuBarIcon.image(scrobbling: engine.playerState == .playing && engine.enabled))
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menu-bar icon: `music.note.arrow.trianglehead.clockwise` while scrobbling, `music.note.slash`
/// when idle. Those symbols are new in macOS 26, so older systems get look-alikes drawn from
/// symbols that exist there.
enum MenuBarIcon {
    private static var cache: [Bool: NSImage] = [:]

    static func image(scrobbling: Bool) -> NSImage {
        if let cached = cache[scrobbling] { return cached }
        let name = scrobbling ? "music.note.arrow.trianglehead.clockwise" : "music.note.slash"
        let label = scrobbling ? "Scrobbling" : "Idle"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
            ?? (scrobbling ? drawnScrobbling() : drawnIdle())
        image.isTemplate = true
        image.accessibilityDescription = label
        cache[scrobbling] = image
        return image
    }

    private static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
    }

    private static func drawCentered(_ image: NSImage?, in rect: NSRect, offset: NSPoint = .zero) {
        guard let image else { return }
        let s = image.size
        image.draw(in: NSRect(x: rect.midX - s.width / 2 + offset.x, y: rect.midY - s.height / 2 + offset.y,
                              width: s.width, height: s.height))
    }

    /// A small note inside a clockwise arrow, like the app icon.
    private static func drawnScrobbling() -> NSImage {
        NSImage(size: NSSize(width: 19, height: 18), flipped: false) { rect in
            drawCentered(symbol("arrow.trianglehead.clockwise", size: 16, weight: .medium), in: rect)
            drawCentered(symbol("music.note", size: 8, weight: .bold), in: rect, offset: NSPoint(x: 0, y: -0.5))
            return true
        }
    }

    /// A note with a knocked-out diagonal slash, matching SF Symbols' `.slash` style.
    private static func drawnIdle() -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            drawCentered(symbol("music.note", size: 14), in: rect)
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            let start = CGPoint(x: rect.minX + 3, y: rect.maxY - 2)
            let end = CGPoint(x: rect.maxX - 3, y: rect.minY + 2)
            ctx.setLineCap(.round)
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(4)
            ctx.strokeLineSegments(between: [start, end])
            ctx.setBlendMode(.normal)
            ctx.setLineWidth(1.6)
            ctx.strokeLineSegments(between: [start, end])
            return true
        }
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
