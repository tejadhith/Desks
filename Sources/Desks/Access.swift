import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func windowID(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

@_silgen_name("GetProcessForPID")
private func process(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

enum Access {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func settings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    static func value<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) ?? []
    }

    static func identifier(_ element: AXUIElement) -> String? {
        value(element, kAXIdentifierAttribute)
    }

    static func press(_ element: AXUIElement, _ action: String = kAXPressAction) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    static func windows(of pid: pid_t) -> [(id: UInt32, element: AXUIElement)] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let windows: [AXUIElement] = value(app, kAXWindowsAttribute) ?? []
        return windows.compactMap { element in
            var id: CGWindowID = 0
            guard windowID(element, &id) == .success else { return nil }
            return (id, element)
        }
    }

    static func titles(for pids: Set<pid_t>) -> [UInt32: String] {
        var titles: [UInt32: String] = [:]
        for pid in pids {
            for window in windows(of: pid) {
                if let title: String = value(window.element, kAXTitleAttribute), !title.isEmpty {
                    titles[window.id] = title
                }
            }
        }
        return titles
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position: AXValue = value(element, kAXPositionAttribute),
              let size: AXValue = value(element, kAXSizeAttribute)
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        AXValueGetValue(position, .cgPoint, &origin)
        AXValueGetValue(size, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }

    static func move(_ element: AXUIElement, to origin: CGPoint) {
        var origin = origin
        guard let position = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
    }

    static func front() -> (pid: pid_t, id: UInt32)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.25)
        guard let window: AXUIElement = value(element, kAXFocusedWindowAttribute) else { return nil }
        var id: CGWindowID = 0
        guard windowID(window, &id) == .success else { return nil }
        return (app.processIdentifier, id)
    }

    static func raise(_ window: Sky.Window) {
        var psn = ProcessSerialNumber()
        if process(window.pid, &psn) == noErr {
            Sky.focus(window.id, of: &psn)
        } else {
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(window.pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        }
        guard let element = windows(of: window.pid).first(where: { $0.id == window.id })?.element else { return }
        _ = press(element, kAXRaiseAction)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
}
