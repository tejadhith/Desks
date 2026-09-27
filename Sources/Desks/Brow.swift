import AppKit
import Combine
import SwiftUI

@MainActor
final class Brow {
    private let store: Store
    private let wave = Wave()
    private let window: NSWindow
    private let host: NSHostingView<Tab>
    private var bag = Set<AnyCancellable>()
    private var fading: DispatchWorkItem?
    private var hiding: DispatchWorkItem?

    init(store: Store) {
        self.store = store
        host = NSHostingView(rootView: Tab(wave: wave))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: Tab.drop), styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        store.$current
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] id in self?.show(id) }
            .store(in: &bag)
    }

    private func show(_ id: UInt64) {
        fading?.cancel()
        hiding?.cancel()
        guard let (space, name) = store.here(on: id), let number = space.number,
              let screen = Sky.screen(space.display)
        else { return dim() }
        let perch = perch(of: screen)
        wave.number = number
        wave.name = name
        wave.pill = perch.pill
        window.setFrame(perch.frame, display: false)
        host.frame = CGRect(origin: .zero, size: perch.frame.size)
        window.orderFrontRegardless()
        DispatchQueue.main.async { self.wave.up = true }
        let work = DispatchWorkItem { [weak self] in self?.dim() }
        fading = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func dim() {
        fading?.cancel()
        guard wave.up else { return }
        wave.up = false
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.wave.up else { return }
            self.window.orderOut(nil)
        }
        hiding = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Tab.out, execute: work)
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
    static let span: CGFloat = 320
    static let out = 0.22
    @ObservedObject var wave: Wave

    var body: some View {
        if wave.pill {
            label
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(height: Self.drop)
                .background(Color.black.opacity(0.9), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.ink.opacity(0.14)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .offset(y: wave.up ? 0 : -Self.gap)
                .opacity(wave.up ? 1 : 0)
                .animation(.easeOut(duration: wave.up ? 0.26 : Self.out), value: wave.up)
        } else {
            label
                .padding(.horizontal, 10)
                .frame(height: Self.drop)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .background(Color.black)
                .clipShape(.rect(bottomLeadingRadius: Self.hem, bottomTrailingRadius: Self.hem))
                .offset(y: wave.up ? 0 : -Self.drop)
                .animation(.easeOut(duration: wave.up ? 0.26 : Self.out), value: wave.up)
        }
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
