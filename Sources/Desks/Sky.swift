import AppKit

enum Sky {
    struct Space: Hashable, Sendable {
        let id: UInt64
        let uuid: String
        let number: Int?
        let index: Int
        let display: String
    }

    struct Window: Identifiable, Hashable, Sendable {
        let id: UInt32
        let pid: pid_t
        let app: String
        var title: String
        let space: UInt64
    }

    private typealias Main = @convention(c) () -> Int32
    private typealias Displays = @convention(c) (Int32) -> UnsafeRawPointer?
    private typealias Active = @convention(c) (Int32) -> UInt64
    private typealias Copy = @convention(c) (Int32, UInt32, CFArray, UInt32, UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>) -> UnsafeRawPointer?
    private typealias Query = @convention(c) (Int32, CFArray, Int32) -> UnsafeRawPointer?
    private typealias Result = @convention(c) (UnsafeRawPointer) -> UnsafeRawPointer?
    private typealias Advance = @convention(c) (UnsafeRawPointer) -> Bool
    private typealias Tags = @convention(c) (UnsafeRawPointer) -> UInt64
    private typealias Parent = @convention(c) (UnsafeRawPointer) -> UInt32
    private typealias Level = @convention(c) (UnsafeRawPointer) -> Int32
    private typealias Assign = @convention(c) (Int32, pid_t, UInt64) -> Int32
    private typealias Front = @convention(c) (UnsafeMutableRawPointer, UInt32, UInt32) -> Int32
    private typealias Record = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>) -> Int32

    private static let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static func load<T>(_ name: String, as type: T.Type) -> T {
        unsafeBitCast(dlsym(library, name), to: type)
    }

    private static let main = load("SLSMainConnectionID", as: Main.self)
    private static let displays = load("SLSCopyManagedDisplaySpaces", as: Displays.self)
    private static let active = load("SLSGetActiveSpace", as: Active.self)
    private static let copy = load("SLSCopyWindowsWithOptionsAndTags", as: Copy.self)
    private static let query = load("SLSWindowQueryWindows", as: Query.self)
    private static let result = load("SLSWindowQueryResultCopyWindows", as: Result.self)
    private static let advance = load("SLSWindowIteratorAdvance", as: Advance.self)
    private static let tags = load("SLSWindowIteratorGetTags", as: Tags.self)
    private static let attributes = load("SLSWindowIteratorGetAttributes", as: Tags.self)
    private static let parent = load("SLSWindowIteratorGetParentID", as: Parent.self)
    private static let identifier = load("SLSWindowIteratorGetWindowID", as: Parent.self)
    private static let level = load("SLSWindowIteratorGetLevel", as: Level.self)
    private static let process = load("SLSProcessAssignToSpace", as: Assign.self)
    private static let front = load("_SLPSSetFrontProcessWithOptions", as: Front.self)
    private static let record = load("SLPSPostEventRecordTo", as: Record.self)

    private static let connection = main()

    static func spaces() -> [Space] {
        guard let raw = displays(connection),
              let list = Unmanaged<CFArray>.fromOpaque(raw).takeRetainedValue() as? [[String: Any]]
        else { return [] }
        var number = 0
        var spaces: [Space] = []
        for display in list {
            let name = display["Display Identifier"] as? String ?? ""
            for (index, space) in (display["Spaces"] as? [[String: Any]] ?? []).enumerated() {
                guard let id = (space["ManagedSpaceID"] as? NSNumber)?.uint64Value else { continue }
                let desktop = (space["type"] as? NSNumber)?.intValue == 0
                if desktop { number += 1 }
                spaces.append(Space(
                    id: id,
                    uuid: space["uuid"] as? String ?? "",
                    number: desktop ? number : nil,
                    index: index,
                    display: name
                ))
            }
        }
        return spaces
    }

    static func current() -> UInt64 {
        active(connection)
    }

    static func focus(_ window: UInt32, of psn: inout ProcessSerialNumber) {
        withUnsafeMutablePointer(to: &psn) { pointer in
            let raw = UnsafeMutableRawPointer(pointer)
            _ = front(raw, window, 0x200)
            var bytes = [UInt8](repeating: 0, count: 0x100)
            bytes[0x04] = 0xF8
            bytes[0x3A] = 0x10
            var id = window
            memcpy(&bytes[0x3C], &id, MemoryLayout<UInt32>.size)
            var point = CGPoint(x: -1, y: -1)
            memcpy(&bytes[0x20], &point, MemoryLayout<CGPoint>.size)
            bytes[0x08] = 0x01
            _ = record(raw, &bytes)
            bytes[0x08] = 0x02
            _ = record(raw, &bytes)
        }
    }

    @discardableResult
    static func assign(_ pid: pid_t, to space: UInt64) -> Bool {
        process(connection, pid, space) == 0
    }

    static func visible() -> Set<UInt64> {
        guard let raw = displays(connection),
              let list = Unmanaged<CFArray>.fromOpaque(raw).takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return Set(list.compactMap { (($0["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value })
    }

    static func frame(of display: String) -> CGRect? {
        guard let top = NSScreen.screens.first?.frame.maxY, let frame = screen(display)?.frame else { return nil }
        return CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
    }

    static func area(of display: String) -> CGRect? {
        guard let top = NSScreen.screens.first?.frame.maxY, let frame = screen(display)?.visibleFrame else { return nil }
        return CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
    }

    static func name(of display: String) -> String? {
        screen(display)?.localizedName
    }

    private static func screen(_ display: String) -> NSScreen? {
        let screens = NSScreen.screens
        return display == "Main" ? screens.first : screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue()
            else { return false }
            return (CFUUIDCreateString(nil, uuid) as String) == display
        }
    }

    static func windows(in spaces: [UInt64]) -> [Window] {
        let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        var owners: [UInt32: (pid: pid_t, app: String, title: String)] = [:]
        for entry in info {
            guard let id = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t
            else { continue }
            owners[id] = (pid, entry[kCGWindowOwnerName as String] as? String ?? "", entry[kCGWindowName as String] as? String ?? "")
        }
        let me = getpid()
        return spaces.flatMap { space in
            ids(on: space).compactMap { id in
                guard let owner = owners[id], owner.pid != me else { return nil }
                return Window(id: id, pid: owner.pid, app: owner.app, title: owner.title, space: space)
            }
        }
    }

    private static func ids(on space: UInt64) -> [UInt32] {
        var set: UInt64 = 1
        var clear: UInt64 = 0
        guard let raw = copy(connection, 0, [NSNumber(value: space)] as CFArray, 0x2, &set, &clear) else { return [] }
        let list = Unmanaged<CFArray>.fromOpaque(raw).takeRetainedValue()
        let count = CFArrayGetCount(list)
        guard count > 0, let search = query(connection, list, Int32(count)) else { return [] }
        defer { Unmanaged<AnyObject>.fromOpaque(search).release() }
        guard let iterator = result(search) else { return [] }
        defer { Unmanaged<AnyObject>.fromOpaque(iterator).release() }
        var ids: [UInt32] = []
        while advance(iterator) {
            let tag = tags(iterator)
            let attribute = attributes(iterator)
            guard parent(iterator) == 0, [0, 3, 8].contains(level(iterator)) else { continue }
            let visible = attribute & 0x2 != 0 || tag & 0x400000000000000 != 0
            let normal = tag & 0x1 != 0 || (tag & 0x2 != 0 && tag & 0x80000000 != 0)
            if visible && normal { ids.append(identifier(iterator)) }
        }
        return ids
    }
}
