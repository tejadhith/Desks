import AppKit

@MainActor
final class Away {
    private let panel: Panel
    private let tab: CGFloat = 10
    private var rest: NSPoint?
    private var placed: NSPoint?
    private var moving = false
    private var moves = 0
    private var tucked = false
    private var right = true
    private var revealed = false
    private var leaving: Date?
    private var banner: NSRect?
    private var center: pid_t?
    private var heard: pid_t?
    private var observer: AXObserver?
    private var monitor: Any?
    private var checks: [DispatchWorkItem] = []
    private var later: DispatchWorkItem?
    private let edge = Edge()
    private var bag: [NSObjectProtocol] = []
    private static let notifications = "com.apple.notificationcenterui"

    init(panel: Panel) {
        self.panel = panel
        edge.crossed = { [weak self] in self?.step() }
        panel.contentView?.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: edge, userInfo: nil))
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            bag.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.listen() }
            })
        }
        bag.append(NotificationCenter.default.addObserver(forName: NSText.didEndEditingNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.step() }
        })
        listen()
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
        arm()
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
        arm()
        clip(false)
        return false
    }

    private func arm() {
        if tucked, monitor == nil {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
                MainActor.assumeIsolated { self?.step() }
            }
        } else if !tucked, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func listen() {
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Away.notifications).first?.processIdentifier
        guard pid != heard || observer == nil else { return }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        heard = pid
        guard let pid, Access.trusted else { return }
        var made: AXObserver?
        guard AXObserverCreate(pid, Away.callback, &made) == .success, let made else { return }
        let app = AXUIElementCreateApplication(pid)
        let me = Unmanaged.passUnretained(self).toOpaque()
        var added = 0
        for name in [kAXWindowCreatedNotification, kAXLayoutChangedNotification, kAXUIElementDestroyedNotification] where AXObserverAddNotification(made, app, name as CFString, me) == .success {
            added += 1
        }
        guard added > 0 else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(made), .commonModes)
        observer = made
    }

    private static let callback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let away = Unmanaged<Away>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated { away.spot() }
    }

    private func spot() {
        for check in checks { check.cancel() }
        checks = [0, 0.2, 0.6].map { delay in
            let check = DispatchWorkItem { [weak self] in self?.look() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: check)
            return check
        }
    }

    private func look() {
        let now = panel.isVisible ? banners() : nil
        if now != banner {
            banner = now
            settle()
        }
    }

    private func step() {
        guard tucked, !moving else { return }
        let mouse = NSEvent.mouseLocation
        if revealed {
            if panel.frame.insetBy(dx: -12, dy: -12).contains(mouse) || strip().contains(mouse) || panel.firstResponder is NSTextView {
                leaving = nil
                later?.cancel()
            } else if let leaving {
                guard Date().timeIntervalSince(leaving) > 0.4 else { return }
                revealed = false
                self.leaving = nil
                settle()
            } else {
                leaving = Date()
                let check = DispatchWorkItem { [weak self] in self?.step() }
                later = check
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: check)
            }
        } else if strip().contains(mouse) {
            revealed = true
            settle()
        }
    }

    private func strip() -> NSRect {
        let screen = screen(at: rest ?? top(panel.frame))
        var frame = panel.frame
        frame.origin.x = right ? screen.maxX - tab : screen.minX - frame.width + tab
        return frame.intersection(screen).insetBy(dx: -2, dy: 0)
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
        } else {
            clip(false)
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
        moves += 1
        let move = moves
        var frame = panel.frame
        frame.origin = NSPoint(x: point.x, y: point.y - frame.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.moves == move else { return }
                self.moving = false
                if self.tucked, !self.revealed, self.near(self.top(self.panel.frame), point) { self.clip(true) }
                done()
                self.step()
            }
        }
    }

    private func clip(_ on: Bool) {
        guard let view = panel.contentView else { return }
        view.wantsLayer = true
        if on {
            let frame = panel.frame
            guard let display = NSScreen.screens.max(by: { $0.frame.intersection(frame).width < $1.frame.intersection(frame).width })?.frame else { return }
            let shown = display.intersection(frame)
            guard !shown.isNull else { return }
            let mask = CALayer()
            mask.backgroundColor = NSColor.black.cgColor
            mask.frame = CGRect(x: shown.minX - frame.minX, y: 0, width: shown.width, height: display.height)
            view.layer?.mask = mask
        } else {
            guard view.layer?.mask != nil else { return }
            view.layer?.mask = nil
        }
        DispatchQueue.main.async { [weak self] in self?.panel.invalidateShadow() }
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

private final class Edge: NSResponder {
    var crossed: () -> Void = {}

    override func mouseEntered(with event: NSEvent) {
        crossed()
    }

    override func mouseExited(with event: NSEvent) {
        crossed()
    }
}
