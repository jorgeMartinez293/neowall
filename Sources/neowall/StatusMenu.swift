import AppKit
import NeowallCore

/// The menu bar icon. Every choice is written to the config file, so the menu
/// and hand edits never disagree.
final class StatusMenu: NSObject, NSMenuDelegate {
    private unowned let engine: Engine
    private var item: NSStatusItem?

    init(engine: Engine) {
        self.engine = engine
    }

    var isVisible: Bool {
        get { item != nil }
        set {
            guard newValue != isVisible else { return }
            if newValue {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                item.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "neowall")
                item.menu = NSMenu()
                item.menu?.delegate = self
                self.item = item
            } else if let item {
                NSStatusBar.system.removeStatusItem(item)
                self.item = nil
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let rate = engine.stepsPerSecond > 0 ? "\(Int(engine.stepsPerSecond)) steps/s" : "frozen"
        menu.addItem(withTitle: "\(engine.theme.name) · \(rate)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        let themes = NSMenu()
        for name in ThemeStore.names(userDirectory: engine.themesURL) {
            add(name, to: themes, key: "theme", checked: name == engine.config.theme)
        }
        menu.addItem(submenu: themes, title: "Theme")

        let clocks = NSMenu()
        let titles: [ClockStyle: String] = [
            .off: "Off", .logo: "Logo Turns into the Time", .corner: "Drawn in the Corner", .text: "Small Text",
        ]
        for style in ClockStyle.allCases {
            add(style.rawValue, to: clocks, key: "clock", checked: style == engine.config.clock, title: titles[style])
        }
        clocks.addItem(.separator())
        let fonts = [
            ("system", "System"), ("rounded", "System Rounded"), ("serif", "System Serif"), ("mono", "System Mono"),
            ("blocks", "Blocks"),
            ("Futura-Medium", "Futura"), ("AvenirNext-Medium", "Avenir Next"), ("GillSans-Light", "Gill Sans Light"),
            ("HelveticaNeue-Thin", "Helvetica Neue Thin"), ("Didot-Bold", "Didot"), ("DINCondensed-Bold", "DIN Condensed"),
            ("JetBrainsMono-Bold", "JetBrains Mono"),
        ]
        for (name, title) in fonts {
            add(name, to: clocks, key: "clock_font", checked: name == engine.config.clockFont, title: title)
        }
        menu.addItem(submenu: clocks, title: "Clock")

        menu.addItem(.separator())
        menu.addItem(toggle("Match System Wallpaper", key: "match_system_wallpaper", on: engine.config.matchSystemWallpaper))
        menu.addItem(toggle("Show on Lock Screen", key: "lock_screen", on: engine.config.lockScreen))
        menu.addItem(toggle("Launch at Login", key: "launch_at_login", on: engine.config.launchAtLogin))
        menu.addItem(action(engine.paused ? "Resume" : "Pause", #selector(togglePause)))
        menu.addItem(action("Edit Config…", #selector(editConfig)))
        menu.addItem(.separator())
        if Updater.shared.isConfigured {
            menu.addItem(toggle("Update Automatically", key: "auto_update", on: engine.config.autoUpdate))
            menu.addItem(action("Check for Updates…", #selector(checkForUpdates)))
            menu.addItem(.separator())
        }
        menu.addItem(action("Quit neowall", #selector(quit)))
    }

    private func add(_ value: String, to menu: NSMenu, key: String, checked: Bool, title: String? = nil) {
        let item = action(title ?? value, #selector(choose(_:)))
        item.representedObject = [key, value]
        item.state = checked ? .on : .off
        menu.addItem(item)
    }

    private func toggle(_ title: String, key: String, on: Bool) -> NSMenuItem {
        let item = action(title, #selector(flip(_:)))
        item.representedObject = [key, on ? "false" : "true"]
        item.state = on ? .on : .off
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        engine.set(pair[0], to: "\"\(pair[1])\"")
    }

    @objc private func flip(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        engine.set(pair[0], to: pair[1])
    }

    @objc private func togglePause() {
        engine.paused.toggle()
    }

    @objc private func editConfig() {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-t", engine.configURL.path]
        try? open.run()
    }

    @objc private func checkForUpdates() {
        Updater.shared.checkForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
