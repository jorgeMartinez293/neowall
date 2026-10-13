import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = Engine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }
}

// A second copy would stack another set of windows on the desktop.
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
