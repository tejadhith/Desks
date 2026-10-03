import AppKit
import Combine
import SwiftUI

@MainActor
final class Brow {
    private let store: Store
    private var flaps: [UInt64: Flap] = [:]
    private var seen = Sky.visible()
    private var active = Sky.current()
    private var bag = Set<AnyCancellable>()

    init(store: Store) {
        self.store = store
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .sink { [weak self] _ in self?.turn() }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &bag)
        Publishers.CombineLatest(store.$spaces, store.$items)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &bag)
        Sky.listen { [weak self] code, window in
            DispatchQueue.main.async { self?.heard(code, window) }
        }
    }

    private func heard(_ code: UInt32, _ window: UInt32?) {
        guard code == 1329 || ((code == 1325 || code == 1326) && flaps.values.contains { $0.id == window }) else { return }
        turn()
    }

    private func turn() {
        let visible = Sky.visible()
        let current = Sky.current()
        for (id, flap) in flaps {
            if !flap.pinned {
                flap.pin()
            } else if !visible.contains(id) {
                flap.hide()
            }
        }
        for id in visible.subtracting(seen) { flaps[id]?.show() }
        if current != active { flaps[current]?.show() }
        seen = visible
        active = current
    }

    private func sync() {
        let spaces = store.spaces.filter { $0.number != nil }
        for (id, flap) in flaps where !spaces.contains(where: { $0.id == id }) {
            flap.close()
            flaps[id] = nil
        }
        for space in spaces {
            guard let number = space.number, let name = store.here(on: space.id)?.name,
                  let screen = Sky.screen(space.display)
            else { continue }
            let perch = perch(of: screen)
            if let flap = flaps[space.id] {
                flap.set(number, name, perch)
            } else {
                let flap = Flap(space: space.id, perch: perch)
                flap.set(number, name, perch)
                flaps[space.id] = flap
            }
        }
        turn()
    }

    private func perch(of screen: NSScreen) -> Perch {
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            let height = screen.safeAreaInsets.top + Tab.drop
            return Perch(frame: CGRect(x: left.maxX, y: screen.frame.maxY - height, width: right.minX - left.maxX, height: height), pill: false)
        }
        let height = Tab.drop + Tab.gap
        return Perch(frame: CGRect(x: screen.frame.midX - Tab.span / 2, y: screen.visibleFrame.maxY - height, width: Tab.span, height: height), pill: true)
    }
}

@MainActor
private final class Flap {
    private let space: UInt64
    private let wave = Wave()
    private let window: NSWindow
    private let host: NSHostingView<Tab>
    private var fading: DispatchWorkItem?
    private var hiding: DispatchWorkItem?

    init(space: UInt64, perch: Perch) {
        self.space = space
        host = NSHostingView(rootView: Tab(wave: wave))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        window = NSWindow(contentRect: perch.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 1)
        window.collectionBehavior = [.ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.alphaValue = 0
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: perch.frame.size)
        window.orderFrontRegardless()
    }

    var id: UInt32 {
        UInt32(window.windowNumber)
    }

    var pinned: Bool {
        Sky.spaces(of: UInt32(window.windowNumber)) == [space]
    }

    func pin() {
        hide()
        Sky.pin(UInt32(window.windowNumber), to: space)
    }

    func set(_ number: Int, _ name: String, _ perch: Perch) {
        if wave.number != number { wave.number = number }
        if wave.name != name { wave.name = name }
        if wave.pill != perch.pill { wave.pill = perch.pill }
        guard window.frame != perch.frame else { return }
        window.setFrame(perch.frame, display: false)
        host.frame = CGRect(origin: .zero, size: perch.frame.size)
    }

    func hide() {
        guard wave.up || window.alphaValue > 0 else { return }
        cancel()
        wave.up = false
        window.alphaValue = 0
    }

    func show() {
        cancel()
        if !wave.up {
            window.alphaValue = 1
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: Tab.fall)) { self.wave.up = true }
            }
        }
        let work = DispatchWorkItem { [weak self] in self?.lift() }
        fading = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func close() {
        cancel()
        window.orderOut(nil)
        window.close()
    }

    private func lift() {
        guard wave.up else { return }
        withAnimation(.easeOut(duration: Tab.out)) { wave.up = false }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.wave.up else { return }
            self.window.alphaValue = 0
        }
        hiding = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Tab.out, execute: work)
    }

    private func cancel() {
        fading?.cancel()
        hiding?.cancel()
    }
}

private struct Perch {
    let frame: CGRect
    let pill: Bool
}

@MainActor
private final class Wave: ObservableObject {
    @Published var number = 0
    @Published var name = ""
    @Published var pill = false
    @Published var up = false
}

private struct Tab: View {
    static let drop: CGFloat = 24
    static let gap: CGFloat = 8
    static let hem: CGFloat = 10
    static let bend: CGFloat = 8
    static let span: CGFloat = 320
    static let fall = 0.26
    static let out = 0.22
    @ObservedObject var wave: Wave

    var body: some View {
        if wave.pill {
            label
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(height: Self.drop)
                .background(Color.black.opacity(0.9), in: bead)
                .overlay(bead.strokeBorder(Color.ink.opacity(0.14)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .offset(y: wave.up ? 0 : -Self.gap)
                .opacity(wave.up ? 1 : 0)
        } else {
            label
                .padding(.horizontal, 10)
                .frame(height: Self.drop)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .background(Color.black)
                .clipShape(.rect(bottomLeadingRadius: Self.hem, bottomTrailingRadius: Self.hem))
                .offset(y: wave.up ? 0 : -Self.drop)
        }
    }

    private var bead: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.bend, style: .continuous)
    }

    private var label: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Text("\(wave.number)")
                .font(.grotesk(10, .bold))
                .monospacedDigit()
                .frame(width: 18, height: 14)
                .foregroundStyle(Color.black)
                .background(Color.ink, in: RoundedRectangle(cornerRadius: 3))
            Text(wave.name)
                .font(.grotesk(11, .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.ink)
    }
}
