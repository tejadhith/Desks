import AppKit
import Combine
import SwiftUI

@main
@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private var panel: Panel!
    private var status: NSStatusItem!
    private var bag = Set<AnyCancellable>()

    static func main() {
        let app = NSApplication.shared
        let delegate = Delegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = Panel(frame: initial())
        let hosting = NSHostingView(rootView: Note().environmentObject(store))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrameUsingName("Desks")
        panel.setFrameAutosaveName("Desks")
        panel.setFrame(NSRect(x: panel.frame.minX, y: panel.frame.maxY - Style.header, width: 300, height: Style.header), display: false)
        panel.orderFrontRegardless()
        if !Access.trusted { Access.prompt() }

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Desks")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show or Hide Tasks", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "Snap to Top Right", action: #selector(anchor), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Desks", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        status.menu = menu

        Publishers.CombineLatest(store.$height, store.$collapsed)
            .sink { [weak self] height, collapsed in self?.fit(height, collapsed) }
            .store(in: &bag)

        store.snap = { [weak self] in self?.anchor() }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.publisher(for: name, object: panel)
                .sink { [weak self] _ in self?.track() }
                .store(in: &bag)
        }
        track()
    }

    private func corner() -> NSPoint {
        let screen = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        return NSPoint(x: screen.maxX - 16, y: screen.maxY - 16)
    }

    private func track() {
        let target = corner()
        store.anchored = abs(panel.frame.maxX - target.x) < 2 && abs(panel.frame.maxY - target.y) < 2
    }

    @objc private func anchor() {
        let target = corner()
        var frame = panel.frame
        frame.origin = NSPoint(x: target.x - frame.width, y: target.y - frame.height)
        panel.setFrame(frame, display: true, animate: true)
        panel.orderFrontRegardless()
    }

    private func initial() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: screen.maxX - 316, y: screen.maxY - 16 - Style.header, width: 300, height: Style.header)
    }

    private func fit(_ content: CGFloat, _ collapsed: Bool) {
        let screen = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let overflow = Style.header + content > screen.height - 32
        if store.overflow != overflow { store.overflow = overflow }
        let height = collapsed ? Style.header : min(Style.header + content, screen.height - 32)
        guard abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    @objc private func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
