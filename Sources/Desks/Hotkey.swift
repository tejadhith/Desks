import AppKit

@MainActor
final class Hotkey {
    var pressed: () -> Void = {}
    var released: () -> Void = {}
    var cancelled: () -> Void = {}
    private var monitors: [Any] = []
    private var down: TimeInterval?
    private var last: TimeInterval = 0
    private var dirty = false
    private var armed = false
    private let key: NSEvent.ModifierFlags

    init(_ key: NSEvent.ModifierFlags) {
        self.key = key
        let handle: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: handle) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { handle($0); return $0 }) {
            monitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        let now = event.timestamp
        guard event.type == .flagsChanged else {
            dirty = true
            last = 0
            if armed {
                armed = false
                cancelled()
            }
            return
        }
        let flags = event.modifierFlags.intersection([.control, .option, .command, .shift, .function])
        if flags == key, down == nil {
            dirty = false
            down = now
            if now - last < 0.4 {
                armed = true
                pressed()
            }
        } else if flags.isEmpty, let start = down {
            down = nil
            if armed {
                armed = false
                last = 0
                released()
            } else {
                last = !dirty && now - start < 0.3 ? now : 0
            }
        } else if !flags.isEmpty {
            dirty = true
            last = 0
            if armed {
                armed = false
                cancelled()
            }
        }
    }
}
