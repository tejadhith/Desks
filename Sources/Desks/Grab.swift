import AppKit

@MainActor
final class Grab {
    private let panel: NSPanel
    private let store: Store
    private var monitor: Any?
    private var window: UInt32?
    private var start: CGRect?
    private var moving = false

    init(panel: NSPanel, store: Store) {
        self.panel = panel
        self.store = store
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
        }
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            moving = false
            (window, start) = under(NSEvent.mouseLocation).map { ($0.id, $0.bounds) } ?? (nil, nil)
        case .leftMouseDragged:
            guard let window, let start else { return }
            if !moving {
                guard let now = Carry.bounds(window), now.size == start.size,
                      abs(now.minX - start.minX) + abs(now.minY - start.minY) > 2
                else { return }
                moving = true
            }
            store.hover(point(NSEvent.mouseLocation))
        case .leftMouseUp:
            defer {
                window = nil
                start = nil
                moving = false
            }
            guard moving, let window, let start else { return }
            if let point = point(NSEvent.mouseLocation) {
                store.take(window, at: point, back: start)
            } else {
                store.hover(nil)
            }
        default:
            break
        }
    }

    private func point(_ location: NSPoint) -> CGPoint? {
        let frame = panel.frame
        guard panel.isVisible, panel.alphaValue > 0.5, frame.contains(location) else { return nil }
        return CGPoint(x: location.x - frame.minX, y: frame.maxY - location.y)
    }

    private func under(_ location: NSPoint) -> (id: UInt32, bounds: CGRect)? {
        guard let top = NSScreen.screens.first?.frame.maxY else { return nil }
        let point = CGPoint(x: location.x, y: top - location.y)
        let me = getpid()
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for entry in info {
            guard let id = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  entry[kCGWindowLayer as String] as? Int == 0,
                  let raw = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary),
                  bounds.contains(point)
            else { continue }
            guard pid != me else { return nil }
            return (id, bounds)
        }
        return nil
    }
}
