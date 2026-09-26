import AppKit
import ApplicationServices

enum Carry {
    private static let source = CGEventSource(stateID: .privateState)

    static func run(_ window: Sky.Window, to space: Sky.Space) async -> Bool {
        if Bridge.move([window.id], to: space.id), await arrived(window.id, in: space.id) { return true }
        guard let number = space.number else { return false }
        if solo(window), await reassign(window, to: space) { return true }
        let title = window.title.isEmpty ? Access.titles(for: [window.pid])[window.id] ?? "" : window.title
        guard !title.isEmpty else { return false }
        let spot = bounds(window.id).map { CGPoint(x: $0.midX, y: $0.midY) }
        guard await Mission.drag(title, near: spot, to: "Desktop \(number)", on: space.display) else { return false }
        for _ in 0..<10 {
            if Sky.windows(in: [space.id]).contains(where: { $0.id == window.id }) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    static func arrived(_ id: UInt32, in space: UInt64) async -> Bool {
        for _ in 0..<20 {
            if Sky.windows(in: [space]).contains(where: { $0.id == id }) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private static func solo(_ window: Sky.Window) -> Bool {
        let siblings = Sky.windows(in: Sky.spaces().map(\.id)).filter { $0.pid == window.pid }
        let minimized = Access.windows(of: window.pid).filter { (Access.value($0.element, kAXMinimizedAttribute) as Bool?) == true }
        return siblings.count == 1 && minimized.isEmpty
    }

    private static func reassign(_ window: Sky.Window, to space: Sky.Space) async -> Bool {
        guard Sky.assign(window.pid, to: space.id) else { return false }
        defer { Sky.assign(window.pid, to: 0) }
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(100))
            if Sky.windows(in: [space.id]).contains(where: { $0.id == window.id }) { return true }
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

    static func fit(_ frame: CGRect?, from source: String, to target: String) -> CGRect? {
        guard let frame, let from = Sky.area(of: source), let to = Sky.area(of: target) else { return nil }
        guard source != target else { return frame }
        let x = to.width / from.width
        let y = to.height / from.height
        return CGRect(
            x: to.minX + (frame.minX - from.minX) * x,
            y: to.minY + (frame.minY - from.minY) * y,
            width: frame.width * x,
            height: frame.height * y
        )
    }

    static func bounds(_ id: UInt32) -> CGRect? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]])?.first,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary
        else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    private static func mouse(_ type: CGEventType, at point: CGPoint) {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        if type != .mouseMoved { event?.setIntegerValueField(.mouseEventClickState, value: 1) }
        event?.post(tap: .cghidEventTap)
    }
}
