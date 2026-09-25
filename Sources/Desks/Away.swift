import AppKit

@MainActor
final class Away {
    private let panel: Panel
    private let tab: CGFloat = 10
    private var rest: NSPoint?
    private var placed: NSPoint?
    private var moving = false
    private var tucked = false
    private var right = true
    private var revealed = false
    private var leaving: Date?
    private var banner: NSRect?
    private var center: pid_t?
    private var tick = 0
    private var timer: Timer?

    init(panel: Panel) {
        self.panel = panel
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    func peek(_ on: Bool) {
        panel.ignoresMouseEvents = on
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = on ? 0.08 : 1
        }
    }

    func toggle() {
        if !tucked {
            let home = rest ?? top(panel.frame)
            let screen = screen(at: home)
            right = home.x + panel.frame.width / 2 > screen.midX
        }
        tucked.toggle()
        revealed = false
        leaving = nil
        settle()
    }

    func moved() -> Bool {
        if moving { return true }
        guard rest != nil else { return false }
        if let placed, near(top(panel.frame), placed) { return true }
        rest = nil
        placed = nil
        tucked = false
        revealed = false
        return false
    }

    private func step() {
        tick += 1
        if tick % 3 == 0 {
            let now = panel.isVisible ? banners() : nil
            if now != banner {
                banner = now
                settle()
            }
        }
        guard tucked, !moving else { return }
        let mouse = NSEvent.mouseLocation
        if revealed {
            if panel.frame.insetBy(dx: -12, dy: -12).contains(mouse) || panel.firstResponder is NSTextView {
                leaving = nil
            } else if let leaving {
                guard Date().timeIntervalSince(leaving) > 0.4 else { return }
                revealed = false
                self.leaving = nil
                settle()
            } else {
                leaving = Date()
            }
        } else if panel.frame.intersection(screen(at: rest ?? top(panel.frame))).insetBy(dx: -2, dy: 0).contains(mouse) {
            revealed = true
            settle()
        }
    }

    private func settle() {
        let home = rest ?? top(panel.frame)
        let size = panel.frame.size
        var goal = home
        if let banner, banner.intersects(NSRect(x: home.x, y: home.y - size.height, width: size.width, height: size.height).insetBy(dx: -8, dy: -8)) {
            goal.y = min(goal.y, banner.minY - 8)
        }
        if tucked && !revealed {
            let screen = screen(at: home)
            goal.x = right ? screen.maxX - tab : screen.minX - size.width + tab
        }
        if near(goal, home) {
            guard rest != nil else { return }
            place(home) { [weak self] in
                guard let self, self.near(self.top(self.panel.frame), home) else { return }
                self.rest = nil
                self.placed = nil
            }
        } else {
            if rest == nil { rest = home }
            place(goal) {}
        }
    }

    private func place(_ point: NSPoint, then done: @escaping () -> Void) {
        placed = point
        moving = true
        var frame = panel.frame
        frame.origin = NSPoint(x: point.x, y: point.y - frame.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.moving = false
                done()
            }
        }
    }

    private func top(_ frame: NSRect) -> NSPoint {
        NSPoint(x: frame.minX, y: frame.maxY)
    }

    private func near(_ a: NSPoint, _ b: NSPoint) -> Bool {
        abs(a.x - b.x) < 1 && abs(a.y - b.y) < 1
    }

    private func screen(at point: NSPoint) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: point.x + 1, y: point.y - 1)) } ?? panel.screen ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    private func banners() -> NSRect? {
        if center == nil || NSRunningApplication(processIdentifier: center ?? 0) == nil {
            center = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first?.processIdentifier
        }
        guard let center else { return nil }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        guard list.contains(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == center && ($0[kCGWindowLayer as String] as? Int ?? 0) > 0 }) else { return nil }
        let app = AXUIElementCreateApplication(center)
        AXUIElementSetMessagingTimeout(app, 0.2)
        let windows: [AXUIElement] = Access.value(app, kAXWindowsAttribute) ?? []
        let frames = windows.flatMap { find($0, depth: 0) }
        guard let first = frames.first, let top = NSScreen.screens.first?.frame.maxY else { return nil }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        return NSRect(x: union.minX, y: top - union.maxY, width: union.width, height: union.height)
    }

    private func find(_ element: AXUIElement, depth: Int) -> [CGRect] {
        if (Access.value(element, kAXSubroleAttribute) as String?) == "AXNotificationCenterBanner" {
            return Access.frame(element).map { [$0] } ?? []
        }
        guard depth < 6 else { return [] }
        return Access.children(element).flatMap { find($0, depth: depth + 1) }
    }
}
