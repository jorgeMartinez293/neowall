import AppKit
import NeowallCore

/// macOS paints its own wallpaper, not the windows above it, behind some
/// system surfaces such as an auto-hidden menu bar sliding in. This swaps the
/// system wallpaper for a flat image of the theme background while neowall
/// runs, and puts the original back afterwards.
final class SystemWallpaper {
    /// Original wallpaper per display, kept on disk so that it survives a crash.
    private var stateURL: URL?

    func match(_ color: RGB, in directory: URL) {
        let stateURL = directory.appendingPathComponent("original-wallpaper.plist")
        self.stateURL = stateURL
        // macOS caches wallpapers by path, so each colour gets its own file.
        let hex = [color.r, color.g, color.b].map { String(format: "%02x", Int(($0 * 255).rounded())) }.joined()
        let image = directory.appendingPathComponent("backdrop-\(hex).png")
        if !FileManager.default.fileExists(atPath: image.path) {
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 3,
                hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )
            let fill = NSColor(deviceRed: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: 1)
            for y in 0..<16 { for x in 0..<16 { bitmap?.setColor(fill, atX: x, y: y) } }
            try? bitmap?.representation(using: .png, properties: [:])?.write(to: image)
        }

        var originals = (NSDictionary(contentsOf: stateURL) as? [String: String]) ?? [:]
        for screen in NSScreen.screens {
            guard let current = NSWorkspace.shared.desktopImageURL(for: screen), current != image else { continue }
            let key = Self.key(for: screen)
            // Never record one of our own backdrops as the original.
            if originals[key] == nil, current.deletingLastPathComponent().path != directory.path {
                originals[key] = current.path
            }
            try? NSWorkspace.shared.setDesktopImageURL(image, for: screen, options: [:])
        }
        (originals as NSDictionary).write(to: stateURL, atomically: true)
    }

    func restore() {
        guard let stateURL, let originals = NSDictionary(contentsOf: stateURL) as? [String: String] else { return }
        for screen in NSScreen.screens {
            guard let path = originals[Self.key(for: screen)] else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
        }
        try? FileManager.default.removeItem(at: stateURL)
        self.stateURL = nil
    }

    private static func key(for screen: NSScreen) -> String {
        "\(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? 0)"
    }
}
