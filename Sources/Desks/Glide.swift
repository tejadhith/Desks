import AppKit
import SwiftUI

@MainActor
final class Glide {
    static let curve = UnitCurve.easeInOut

    static func duration(for span: CGFloat) -> Double {
        min(0.32, max(0.16, 0.12 + Double(abs(span)) / 1500))
    }

    static func animation(_ duration: Double) -> Animation {
        .timingCurve(curve, duration: duration)
    }

    private var goal: CGFloat = 0
    private var done: CGFloat = 0
    private var last: CGFloat?
    private var from: Double = 0
    private var to: Double = 0
    private var value: Double = 0
    private var running = false

    func add(_ drift: CGFloat, until clock: Double?) {
        guard let clock else {
            if running {
                goal += drift
            } else {
                move(drift)
                last = nil
            }
            return
        }
        if running {
            goal = goal - done + drift
            from = value
        } else {
            goal = drift
            from = clock - 1
            running = true
        }
        done = 0
        to = clock
    }

    func tick(_ now: Double) {
        guard now != value else { return }
        let then = value
        value = now
        guard running, to != from else { return }
        let progress = CGFloat(min(1, max(0, (now - from) / (to - from))))
        let late = CGFloat(min(1, max(0, (then - from) / (to - from))))
        let target = goal * (progress >= 1 ? 1 : late)
        move(target - done)
        done = target
        if progress >= 1 { stop() }
    }

    private func move(_ step: CGFloat) {
        guard let top = NSScreen.screens.first?.frame.maxY, let panel = Panel.main?.frame else { return }
        let mouse = NSEvent.mouseLocation
        let y = top - mouse.y
        let base = last.map { abs(y - $0) > 1.5 ? y : $0 } ?? y
        let floor = min(base, top - panel.maxY + Style.header + 1)
        let ceiling = max(base, top - panel.minY - 1)
        let next = min(ceiling, max(floor, base + step))
        CGWarpMouseCursorPosition(CGPoint(x: mouse.x, y: next))
        CGAssociateMouseAndMouseCursorPosition(1)
        last = next
    }

    private func stop() {
        running = false
        goal = 0
        done = 0
        last = nil
        DispatchQueue.main.async { Panel.main?.invalidateShadow() }
    }
}

struct Clock: ViewModifier, Animatable {
    var value: Double
    let tick: (Double) -> Void

    var animatableData: Double {
        get { value }
        set {
            value = newValue
            tick(newValue)
        }
    }

    func body(content: Content) -> some View { content }
}
