import AppKit
import ApplicationServices

@MainActor
final class Scout {
    private static let app = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXApplicationHiddenNotification, kAXApplicationShownNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification]
    private static let window = [kAXTitleChangedNotification, kAXUIElementDestroyedNotification]

    private var observers: [pid_t: AXObserver] = [:]
    private var seen: [pid_t: Set<UInt32>] = [:]
    private var bag: [NSObjectProtocol] = []
    private let changed: () -> Void
    private let focused: () -> Void
    private let titled: (UInt32, String) -> Void

    init(changed: @escaping () -> Void, focused: @escaping () -> Void, titled: @escaping (UInt32, String) -> Void) {
        self.changed = changed
        self.focused = focused
        self.titled = titled
        let center = NSWorkspace.shared.notificationCenter
        bag.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.activationPolicy == .regular else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.observe(pid) }
        })
        bag.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else { return }
            MainActor.assumeIsolated { self?.forget(pid) }
        })
        scan()
    }

    func scan() {
        guard Access.trusted else { return }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular { observe(app.processIdentifier) }
    }

    func attach(_ windows: [UInt32: (pid: pid_t, element: AXUIElement, title: String)]) {
        let me = Unmanaged.passUnretained(self).toOpaque()
        for (id, window) in windows where seen[window.pid]?.contains(id) != true {
            observe(window.pid)
            guard let observer = observers[window.pid] else { continue }
            for name in Scout.window { AXObserverAddNotification(observer, window.element, name as CFString, me) }
            seen[window.pid, default: []].insert(id)
        }
    }

    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil, pid != getpid(), Access.trusted else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, Scout.callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let me = Unmanaged.passUnretained(self).toOpaque()
        for name in Scout.app { AXObserverAddNotification(observer, app, name as CFString, me) }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
    }

    private func forget(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        seen[pid] = nil
    }

    private static let callback: AXObserverCallback = { _, element, name, refcon in
        guard let refcon else { return }
        let scout = Unmanaged<Scout>.fromOpaque(refcon).takeUnretainedValue()
        let name = name as String
        MainActor.assumeIsolated { scout.heard(element, name) }
    }

    private func heard(_ element: AXUIElement, _ name: String) {
        switch name {
        case kAXTitleChangedNotification:
            guard (Access.value(element, kAXRoleAttribute) as String?) == kAXWindowRole, let id = Access.id(of: element),
                  let title: String = Access.value(element, kAXTitleAttribute)
            else { return }
            titled(id, title)
        case kAXFocusedWindowChangedNotification:
            focused()
        case kAXUIElementDestroyedNotification:
            changed()
            focused()
        default:
            changed()
        }
    }
}
