import Foundation

public struct RGB: Equatable {
    public var r: Float
    public var g: Float
    public var b: Float

    public init(r: Float, g: Float, b: Float) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        r = Float((value >> 16) & 0xFF) / 255
        g = Float((value >> 8) & 0xFF) / 255
        b = Float(value & 0xFF) / 255
    }

    public func mixed(with other: RGB, _ t: Float) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }
}

/// Indices into `Theme.inks`, stored per cell and resolved by the shader.
public enum Ink {
    public static let muted: UInt8 = 0
    public static let soft: UInt8 = 1
    public static let foreground: UInt8 = 2
    public static let a: UInt8 = 3
    public static let b: UInt8 = 4
    public static let c: UInt8 = 5
    public static let count = 6
}

/// A palette built from an Omarchy `colors.toml`. The optional `neowall_inks`
/// key names the three colours the scene paints with.
public struct Theme: Equatable {
    public var name: String
    public var background: RGB
    public var inks: [RGB]

    public init(name: String, toml: [String: TOMLValue]) {
        func color(_ key: String) -> RGB? { toml[key]?.string.flatMap(RGB.init(hex:)) }

        self.name = name
        let background = color("background") ?? RGB(r: 0.07, g: 0.07, b: 0.07)
        let foreground = color("foreground") ?? RGB(r: 0.75, g: 0.75, b: 0.75)
        let accentKeys = toml["neowall_inks"]?.strings ?? ["accent", "cyan", "magenta"]
        let accents = (0..<3).map { index in
            (index < accentKeys.count ? color(accentKeys[index]) : nil) ?? foreground
        }
        self.background = background
        inks = [
            color("muted") ?? background.mixed(with: foreground, 0.25),
            color("dark_foreground") ?? background.mixed(with: foreground, 0.5),
            foreground,
        ] + accents
    }
}

public enum ThemeStore {
    public static let fallback = "tokyo-night"

    /// Built-in theme names plus any `<name>.toml` found in `userDirectory`.
    public static func names(userDirectory: URL?) -> [String] {
        var names = Set(BuiltinThemes.sources.keys)
        if let userDirectory,
           let files = try? FileManager.default.contentsOfDirectory(at: userDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "toml" {
                names.insert(file.deletingPathExtension().lastPathComponent)
            }
        }
        return names.sorted()
    }

    /// User themes shadow built-ins; unknown names resolve to the fallback theme.
    public static func load(_ name: String, userDirectory: URL?) -> Theme {
        if let userDirectory, !name.contains("/"), !name.hasPrefix("."),
           let text = try? String(contentsOf: userDirectory.appendingPathComponent("\(name).toml"), encoding: .utf8) {
            return Theme(name: name, toml: FlatTOML.parse(text))
        }
        if let source = BuiltinThemes.sources[name] {
            return Theme(name: name, toml: FlatTOML.parse(source))
        }
        return Theme(name: fallback, toml: FlatTOML.parse(BuiltinThemes.sources[fallback] ?? ""))
    }
}
