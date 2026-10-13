# neowall

An animated ASCII wallpaper for macOS in the style of [Omarchy](https://omarchy.org),
built to cost almost nothing while the desktop is visible, and no wakeups at
all while it is covered.

## Install

Download [neowall.dmg](https://github.com/jorgeMartinez293/neowall-releases/releases/latest/download/neowall.dmg),
open it and drag neowall to Applications. It runs on macOS 14 or later, on
Apple Silicon and Intel, and keeps itself up to date.

## Build


```bash
make run        # build, bundle and launch build/neowall.app
make install    # copy the app to /Applications
make test
```

Requires macOS 14 and the Swift toolchain (Xcode). The only dependency is
[Sparkle](https://sparkle-project.org), which SwiftPM fetches, for updates.

## Configure

Everything lives in `~/.config/neowall/config.toml`, created on first launch.
Saving the file applies it immediately; the menu bar icon edits the same file.

| Key | Default | Meaning |
| --- | --- | --- |
| `theme` | `tokyo-night` | Any stock Omarchy theme (all 22 are built in) or a user theme |
| `font` | `JetBrains Mono` | Falls back to the system monospaced font |
| `cell_size` | `18` | Text cell height in points |
| `steps` / `steps_battery` | `10` / `6` | Scene steps per second on AC power and on battery; the CPU cost |
| `fps` | `30` | Frame rate of the cross-fade between steps; `0` shows hard steps |
| `pause_on_low_power` | `true` | Freeze while Low Power Mode is on |
| `speed` | `1.0` | Animation speed multiplier |
| `brightness` / `vignette` | `1.0` / `0.3` | Ink strength and edge darkening |
| `logo` / `logo_size` | `apple` / `0.34` | `apple`, `none`, or any text; height as a fraction of the screen |
| `match_system_wallpaper` | `false` | Swap the system wallpaper for the theme background while running (see below) |
| `lock_screen` | `false` | Keep animating on the lock screen (see below) |
| `clock` | `off` | `off`, `logo`, `corner` or `text` (see below) |
| `clock_seconds` / `clock_24h` | `5` / `true` | How long a clicked clock stays; 24-hour or 12-hour time |
| `clock_font` | `mono` | `system`, `rounded`, `serif`, `mono`, `blocks`, or any installed font by name |
| `launch_at_login` | `false` | Start at login; run the app from `/Applications` |
| `auto_update` | `true` | Look for a new version once a day and offer to install it |
| `menu_bar` | `true` | Show the menu bar icon |

### Themes

Any Omarchy `colors.toml` works as a theme: save it as
`~/.config/neowall/themes/<name>.toml` and set `theme = "<name>"`. One optional
key tunes it for neowall:

```toml
neowall_inks = ["accent", "cyan", "magenta"]  # the three colours the scene paints with
```

### Menu bar

neowall is a window above the system wallpaper. Some system surfaces draw the
system wallpaper itself instead of what is on screen, most visibly an
auto-hidden menu bar as it slides in. `match_system_wallpaper = true` replaces
the system wallpaper with a flat image of the theme background while neowall
runs, per space as you visit it, and restores the original on quit.

### Clock

`clock` picks one of three ways to tell the time, also offered in the menu
bar icon's Clock menu:

- `logo` — a click on the centre logo dissolves it into the time, cell by
  cell in patches, and the time dissolves back the same way.
- `corner` — a click on the bare desktop near the top right corner draws the
  time there, the flow parting in a front that sweeps out from the corner.
- `text` — the time stays in the corner in small characters of the font.

`clock_font` sets the digits of both: a design of the system font, `blocks`
for digits built from whole cells, or the name of any installed font, such as
`Futura-Medium`.

A clicked clock leaves after `clock_seconds`, or on a second click. Nothing
runs between clicks. `corner` watches for clicks that land on the desktop.
`logo` instead keeps a transparent panel over the logo that takes the click
itself: a click that reaches the Finder makes it the active app, which brings
an auto-hidden menu bar down until another app is active. Desktop icons under
the logo cannot be clicked while `logo` is chosen.
A clock is blended into the scene's logo mask when it changes, so a step costs
the same with one as without. The minute is checked on the steps the scene
already takes; a frozen scene cannot keep time, so `text` hides while paused.

If Desktop & Dock's "Click wallpaper to reveal desktop" is set to Always, the
same click also moves the windows aside.

### Lock screen

macOS draws the lock screen's wallpaper and clock in one window, so nothing
can sit between them. `lock_screen = true` instead draws the scene's ink,
without its background, in a transparent window above the lock screen and
keeps it clear of the clock and the password field. The lock screen shows the
system wallpaper underneath, so `match_system_wallpaper` makes it the theme's.

The overlay exists only while the screen is locked and steps at the usual
rate until the display sleeps. It uses private SkyLight API; if a macOS update
removes it, the lock screen is simply left alone.

## How it stays cheap

- The scene simulates a small character grid on the CPU (roughly 10,000 cells).
  The grid is uploaded as a tiny texture and one full-screen triangle draws
  it; the fragment shader looks up each pixel's cell and its glyph in a font
  atlas.
- The scene steps only a few times a second. Each step is drawn into the hidden
  one of two stacked layers, and Core Animation cross-fades to it inside the
  window server. Motion between steps is smooth while neowall itself neither
  draws nor wakes.
- Steps come from a display link, which keeps them evenly spaced on the
  screen's own refresh.
- The display link pauses while the desktop is fully covered, the screen is
  locked (unless `lock_screen` is on) or asleep, or Low Power Mode is on.

## Layout

- `Sources/NeowallCore` — config, themes, the flow scene; no AppKit, unit tested.
- `Sources/neowall` — windows, Metal renderer, power and file watching, menu.
- `scripts/generate-icon.swift` — draws `Resources/AppIcon.icns`; run it with
  `install` to regenerate.
- `scripts/ship.sh` — builds, notarizes and publishes a release; see
  [docs/RELEASING.md](docs/RELEASING.md) and [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

## License

[MIT](LICENSE).
