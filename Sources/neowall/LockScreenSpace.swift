import AppKit

/// The lock screen covers every ordinary window, whatever its level. The
/// window server keeps a space above it, the one Notification Center uses
/// while locked, and a window moved into a space at that level shows there.
///
/// This is private SkyLight API, so every symbol is looked up at run time; if
/// any is missing the lock screen simply stays as the system draws it.
enum LockScreenSpace {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static let addWindows = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindows.self)

    /// Created on first use and kept for the life of the process.
    private static let space: (connection: Int32, id: Int32)? = {
        guard let mainConnection = symbol("SLSMainConnectionID", as: MainConnection.self),
              let create = symbol("SLSSpaceCreate", as: SpaceCreate.self),
              let setLevel = symbol("SLSSpaceSetAbsoluteLevel", as: SpaceSetLevel.self),
              let show = symbol("SLSShowSpaces", as: ShowSpaces.self),
              addWindows != nil
        else {
            NSLog("neowall: the lock screen space is unavailable on this version of macOS")
            return nil
        }
        let level = handle.flatMap { dlsym($0, "kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock") }?
            .assumingMemoryBound(to: Int32.self).pointee ?? 400
        let connection = mainConnection()
        let id = create(connection, 1, 0)
        _ = setLevel(connection, id, level)
        _ = show(connection, [id] as CFArray)
        return (connection, id)
    }()

    /// Moves `window` above the lock screen. Returns false when that is not possible.
    @discardableResult
    static func add(_ window: NSWindow) -> Bool {
        guard let space, let addWindows else { return false }
        _ = addWindows(space.connection, space.id, [window.windowNumber] as CFArray, 7)
        return true
    }
}
