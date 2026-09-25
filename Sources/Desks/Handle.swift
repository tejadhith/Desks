import SwiftUI

struct Handle: NSViewRepresentable {
    let tap: () -> Void

    func makeNSView(context: Context) -> NSView {
        let grip = Grip()
        grip.tap = tap
        return grip
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? Grip)?.tap = tap
    }

    private final class Grip: NSView {
        var tap: () -> Void = {}

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let start = NSEvent.mouseLocation
            let origin = window.frame.origin
            var moved = false
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged {
                let now = NSEvent.mouseLocation
                if !moved && hypot(now.x - start.x, now.y - start.y) < 3 { continue }
                moved = true
                window.setFrameOrigin(NSPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y))
            }
            if !moved { tap() }
        }
    }
}
