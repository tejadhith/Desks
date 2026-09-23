import AppKit
import ApplicationServices

enum Carry {
    private static let grips: Set<String> = [
        kAXWindowRole, kAXToolbarRole, kAXGroupRole, kAXStaticTextRole, kAXUnknownRole, kAXTabGroupRole,
    ]

    private static let controls: Set<String> = [
        kAXButtonRole, kAXRadioButtonRole, kAXPopUpButtonRole, kAXMenuButtonRole, kAXCheckBoxRole,
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXLink",
    ]

    private static let source = CGEventSource(stateID: .privateState)

    static func run(_ window: Sky.Window, to space: Sky.Space) async -> Bool {
        guard let number = space.number else { return false }
        Access.raise(window)
        try? await Task.sleep(for: .milliseconds(250))
        guard let element = Access.windows(of: window.pid).first(where: { $0.id == window.id })?.element,
              let frame = Access.frame(element)
        else { return false }
        let cursor = CGEvent(source: nil)?.location ?? .zero
        defer { CGWarpMouseCursorPosition(cursor) }
        for point in candidates(element, frame, pid: window.pid).prefix(6) {
            guard await grab(window.id, at: point, from: frame.origin) else { continue }
            _ = Keys.desktop(number)
            for _ in 0..<15 where Sky.current() != space.id {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(250))
            mouse(.leftMouseUp, at: point.applying(.init(translationX: 12, y: 0)))
            try? await Task.sleep(for: .milliseconds(200))
            Access.move(element, to: frame.origin)
            return Sky.windows(in: [space.id]).contains { $0.id == window.id }
        }
        return false
    }

    static func tap(_ point: CGPoint) {
        let cursor = CGEvent(source: nil)?.location ?? .zero
        mouse(.mouseMoved, at: point)
        mouse(.leftMouseDown, at: point)
        mouse(.leftMouseUp, at: point)
        CGWarpMouseCursorPosition(cursor)
    }

    static func place(_ window: Sky.Window, in frame: CGRect) -> Bool {
        guard let element = Access.windows(of: window.pid).first(where: { $0.id == window.id })?.element,
              let size = Access.frame(element)?.size
        else { return false }
        let origin = CGPoint(
            x: frame.minX + max(0, (frame.width - size.width) / 2),
            y: frame.minY + max(40, (frame.height - size.height) / 2)
        )
        Access.move(element, to: origin)
        return true
    }

    private static func grab(_ id: UInt32, at point: CGPoint, from origin: CGPoint) async -> Bool {
        mouse(.mouseMoved, at: point)
        try? await Task.sleep(for: .milliseconds(40))
        mouse(.leftMouseDown, at: point)
        try? await Task.sleep(for: .milliseconds(80))
        for step in 1...4 {
            mouse(.leftMouseDragged, at: point.applying(.init(translationX: CGFloat(step * 3), y: 0)), delta: 3)
            try? await Task.sleep(for: .milliseconds(30))
        }
        try? await Task.sleep(for: .milliseconds(120))
        if let moved = bounds(id)?.origin, abs(moved.x - origin.x) >= 3 { return true }
        mouse(.leftMouseUp, at: point.applying(.init(translationX: 12, y: 0)))
        try? await Task.sleep(for: .milliseconds(100))
        return false
    }

    private static func candidates(_ element: AXUIElement, _ frame: CGRect, pid: pid_t) -> [CGPoint] {
        let zoom = Access.value(element, kAXZoomButtonAttribute).flatMap { (button: AXUIElement) in Access.frame(button) }
        let left = (zoom?.maxX ?? frame.minX + 70) + 14
        let rows = [zoom?.midY ?? frame.minY + 12, frame.minY + 6]
        var points: [CGPoint] = []
        for y in rows {
            for x in stride(from: left, through: frame.maxX - 40, by: 24) {
                let point = CGPoint(x: x, y: y)
                if draggable(point, pid: pid) { points.append(point) }
            }
        }
        return points
    }

    private static func draggable(_ point: CGPoint, pid: pid_t) -> Bool {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit
        else { return false }
        var owner: pid_t = 0
        AXUIElementGetPid(hit, &owner)
        guard owner == pid, let role: String = Access.value(hit, kAXRoleAttribute), grips.contains(role) else { return false }
        let parent: AXUIElement? = Access.value(hit, kAXParentAttribute)
        let above: String? = parent.flatMap { Access.value($0, kAXRoleAttribute) }
        return !controls.contains(above ?? "")
    }

    private static func bounds(_ id: UInt32) -> CGRect? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]])?.first,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary
        else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    private static func mouse(_ type: CGEventType, at point: CGPoint, delta: Int64 = 0) {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        if type != .mouseMoved { event?.setIntegerValueField(.mouseEventClickState, value: 1) }
        if delta != 0 { event?.setIntegerValueField(.mouseEventDeltaX, value: delta) }
        event?.post(tap: .cghidEventTap)
    }
}
