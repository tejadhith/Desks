import AppKit
import Combine
import os

final class Chord: @unchecked Sendable {
    var act: () -> Void = {}
    private let state = OSAllocatedUnfairLock(initialState: (switching: false, held: false))
    private var tap: CFMachPort?

    func listen() {
        guard tap == nil else { return }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
        let info = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let chord = Unmanaged<Chord>.fromOpaque(info).takeUnretainedValue()
            return chord.handle(type, event) ? Unmanaged.passUnretained(event) : nil
        }, userInfo: info) else { return }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Chord"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        let flags = event.flags
        let command = flags.contains(.maskCommand) && !flags.contains(.maskAlternate) && !flags.contains(.maskControl)
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        return state.withLock { state in
            switch type {
            case .flagsChanged:
                if !flags.contains(.maskCommand) { state = (false, false) }
                return true
            case .keyDown where code == 49:
                if state.held { return false }
                guard command, state.switching else { return true }
                state = (false, true)
                DispatchQueue.main.async { [act] in act() }
                return false
            case .keyUp where code == 49:
                guard state.held else { return true }
                state.held = false
                return false
            case .keyDown where code == 48:
                if command { state.switching = true }
                return true
            case .keyDown where code == 53:
                state.switching = false
                return true
            default:
                return true
            }
        }
    }
}

@MainActor
final class Bring {
    private let store: Store
    private let chord = Chord()
    private var bag = Set<AnyCancellable>()

    init(store: Store) {
        self.store = store
        chord.act = { [weak self] in
            MainActor.assumeIsolated { self?.bring() }
        }
        store.$trusted
            .filter { $0 }
            .sink { [weak self] _ in self?.chord.listen() }
            .store(in: &bag)
    }

    private func bring() {
        guard let app = selected() else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let escape = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down)
            escape?.flags = .maskCommand
            escape?.post(tap: .cghidEventTap)
        }
        let here = Sky.current()
        let spaces = Sky.spaces()
        let rank = Sky.order()
        let all = Sky.windows(in: spaces.filter { $0.number != nil }.map(\.id))
            .filter { $0.pid == app.processIdentifier }
            .sorted { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
        guard let window = all.first(where: { $0.space == here }) ?? all.first else {
            if let url = app.bundleURL { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) }
            return
        }
        guard window.space != here else {
            Access.raise(window)
            return
        }
        guard let space = spaces.first(where: { $0.id == here }), space.number != nil else {
            store.focus(window)
            return
        }
        store.send(window, to: space)
    }

    private func selected() -> NSRunningApplication? {
        guard let dock = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else { return nil }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        guard let list = Access.children(element).first(where: { Access.value($0, kAXSubroleAttribute) == "AXProcessSwitcherList" }),
              let chosen: [AXUIElement] = Access.value(list, kAXSelectedChildrenAttribute),
              let item = chosen.first,
              let title: String = Access.value(item, kAXTitleAttribute)
        else { return nil }
        return NSWorkspace.shared.runningApplications.first { $0.activationPolicy == .regular && $0.localizedName == title }
    }
}
