import AppKit
import SwiftUI

@MainActor
final class Glide: NSObject {
    static let curve = UnitCurve.easeInOut

    static func duration(for span: CGFloat) -> Double {
        min(0.32, max(0.16, 0.12 + Double(abs(span)) / 1500))
    }

    static func animation(_ duration: Double) -> Animation {
        .timingCurve(curve, duration: duration)
    }

    private var link: CADisplayLink?
    private var start: CFTimeInterval?
    private var length = 0.2
    private var goal: CGFloat = 0
    private var done: CGFloat = 0
    private var last: CGFloat?

    func add(_ drift: CGFloat, over duration: Double?) {
        if link != nil {
            goal += drift
            return
        }
        guard let duration, let view = Panel.main?.contentView else {
            move(drift)
            last = nil
            return
        }
        goal = drift
        length = duration
        let link = view.displayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        let start = start ?? link.targetTimestamp
        self.start = start
        let t = min(1, max(0, (link.targetTimestamp - start) / length))
        let target = goal * CGFloat(Self.curve.value(at: t))
        move(target - done)
        done = target
        if t >= 1 { stop() }
    }

    private func move(_ step: CGFloat) {
        guard let top = NSScreen.screens.first?.frame.maxY else { return }
        let mouse = NSEvent.mouseLocation
        let y = top - mouse.y
        let base = last.map { abs(y - $0) > 1.5 ? y : $0 } ?? y
        let next = base + step
        CGWarpMouseCursorPosition(CGPoint(x: mouse.x, y: next))
        CGAssociateMouseAndMouseCursorPosition(1)
        last = next
    }

    private func stop() {
        link?.invalidate()
        link = nil
        start = nil
        goal = 0
        done = 0
        last = nil
        DispatchQueue.main.async { Panel.main?.invalidateShadow() }
    }
}
