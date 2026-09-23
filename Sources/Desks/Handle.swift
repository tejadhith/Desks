import SwiftUI

struct Handle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Grip() }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class Grip: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
