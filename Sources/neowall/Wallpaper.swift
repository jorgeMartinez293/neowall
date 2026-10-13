import AppKit
import NeowallCore
import QuartzCore

/// A borderless, click-through window pinned to the desktop layer of one
/// screen, below the Finder icons; or, as an overlay, a transparent one above
/// the lock screen that carries on the scene of the desktop it covers.
final class Wallpaper: NSObject {
    /// Seconds a clock takes to appear or leave.
    private var clockTransition: Double { clock == .logo ? 1.6 : 0.9 }

    let screen: NSScreen
    private let window: NSWindow
    private let renderer: Renderer
    private let overlay: Bool
    private var link: CADisplayLink?
    private var speed = 1.0
    private var fadeRate: Float = 0
    private(set) var time = 0.0
    private var lastStep = 0.0
    private var clock = ClockStyle.off
    private var clock24h = true
    /// The minute the scene's clock reads, counted from the epoch.
    private var clockMinute = 0
    private var clockTarget: Float = 0
    private var clockReveal: Float = 0
    /// Takes the clicks on the logo while the `logo` clock is chosen.
    private var clickCatcher: NSPanel?
    /// Called when the logo is clicked.
    var onLogoClick: (() -> Void)?

    init(screen: NSScreen, overlaying desktop: Wallpaper? = nil) {
        self.screen = screen
        overlay = desktop != nil
        renderer = desktop.map { Renderer(overlay: true, seed: $0.renderer.seed) } ?? Renderer()
        time = desktop?.time ?? 0
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        // An overlay is ordered by its space, not by its level.
        if !overlay { window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow))) }
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = !overlay
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.layer = renderer.layer
        view.wantsLayer = true
        window.contentView = view
        window.setFrame(screen.frame, display: false)
        window.orderFront(nil)
        if overlay { LockScreenSpace.add(window) }
        super.init()

        // A display link fires on the screen's own refresh, so steps land
        // evenly spaced instead of beating against it like a timer would.
        link = view.displayLink(target: self, selector: #selector(step(_:)))
        link?.isPaused = true
        link?.add(to: .main, forMode: .common)
    }

    /// False while other windows or a full-screen space cover the desktop.
    var isVisible: Bool {
        window.occlusionState.contains(.visible)
    }

    /// Scene steps per second; 0 freezes the current frame and stops all work.
    var stepsPerSecond = 0.0 {
        didSet {
            guard stepsPerSecond != oldValue, let link else { return }
            link.isPaused = stepsPerSecond <= 0
            if clock == .text {
                // A frozen frame cannot keep time, so it shows none.
                clockReveal = stepsPerSecond > 0 ? 1 : 0
                clockTarget = clockReveal
                if stepsPerSecond <= 0, isVisible { redraw() }
            }
            guard stepsPerSecond > 0 else { return }
            let rate = Float(stepsPerSecond)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
            lastStep = 0
        }
    }

    func configure(config: Config, theme: Theme) {
        let scale = screen.backingScaleFactor
        let size = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
        if !overlay {
            window.backgroundColor = NSColor(
                srgbRed: CGFloat(theme.background.r), green: CGFloat(theme.background.g),
                blue: CGFloat(theme.background.b), alpha: 1
            )
        }
        speed = config.speed
        fadeRate = Float(config.fps)
        renderer.layer.frame = NSRect(origin: .zero, size: screen.frame.size)
        renderer.configure(pixelSize: size, scale: scale, config: config, theme: theme)
        // The lock screen has a clock of its own.
        let style = overlay ? .off : config.clock
        if style != clock {
            clock = style
            clockTarget = style == .text && stepsPerSecond > 0 ? 1 : 0
            clockReveal = clockTarget
        }
        clock24h = config.clock24h
        clockMinute = 0
        redraw()
        placeClickCatcher()
    }

    /// Keeps a transparent panel over the logo, just above the desktop's
    /// icons, while it is what a click asks the time of. A click that reached
    /// the Finder would make it the active app, and that brings an
    /// auto-hidden menu bar down for as long as the Finder stays active. The
    /// panel takes the click without activating anything.
    private func placeClickCatcher() {
        guard clock == .logo else {
            clickCatcher?.close()
            clickCatcher = nil
            return
        }
        let panel = clickCatcher ?? {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            // Set explicitly, a transparent window still receives clicks.
            panel.ignoresMouseEvents = false
            let view = ClickView()
            view.onClick = { [weak self] in self?.onLogoClick?() }
            panel.contentView = view
            clickCatcher = panel
            return panel
        }()
        let zone = renderer.logoZone, frame = screen.frame
        panel.setFrame(NSRect(
            x: frame.minX + zone.minX * frame.width, y: frame.maxY - zone.maxY * frame.height,
            width: zone.width * frame.width, height: zone.height * frame.height
        ), display: false)
        panel.orderFront(nil)
    }

    /// Whether a click here asked for the clock and it has not left yet.
    var showsClock: Bool {
        clock != .text && clockTarget > 0
    }

    /// Whether a click at `point`, in screen coordinates, asks for the
    /// `corner` clock: it does near the top right corner.
    func clockIsAsked(at point: NSPoint) -> Bool {
        let frame = screen.frame
        return clock == .corner && point.x > frame.maxX - frame.width * 0.2 && point.y > frame.maxY - frame.height * 0.2
    }

    /// Brings in or sends away the `logo` or `corner` clock.
    func showClock(_ shown: Bool) {
        guard clock == .logo || clock == .corner else { return }
        clockTarget = shown ? 1 : 0
        // A frozen wallpaper has no steps to animate with.
        guard stepsPerSecond <= 0 else { return }
        clockReveal = clockTarget
        if isVisible { redraw() }
    }

    /// Rebuilds the clock once the minute it reads has passed.
    private func updateClock() {
        if clockTarget > 0 || clockReveal > 0 {
            let now = Date()
            let minute = Int(now.timeIntervalSince1970 / 60)
            if minute != clockMinute {
                clockMinute = minute
                renderer.setClock(clock, time: clockText(now, twentyFourHour: clock24h))
                // The time is wider than the logo it replaces.
                placeClickCatcher()
            }
        }
        renderer.clockReveal = clockReveal
    }

    private func redraw() {
        updateClock()
        renderer.step(time: time, dt: 0, fade: 0, frameRate: 0)
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let interval = 1 / stepsPerSecond
        // The first step after a pause has no previous one to measure from.
        let elapsed = lastStep > 0 ? min(now - lastStep, 0.25) : interval
        // Some displays cannot refresh as slowly as asked; skip the extra callbacks.
        guard elapsed > interval * 0.75 else { return }
        lastStep = now
        time += elapsed * speed
        if clockReveal != clockTarget {
            let change = Float(elapsed / clockTransition)
            clockReveal = clockTarget > clockReveal
                ? min(clockTarget, clockReveal + change) : max(clockTarget, clockReveal - change)
        }
        updateClock()
        renderer.step(time: time, dt: elapsed * speed, fade: interval, frameRate: fadeRate)
    }

    /// Picks the scene up where an overlay left it.
    func resume(from overlay: Wallpaper) {
        time = overlay.time
    }

    func close() {
        clickCatcher?.close()
        link?.invalidate()
        window.close()
    }
}

/// Reports left clicks, including the first one in an inactive app.
private final class ClickView: NSView {
    var onClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
