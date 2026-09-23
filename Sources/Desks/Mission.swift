import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum Mission {
    private static let app = URL(fileURLWithPath: "/System/Applications/Mission Control.app")

    private static var root: AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        return Access.children(element).first { Access.identifier($0) == "mc" }
    }

    static var isOpen: Bool { root != nil }

    static func open() {
        guard !isOpen else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func close() async {
        for _ in 0..<10 where isOpen {
            Keys.press(CGKeyCode(kVK_Escape))
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    static func add(on display: String) async -> Bool {
        open()
        guard let screen = await screen(display), let button = search(screen, "mc.spaces.add", depth: 0) else {
            await close()
            return false
        }
        return Access.press(button)
    }

    static func remove(at index: Int, on display: String) async -> Bool {
        open()
        guard let button = await space(at: index, on: display) else {
            await close()
            return false
        }
        let done = Access.press(button, "AXRemoveDesktop")
        try? await Task.sleep(for: .milliseconds(300))
        await close()
        return done
    }

    static func go(to index: Int, on display: String) async -> Bool {
        open()
        guard let button = await space(at: index, on: display) else {
            await close()
            return false
        }
        return Access.press(button)
    }

    private static func space(at index: Int, on display: String) async -> AXUIElement? {
        guard let screen = await screen(display) else { return nil }
        for _ in 0..<40 {
            if let list = search(screen, "mc.spaces.list", depth: 0) {
                let buttons = Access.children(list)
                if buttons.indices.contains(index) { return buttons[index] }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private static func screen(_ display: String) async -> AXUIElement? {
        let frame = Sky.frame(of: display)
        for _ in 0..<40 {
            if let root {
                let screens = Access.children(root).filter { Access.identifier($0) == "mc.display" }
                let match = screens.first { screen in
                    guard let frame, let box = Access.frame(screen) else { return false }
                    return abs(box.minX - frame.minX) < 2 && abs(box.minY - frame.minY) < 2
                }
                if let match { return match }
                if screens.count == 1 { return screens[0] }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private static func search(_ element: AXUIElement, _ identifier: String, depth: Int) -> AXUIElement? {
        if Access.identifier(element) == identifier { return element }
        guard depth < 6 else { return nil }
        for child in Access.children(element) {
            if let found = search(child, identifier, depth: depth + 1) { return found }
        }
        return nil
    }
}
