import AppKit
import Combine
import SwiftUI

@main
@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private var panel: Panel!
    private var status: NSStatusItem!
    private var agents: NSMenuItem!
    private var hosting: NSView!
    private var away: Away!
    private var grab: Grab!
    private var hotkey: Hotkey!
    private var option: Hotkey!
    private var presses = 0
    private var down = false
    private var peeking = false
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
        let view = NSHostingView(rootView: Note().environmentObject(store))
        view.sizingOptions = []
        view.autoresizingMask = [.width, .minYMargin]
        hosting = view
        let stage = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        stage.addSubview(view)
        panel.contentView = stage
        stretch()
        if let top = saved() {
            panel.setFrame(NSRect(x: top.x, y: top.y - Style.header, width: 300, height: Style.header), display: false)
        } else {
            panel.setFrameOrigin(NSPoint(x: corner().x - panel.frame.width, y: corner().y - panel.frame.height))
        }
        panel.orderFrontRegardless()
        if !Access.trusted { Access.prompt() }
        if Hooks.connected { Task.detached { Hooks.install() } }

        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Desks")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16.5, weight: .regular))
        let menu = NSMenu()
        menu.addItem(withTitle: "Show or Hide Tasks", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "Snap to Top Right", action: #selector(anchor), keyEquivalent: "")
        menu.addItem(withTitle: "Tuck Away or Bring Back (Double-Tap ⌃)", action: #selector(slide), keyEquivalent: "")
        menu.addItem(withTitle: "Collapse or Expand (Double-Tap ⌥)", action: #selector(shrink), keyEquivalent: "")
        menu.addItem(.separator())
        agents = menu.addItem(withTitle: "", action: #selector(connect), keyEquivalent: "")
        name()
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Desks", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        status.menu = menu

        Publishers.CombineLatest(store.$height, store.$collapsed)
            .sink { [weak self] height, collapsed in self?.fit(height, collapsed) }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.stretch() }
            .store(in: &bag)

        store.snap = { [weak self] in self?.anchor() }
        away = Away(panel: panel)
        grab = Grab(panel: panel, store: store)
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.publisher(for: name, object: panel)
                .sink { [weak self] _ in
                    guard let self, !self.away.moved() else { return }
                    self.track()
                    UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: self.panel.frame.minX, y: self.panel.frame.maxY)), forKey: "top")
                }
                .store(in: &bag)
        }
        track()

        hotkey = Hotkey(.control)
        hotkey.pressed = { [weak self] in self?.press() }
        hotkey.released = { [weak self] in self?.lift() }
        hotkey.cancelled = { [weak self] in self?.drop() }
        option = Hotkey(.option)
        option.released = { [weak self] in self?.fold() }
    }

    private func saved() -> NSPoint? {
        let defaults = UserDefaults.standard
        var top = defaults.string(forKey: "top").map(NSPointFromString)
        if top == nil {
            let values = (defaults.string(forKey: "NSWindow Frame Desks") ?? "").split(separator: " ").compactMap { Double($0) }
            if values.count >= 4 { top = NSPoint(x: values[0], y: values[1] + values[3]) }
        }
        guard let top else { return nil }
        let frame = NSRect(x: top.x, y: top.y - Style.header, width: 300, height: Style.header)
        return NSScreen.screens.contains { $0.frame.insetBy(dx: -2, dy: -2).contains(frame) } ? top : nil
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

    private func stretch() {
        let tallest = NSScreen.screens.map(\.visibleFrame.height).max() ?? 1000
        let stage = panel.contentView?.bounds ?? .zero
        hosting.frame = NSRect(x: 0, y: stage.height - tallest, width: stage.width, height: tallest)
    }

    private func fit(_ content: CGFloat, _ collapsed: Bool) {
        let screen = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let room = screen.height - 32
        let limit = room - Style.header
        if store.limit != limit { store.limit = limit }
        let overflow = content > limit
        if store.overflow != overflow { store.overflow = overflow }
        let height = collapsed ? Style.header : min(Style.header + content, room)
        guard abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        panel.setFrame(frame, display: false)
    }

    private func press() {
        guard !down else { return }
        down = true
        presses += 1
        let press = presses
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.down, self.presses == press else { return }
                self.peeking = true
                self.away.peek(true)
            }
        }
    }

    private func lift() {
        down = false
        if peeking {
            peeking = false
            away.peek(false)
        } else {
            slide()
        }
    }

    private func fold() {
        let mouse = NSEvent.mouseLocation
        if panel.isVisible, !store.collapsed, panel.frame.contains(mouse),
           store.fold(at: CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)) {
            return
        }
        shrink()
    }

    @objc private func shrink() {
        store.collapsed.toggle()
    }

    private func drop() {
        down = false
        if peeking {
            peeking = false
            away.peek(false)
        }
    }

    @objc private func slide() {
        guard panel.isVisible else {
            panel.orderFrontRegardless()
            return
        }
        away.toggle()
    }

    @objc private func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    private func name() {
        agents.title = Hooks.connected ? "Disconnect Coding Agents" : "Connect Coding Agents"
        agents.toolTip = "Claude Code, Codex, Devin and VS Code report their conversations to Desks through hooks"
    }

    @objc private func connect() {
        if Hooks.connected {
            Hooks.remove()
            store.tell("Disconnected coding agents. Desks removed its hooks from their settings.")
        } else {
            let agents = Hooks.install()
            if agents.isEmpty {
                store.tell("No supported coding agents found. Desks works with Claude Code, Codex, Devin and VS Code.")
            } else {
                let names = agents.map(\.name)
                let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1] : names[0]
                let codex = agents.contains(.codex) ? " In Codex, approve the Desks hooks with /hooks." : ""
                store.tell("Connected \(list). Conversations appear after their next prompt.\(codex)")
            }
        }
        name()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
