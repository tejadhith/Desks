import AppKit

enum Keys {
    static func press(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    static func desktop(_ number: Int) -> Bool {
        guard let shortcut = shortcut(for: number) else { return false }
        press(shortcut.code, flags: shortcut.flags)
        return true
    }

    static func label(for number: Int) -> String? {
        guard shortcut(for: number) != nil, number <= 9 else { return nil }
        return "⌃\(number)"
    }

    private static func shortcut(for number: Int) -> (code: CGKeyCode, flags: CGEventFlags)? {
        guard (1...16).contains(number),
              let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let hotkeys = domain["AppleSymbolicHotKeys"] as? [String: Any],
              let entry = hotkeys[String(117 + number)] as? [String: Any],
              (entry["enabled"] as? NSNumber)?.boolValue == true,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [NSNumber],
              parameters.count == 3
        else { return nil }
        return (CGKeyCode(parameters[1].intValue), CGEventFlags(rawValue: parameters[2].uint64Value))
    }
}
