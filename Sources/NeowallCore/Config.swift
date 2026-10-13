import Foundation

public struct Config: Equatable {
    public var theme = ThemeStore.fallback
    public var font = "JetBrains Mono"
    /// Height of a text cell, in points.
    public var cellSize = 18.0
    /// Scene steps per second on AC power and on battery.
    public var steps = 10.0
    public var stepsBattery = 6.0
    /// Frame rate of the cross-fade between steps; 0 shows hard steps.
    public var fps = 30.0
    public var pauseOnLowPower = true
    public var speed = 1.0
    public var brightness = 1.0
    public var vignette = 0.3
    public var menuBar = true
    /// `apple`, `none`, or any text to render as the centre logo.
    public var logo = "apple"
    /// Logo height as a fraction of the screen height.
    public var logoSize = 0.34
    /// Replace the system wallpaper with the theme's background colour while
    /// running, so system surfaces that show it (the revealed menu bar) match.
    public var matchSystemWallpaper = false
    /// Draw the scene's ink over the lock screen as well.
    public var lockScreen = false
    public var launchAtLogin = false
    /// Look for a new version once a day.
    public var autoUpdate = true
    public var clock = ClockStyle.off
    /// How long the `logo` and `corner` clocks stay after a click.
    public var clockSeconds = 5.0
    public var clock24h = true
    /// `system`, `rounded`, `serif`, `mono`, `blocks`, or the name of any installed font.
    public var clockFont = "mono"

    public init() {}

    public init(toml: [String: TOMLValue]) {
        func number(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            min(max(toml[key]?.number ?? fallback, range.lowerBound), range.upperBound)
        }
        let defaults = Config()
        theme = toml["theme"]?.string ?? defaults.theme
        font = toml["font"]?.string ?? defaults.font
        cellSize = number("cell_size", defaults.cellSize, 6...64)
        steps = number("steps", defaults.steps, 1...30)
        stepsBattery = number("steps_battery", defaults.stepsBattery, 0...30)
        fps = number("fps", defaults.fps, 0...120)
        pauseOnLowPower = toml["pause_on_low_power"]?.bool ?? defaults.pauseOnLowPower
        speed = number("speed", defaults.speed, 0...10)
        brightness = number("brightness", defaults.brightness, 0...1)
        vignette = number("vignette", defaults.vignette, 0...1)
        menuBar = toml["menu_bar"]?.bool ?? defaults.menuBar
        logo = toml["logo"]?.string ?? defaults.logo
        logoSize = number("logo_size", defaults.logoSize, 0.05...0.9)
        matchSystemWallpaper = toml["match_system_wallpaper"]?.bool ?? defaults.matchSystemWallpaper
        lockScreen = toml["lock_screen"]?.bool ?? defaults.lockScreen
        launchAtLogin = toml["launch_at_login"]?.bool ?? defaults.launchAtLogin
        autoUpdate = toml["auto_update"]?.bool ?? defaults.autoUpdate
        clock = toml["clock"]?.string.flatMap(ClockStyle.init(rawValue:)) ?? defaults.clock
        clockSeconds = number("clock_seconds", defaults.clockSeconds, 1...60)
        clock24h = toml["clock_24h"]?.bool ?? defaults.clock24h
        clockFont = toml["clock_font"]?.string ?? defaults.clockFont
    }

    /// Sets a top-level key in config text, keeping every other line and any
    /// trailing comment intact. Appends the key when it is missing.
    public static func replacing(key: String, with literal: String, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        for index in lines.indices {
            let code = FlatTOML.stripComment(lines[index])
            let trimmed = code.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key),
                  trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces).hasPrefix("=")
            else { continue }
            let comment = lines[index].dropFirst(code.count)
            lines[index] = "\(key) = \(literal)" + (comment.isEmpty ? "" : "  \(comment)")
            return lines.joined(separator: "\n")
        }
        if lines.last == "" { lines.removeLast() }
        lines.append("\(key) = \(literal)")
        return lines.joined(separator: "\n") + "\n"
    }

    public static let template = """
    # neowall configuration. Saved changes apply immediately.

    # Every stock Omarchy theme is built in (see the menu bar icon for the
    # list). Any Omarchy colors.toml dropped into themes/<name>.toml works too.
    theme = "tokyo-night"

    # Falls back to the system monospaced font when not installed.
    font = "JetBrains Mono"

    # Height of a text cell in points. Larger cells are chunkier and cheaper.
    cell_size = 18

    # Scene steps per second on AC power and on battery (0 freezes the frame).
    # This is what costs CPU.
    steps = 10
    steps_battery = 6

    # Frame rate of the cross-fade between steps. The window server runs the
    # fade, so it is smooth at no cost to neowall itself. 0 shows hard steps.
    fps = 30

    # Freeze the frame while macOS Low Power Mode is on.
    pause_on_low_power = true

    # Animation speed multiplier.
    speed = 1.0

    # Ink strength (0-1) and how much the edges darken (0-1).
    brightness = 1.0
    vignette = 0.3

    # Centre logo: "apple", "none", or any text. Size is a fraction of the
    # screen height.
    logo = "apple"
    logo_size = 0.34

    # macOS draws its own wallpaper behind the menu bar when an auto-hidden
    # bar slides in. Turn this on to swap the system wallpaper for the theme's
    # background colour while neowall runs; the original returns on quit.
    match_system_wallpaper = false

    # Keep animating on the lock screen. The ink is drawn over the system's
    # lock screen, clear of the clock and the password field, and costs the
    # same as the desktop until the display sleeps. Relies on private macOS
    # API; pairs well with match_system_wallpaper.
    lock_screen = false

    # Tell the time: "off", "logo", "corner" or "text". With "logo", a click
    # on the centre logo dissolves it into the time; with "corner", a click
    # near the top right corner of the desktop draws it there. Both stay for
    # clock_seconds, or until a second click. "text" keeps the time in small
    # characters in the corner instead. None of them adds work to a step.
    # "logo" takes the clicks on the logo for itself, so desktop icons under
    # it cannot be clicked.
    clock = "off"
    clock_seconds = 5
    clock_24h = true

    # Digits of the "logo" and "corner" clocks: "system", "rounded", "serif",
    # "mono", "blocks" (built from whole cells), or any installed font by
    # name, such as "Futura-Medium".
    clock_font = "mono"

    # Start neowall when you log in. Run it from /Applications for this.
    launch_at_login = false

    # Look for a new version once a day and offer to install it.
    auto_update = true

    # Show the menu bar icon.
    menu_bar = true

    """
}
