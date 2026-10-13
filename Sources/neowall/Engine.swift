import AppKit
import NeowallCore
import ServiceManagement

/// Owns the wallpaper windows and decides how often they animate, if at all.
final class Engine {
    let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/neowall")
    var configURL: URL { directory.appendingPathComponent("config.toml") }
    var themesURL: URL { directory.appendingPathComponent("themes") }

    private(set) var config = Config()
    private(set) var theme = ThemeStore.load(ThemeStore.fallback, userDirectory: nil)
    private(set) var stepsPerSecond = 0.0
    var paused = false { didSet { updatePacing() } }

    private var wallpapers: [Wallpaper] = []
    /// One per screen, only while the screen is locked and `lock_screen` is on.
    private var lockWallpapers: [Wallpaper] = []
    private var screensAsleep = false
    private var locked = false
    private let power = PowerMonitor()
    private var watcher: FileWatcher?
    private var pendingReload: DispatchWorkItem?
    private let systemWallpaper = SystemWallpaper()
    private var clockMonitor: Any?
    private var clockHide: DispatchWorkItem?
    private lazy var menu = StatusMenu(engine: self)

    func start() {
        try? FileManager.default.createDirectory(at: themesURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try? Config.template.write(to: configURL, atomically: true, encoding: .utf8)
        }
        loadConfig()
        observe()
        rebuildWallpapers()
    }

    /// Rewrites one key of the config file; the file stays the source of truth.
    func set(_ key: String, to literal: String) {
        let text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? Config.template
        try? Config.replacing(key: key, with: literal, in: text).write(to: configURL, atomically: true, encoding: .utf8)
        reload()
    }

    // MARK: - Configuration

    @discardableResult
    private func loadConfig() -> Bool {
        let text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let newConfig = Config(toml: FlatTOML.parse(text))
        let newTheme = ThemeStore.load(newConfig.theme, userDirectory: themesURL)
        // Re-arm on every load: an atomic save leaves the old watch on a dead inode.
        watcher = FileWatcher(paths: [directory.path, configURL.path, themesURL.path]) { [weak self] in
            self?.scheduleReload()
        }
        guard newConfig != config || newTheme != theme else { return false }
        config = newConfig
        theme = newTheme
        return true
    }

    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func reload() {
        guard loadConfig() else { return }
        applyConfig()
    }

    private func applyConfig() {
        menu.isVisible = config.menuBar
        (wallpapers + lockWallpapers).forEach { $0.configure(config: config, theme: theme) }
        syncSystemWallpaper()
        syncLoginItem()
        Updater.shared.automaticChecks = config.autoUpdate
        syncClockTrigger()
        updatePacing()
    }

    func stop() {
        systemWallpaper.restore()
    }

    private func syncSystemWallpaper() {
        if config.matchSystemWallpaper {
            systemWallpaper.match(theme.background, in: directory)
        } else {
            systemWallpaper.restore()
        }
    }

    /// Registers or removes the app as a login item to match the config.
    private func syncLoginItem() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let service = SMAppService.mainApp
        guard config.launchAtLogin != (service.status == .enabled) else { return }
        do {
            if config.launchAtLogin { try service.register() } else { try service.unregister() }
        } catch {
            NSLog("neowall: could not update the login item: \(error.localizedDescription)")
        }
    }

    private func rebuildWallpapers() {
        wallpapers.forEach { $0.close() }
        wallpapers = NSScreen.screens.map { Wallpaper(screen: $0) }
        for wallpaper in wallpapers {
            wallpaper.onLogoClick = { [weak self, weak wallpaper] in
                if let wallpaper { self?.toggleClock(on: wallpaper) }
            }
        }
        rebuildLockWallpapers()
        applyConfig()
    }

    private func rebuildLockWallpapers() {
        // The desktops take the scene back from the overlays that are leaving.
        for (wallpaper, overlay) in zip(wallpapers, lockWallpapers) where wallpaper.screen == overlay.screen {
            wallpaper.resume(from: overlay)
        }
        lockWallpapers.forEach { $0.close() }
        lockWallpapers = locked && config.lockScreen ? wallpapers.map { Wallpaper(screen: $0.screen, overlaying: $0) } : []
        lockWallpapers.forEach { $0.configure(config: config, theme: theme) }
    }

    // MARK: - Clock

    /// Listens for clicks on the desktop only while the `corner` clock is
    /// chosen; the `logo` clock has a panel of its own to click.
    private func syncClockTrigger() {
        let wanted = config.clock == .corner
        if !wanted { clockHide?.cancel() }
        if wanted, clockMonitor == nil {
            // The wallpaper lets clicks through to the Finder, so they are
            // seen from outside. Nothing runs between clicks.
            clockMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                self?.clicked(at: NSEvent.mouseLocation)
            }
        } else if !wanted, let clockMonitor {
            NSEvent.removeMonitor(clockMonitor)
            self.clockMonitor = nil
        }
    }

    /// A click on the bare desktop near a screen's top right corner asks for
    /// its clock.
    private func clicked(at point: NSPoint) {
        guard let wallpaper = wallpapers.first(where: { $0.screen.frame.contains(point) }),
              wallpaper.clockIsAsked(at: point), Self.isDesktop(at: point)
        else { return }
        toggleClock(on: wallpaper)
    }

    /// Shows a screen's clock for a while, or sends it away if it is there.
    private func toggleClock(on wallpaper: Wallpaper) {
        clockHide?.cancel()
        let shown = !wallpaper.showsClock
        wallpapers.forEach { $0.showClock(shown && $0 === wallpaper) }
        guard shown else { return }
        let hide = DispatchWorkItem { [weak wallpaper] in wallpaper?.showClock(false) }
        clockHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + config.clockSeconds, execute: hide)
    }

    /// Whether the topmost window at `point` belongs to the desktop, whose
    /// windows all sit below the level of ordinary ones.
    private static func isDesktop(at point: NSPoint) -> Bool {
        let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        guard number > 0,
              let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(number)) as? [[CFString: Any]],
              let level = windows.first?[kCGWindowLayer] as? Int
        else { return false }
        return level < 0
    }

    // MARK: - Pacing

    private func observe() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rebuildWallpapers()
        }
        workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            // The system wallpaper is set per space.
            self?.syncSystemWallpaper()
        }
        center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updatePacing()
        }
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = true
            self?.updatePacing()
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false
            self?.updatePacing()
        }
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.locked = true
            self?.rebuildLockWallpapers()
            self?.updatePacing()
        }
        distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.locked = false
            self?.rebuildLockWallpapers()
            self?.updatePacing()
        }
        power.onChange = { [weak self] in self?.updatePacing() }
    }

    private var targetStepsPerSecond: Double {
        if paused || screensAsleep { return 0 }
        if power.lowPowerMode && config.pauseOnLowPower { return 0 }
        return power.onBattery ? config.stepsBattery : config.steps
    }

    /// Each wallpaper animates only while it would actually be seen; a
    /// covered desktop costs nothing.
    private func updatePacing() {
        let target = targetStepsPerSecond
        for wallpaper in wallpapers {
            wallpaper.stepsPerSecond = !locked && wallpaper.isVisible ? target : 0
        }
        for wallpaper in lockWallpapers {
            wallpaper.stepsPerSecond = wallpaper.isVisible ? target : 0
        }
        stepsPerSecond = (wallpapers + lockWallpapers).map(\.stepsPerSecond).max() ?? 0
    }
}
