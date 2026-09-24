import AppKit
import ObjectiveC

enum Bridge {
    private typealias Perform = @convention(c) (AnyObject, Selector) -> Void

    static func move(_ windows: [UInt32], to space: UInt64) -> Bool {
        typealias Initializer = @convention(c) (AnyObject, Selector, NSArray, UInt64) -> AnyObject
        return run("SLSBridgedMoveWindowsToManagedSpaceOperation", "initWithWindows:spaceID:") { instance, selector, implementation in
            unsafeBitCast(implementation, to: Initializer.self)(instance, selector, windows.map { NSNumber(value: $0) } as NSArray, space)
        }
    }

    private static func run(_ name: String, _ initializer: String, _ build: (AnyObject, Selector, IMP) -> AnyObject) -> Bool {
        let selector = NSSelectorFromString(initializer)
        let perform = NSSelectorFromString("performWithWMBridgeDelegate")
        guard let type = NSClassFromString(name),
              let method = class_getInstanceMethod(type, selector),
              let instance = class_createInstance(type, 0) as AnyObject?
        else { return false }
        let operation = build(instance, selector, method_getImplementation(method))
        guard let action = class_getInstanceMethod(Swift.type(of: operation), perform) else { return false }
        unsafeBitCast(method_getImplementation(action), to: Perform.self)(operation, perform)
        return true
    }
}
