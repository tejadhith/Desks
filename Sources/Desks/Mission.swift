import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum Mission {
    private static let app = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
    private static let source = CGEventSource(stateID: .hidSystemState)

    private static var root: AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        return Access.children(element).first { Access.identifier($0) == "mc" }
    }

    static var isOpen: Bool { root != nil }

    static func open() {
        guard !isOpen else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func close() async {
        for _ in 0..<10 where isOpen {
            Keys.press(CGKeyCode(kVK_Escape))
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    static func add(on display: String) async -> Bool {
        open()
        guard let screen = await screen(display), let button = search(screen, "mc.spaces.add", depth: 0) else {
            await close()
            return false
        }
        return Access.press(button)
    }

    static func remove(at index: Int, on display: String) async -> Bool {
        open()
        guard let button = await space(at: index, on: display) else {
            await close()
            return false
        }
        let done = Access.press(button, "AXRemoveDesktop")
        try? await Task.sleep(for: .milliseconds(300))
        await close()
        return done
    }

    static func go(to index: Int, on display: String) async -> Bool {
        open()
        guard let button = await space(at: index, on: display) else {
            await close()
            return false
        }
        return Access.press(button)
    }

    static func drag(_ title: String, near spot: CGPoint?, to label: String, on display: String) async -> Bool {
        open()
        guard let screen = await screen(display) else {
            await close()
            return false
        }
        try? await Task.sleep(for: .milliseconds(800))
        var thumbs: [AXUIElement] = []
        for _ in 0..<30 where thumbs.isEmpty {
            if let windows = search(screen, "mc.windows", depth: 0) {
                thumbs = matches(title, in: Access.children(windows))
            }
            if thumbs.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        }
        guard let thumb = pick(thumbs, near: spot, on: display, in: screen),
              let start = await settle(thumb).map(center),
              let list = search(screen, "mc.spaces.list", depth: 0),
              let first = button(label, in: list)
        else {
            await close()
            return false
        }
        let cursor = CGEvent(source: nil)?.location ?? .zero
        defer { CGWarpMouseCursorPosition(cursor) }
        let hover = CGPoint(x: first.x, y: first.y + 40)
        mouse(.mouseMoved, at: start)
        try? await Task.sleep(for: .milliseconds(100))
        mouse(.leftMouseDown, at: start)
        try? await Task.sleep(for: .milliseconds(300))
        await glide(from: start, to: hover, steps: 30)
        try? await Task.sleep(for: .milliseconds(600))
        let target = button(label, in: list) ?? first
        await glide(from: hover, to: target, steps: 10)
        try? await Task.sleep(for: .milliseconds(400))
        mouse(.leftMouseUp, at: target)
        try? await Task.sleep(for: .milliseconds(700))
        await close()
        return true
    }

    private static func matches(_ title: String, in thumbs: [AXUIElement]) -> [AXUIElement] {
        let named = thumbs.compactMap { thumb in (Access.value(thumb, kAXTitleAttribute) as String?).map { (thumb, $0) } }
        let exact = named.filter { $0.1 == title }
        if !exact.isEmpty { return exact.map(\.0) }
        return named.filter { !$0.1.isEmpty && (title.hasPrefix($0.1) || $0.1.hasPrefix(title)) }.map(\.0)
    }

    private static func settle(_ thumb: AXUIElement) async -> CGRect? {
        var last = Access.frame(thumb)
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(80))
            let now = Access.frame(thumb)
            if let now, now == last { return now }
            last = now
        }
        return last
    }

    private static func pick(_ thumbs: [AXUIElement], near spot: CGPoint?, on display: String, in screen: AXUIElement) -> AXUIElement? {
        guard thumbs.count > 1, let spot, let frame = Sky.frame(of: display),
              let area = search(screen, "mc.windows", depth: 0).flatMap(Access.frame)
        else { return thumbs.first }
        let goal = CGPoint(x: (spot.x - frame.minX) / frame.width, y: (spot.y - frame.minY) / frame.height)
        return thumbs.min { lhs, rhs in
            distance(lhs, goal, area) < distance(rhs, goal, area)
        }
    }

    private static func distance(_ thumb: AXUIElement, _ goal: CGPoint, _ area: CGRect) -> CGFloat {
        guard let point = Access.frame(thumb).map(center) else { return .infinity }
        return hypot((point.x - area.minX) / area.width - goal.x, (point.y - area.minY) / area.height - goal.y)
    }

    private static func button(_ label: String, in list: AXUIElement) -> CGPoint? {
        Access.children(list)
            .first { (Access.value($0, kAXTitleAttribute) as String?) == label }
            .flatMap(Access.frame)
            .map(center)
    }

    private static func center(_ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    private static func glide(from start: CGPoint, to end: CGPoint, steps: Int) async {
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            mouse(.leftMouseDragged, at: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    private static func mouse(_ type: CGEventType, at point: CGPoint) {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        if type != .mouseMoved { event?.setIntegerValueField(.mouseEventClickState, value: 1) }
        event?.post(tap: .cghidEventTap)
    }

    private static func space(at index: Int, on display: String) async -> AXUIElement? {
        guard let screen = await screen(display) else { return nil }
        for _ in 0..<40 {
            if let list = search(screen, "mc.spaces.list", depth: 0) {
                let buttons = Access.children(list)
                if buttons.indices.contains(index) { return buttons[index] }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private static func screen(_ display: String) async -> AXUIElement? {
        let frame = Sky.frame(of: display)
        for _ in 0..<40 {
            if let root {
                let screens = Access.children(root).filter { Access.identifier($0) == "mc.display" }
                let match = screens.first { screen in
                    guard let frame, let box = Access.frame(screen) else { return false }
                    return abs(box.minX - frame.minX) < 2 && abs(box.minY - frame.minY) < 2
                }
                if let match { return match }
                if screens.count == 1 { return screens[0] }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private static func search(_ element: AXUIElement, _ identifier: String, depth: Int) -> AXUIElement? {
        if Access.identifier(element) == identifier { return element }
        guard depth < 6 else { return nil }
        for child in Access.children(element) {
            if let found = search(child, identifier, depth: depth + 1) { return found }
        }
        return nil
    }
}
