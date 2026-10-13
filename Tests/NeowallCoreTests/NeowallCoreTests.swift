import XCTest
@testable import NeowallCore

final class TOMLTests: XCTestCase {
    func testParsesScalarsArraysAndComments() {
        let toml = FlatTOML.parse("""
        # heading
        [section]
        accent = "#7aa2f7"  # the hash inside quotes is not a comment
        fps = 12
        speed = 1.5
        menu_bar = false
        inks = ["accent", "cyan"]
        """)
        XCTAssertEqual(toml["accent"], .string("#7aa2f7"))
        XCTAssertEqual(toml["fps"], .number(12))
        XCTAssertEqual(toml["speed"], .number(1.5))
        XCTAssertEqual(toml["menu_bar"], .bool(false))
        XCTAssertEqual(toml["inks"]?.strings, ["accent", "cyan"])
        XCTAssertNil(toml["section"])
    }
}

final class ConfigTests: XCTestCase {
    func testTemplateMatchesDefaults() {
        XCTAssertEqual(Config(toml: FlatTOML.parse(Config.template)), Config())
    }

    func testClampsOutOfRangeNumbers() {
        let config = Config(toml: FlatTOML.parse("steps = 500\ncell_size = 1\nbrightness = -3"))
        XCTAssertEqual(config.steps, 30)
        XCTAssertEqual(config.cellSize, 6)
        XCTAssertEqual(config.brightness, 0)
    }

    func testReplacingKeepsCommentsAndOtherLines() {
        let text = "# top\ntheme = \"tokyo-night\"  # pick one\nfps = 12\n"
        let updated = Config.replacing(key: "theme", with: "\"hackerman\"", in: text)
        XCTAssertEqual(updated, "# top\ntheme = \"hackerman\"  # pick one\nfps = 12\n")
    }

    func testReplacingDoesNotMatchLongerKey() {
        let updated = Config.replacing(key: "fps", with: "30", in: "fps_battery = 5\n")
        XCTAssertEqual(updated, "fps_battery = 5\nfps = 30\n")
    }
}

final class ThemeTests: XCTestCase {
    func testBuiltinsResolveEveryInk() {
        for name in ThemeStore.names(userDirectory: nil) {
            let theme = ThemeStore.load(name, userDirectory: nil)
            XCTAssertEqual(theme.name, name)
            XCTAssertEqual(theme.inks.count, Ink.count)
        }
        XCTAssertEqual(ThemeStore.load("tokyo-night", userDirectory: nil).background, RGB(hex: "#1a1b26"))
    }

    func testUnknownThemeFallsBack() {
        XCTAssertEqual(ThemeStore.load("nope", userDirectory: nil).name, ThemeStore.fallback)
    }

    func testUserThemeShadowsBuiltin() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "background = \"#ff0000\"\n"
            .write(to: directory.appendingPathComponent("hackerman.toml"), atomically: true, encoding: .utf8)

        let theme = ThemeStore.load("hackerman", userDirectory: directory)
        XCTAssertEqual(theme.background, RGB(r: 1, g: 0, b: 0))
    }
}

final class FlowSceneTests: XCTestCase {
    private func run(seed: UInt64, mask: [Float] = []) -> CellGrid {
        var grid = CellGrid(cols: 40, rows: 20)
        let scene = FlowScene(cols: 40, rows: 20, seed: seed, mask: mask)
        for index in 1...30 {
            scene.step(time: Double(index) / 10, dt: 0.1, grid: &grid)
        }
        return grid
    }

    func testWritesValidCells() {
        let grid = run(seed: 7)
        var drawn = 0
        for cell in stride(from: 0, to: grid.bytes.count, by: 4) {
            XCTAssertLessThanOrEqual(grid.bytes[cell], CellGrid.glyph(126))
            XCTAssertLessThan(Int(grid.bytes[cell + 1]), Ink.count)
            if grid.bytes[cell] != CellGrid.blank, grid.bytes[cell + 2] > 0 { drawn += 1 }
        }
        XCTAssertGreaterThan(drawn, 0)
    }

    func testIsDeterministicPerSeed() {
        XCTAssertEqual(run(seed: 3).bytes, run(seed: 3).bytes)
        XCTAssertNotEqual(run(seed: 3).bytes, run(seed: 4).bytes)
    }

    func testClearingsLeaveCellsBlank() {
        let clearings = lockScreenClearings(cols: 40, rows: 20)
        XCTAssertEqual(clearings[3 * 40 + 20], 1)   // under the clock
        XCTAssertEqual(clearings[10 * 40 + 2], 0)   // mid-left edge
        var grid = CellGrid(cols: 40, rows: 20)
        let scene = FlowScene(cols: 40, rows: 20, seed: 3, clearings: clearings)
        scene.step(time: 1, dt: 0.1, grid: &grid)
        XCTAssertEqual(grid.bytes[(3 * 40 + 20) * 4], CellGrid.blank)
    }

    func testLogoMaskIsDrawnInForeground() {
        var mask = [Float](repeating: 0, count: 40 * 20)
        let logoCell = 10 * 40 + 20
        mask[logoCell] = 1
        let grid = run(seed: 3, mask: mask)
        XCTAssertEqual(grid.bytes[logoCell * 4 + 1], Ink.foreground)
        XCTAssertNotEqual(grid.bytes[logoCell * 4], CellGrid.blank)
    }
}

final class ClockTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testFormatsBothClocks() {
        let afternoon = Date(timeIntervalSince1970: 14 * 3600 + 5 * 60)
        XCTAssertEqual(clockText(afternoon, twentyFourHour: true, calendar: utc), "14:05")
        XCTAssertEqual(clockText(afternoon, twentyFourHour: false, calendar: utc), "2:05")
        let midnight = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(clockText(midnight, twentyFourHour: true, calendar: utc), "00:00")
        XCTAssertEqual(clockText(midnight, twentyFourHour: false, calendar: utc), "12:00")
    }

    func testConfigReadsClock() {
        XCTAssertEqual(Config(toml: FlatTOML.parse("clock = \"corner\"\nclock_seconds = 900")).clock, .corner)
        XCTAssertEqual(Config(toml: FlatTOML.parse("clock = \"corner\"\nclock_seconds = 900")).clockSeconds, 60)
        XCTAssertEqual(Config(toml: FlatTOML.parse("clock = \"sundial\"")).clock, .off)
    }

    func testTextClockWritesItsCharacters() {
        var grid = CellGrid(cols: 80, rows: 32)
        let scene = FlowScene(cols: 80, rows: 32, seed: 3)
        scene.clock = .text("14:05", cols: 80, rows: 32)
        scene.clockReveal = 1
        scene.step(time: 1, dt: 0.1, grid: &grid)
        let start = 2 * 80 + 80 - 5 - 2
        let written = (0..<5).map { grid.bytes[(start + $0) * 4] }
        XCTAssertEqual(written, "14:05".utf8.map(CellGrid.glyph))
        XCTAssertEqual(grid.bytes[(start - 1) * 4], CellGrid.blank)
    }

    func testHiddenClockLeavesTheSceneAlone() {
        var plain = CellGrid(cols: 40, rows: 20), clocked = CellGrid(cols: 40, rows: 20)
        let scene = FlowScene(cols: 40, rows: 20, seed: 3)
        scene.step(time: 1, dt: 0.1, grid: &plain)
        scene.clock = .text("14:05", cols: 40, rows: 20)
        scene.step(time: 1, dt: 0.1, grid: &clocked)
        XCTAssertEqual(plain.bytes, clocked.bytes)
    }

    func testLogoClockReplacesTheLogo() {
        var logo = [Float](repeating: 0, count: 40 * 20), digits = logo
        logo[10 * 40 + 10] = 1
        digits[10 * 40 + 30] = 1
        var grid = CellGrid(cols: 40, rows: 20)
        let scene = FlowScene(cols: 40, rows: 20, seed: 3, mask: logo)
        scene.clock = .logo(mask: digits, cols: 40, rows: 20)
        scene.clockReveal = 1
        scene.step(time: 1, dt: 0.1, grid: &grid)
        XCTAssertEqual(grid.bytes[(10 * 40 + 30) * 4 + 1], Ink.foreground)
        XCTAssertNotEqual(grid.bytes[(10 * 40 + 10) * 4 + 1], Ink.foreground)
    }

    func testLogoDissolvesCellByCellAndBack() {
        let cols = 60, rows = 30
        let logo = [Float](repeating: 1, count: cols * rows)
        let digits = [Float](repeating: 0, count: cols * rows)
        let scene = FlowScene(cols: cols, rows: rows, seed: 3, mask: logo)
        scene.clock = .logo(mask: digits, cols: cols, rows: rows, seed: 3)
        func logoCells(at reveal: Float) -> [UInt8] {
            var grid = CellGrid(cols: cols, rows: rows)
            scene.clockReveal = reveal
            scene.step(time: 1, dt: 0.1, grid: &grid)
            return stride(from: 1, to: grid.bytes.count, by: 4).map { grid.bytes[$0] == Ink.foreground ? 1 : 0 }
        }
        let start = logoCells(at: 0), middle = logoCells(at: 0.5), end = logoCells(at: 1)
        XCTAssertEqual(start.reduce(0) { $0 + Int($1) }, cols * rows)
        XCTAssertEqual(end.reduce(0) { $0 + Int($1) }, 0)
        // Half way, some cells have turned and others have not.
        let left = middle.reduce(0) { $0 + Int($1) }
        XCTAssertGreaterThan(left, cols * rows / 10)
        XCTAssertLessThan(left, cols * rows * 9 / 10)
        XCTAssertEqual(logoCells(at: 0.5), middle)
        XCTAssertEqual(logoCells(at: 0), start)
    }

    func testBlockClockIsBuiltFromWholeCells() {
        let mask = blockClock("10:42", cols: 80, rows: 20, heightFraction: 0.5, inCorner: false)
        XCTAssertTrue(mask.allSatisfy { $0 == 0 || $0 == 1 })
        let inked = (0..<20).filter { y in (0..<80).contains { mask[y * 80 + $0] == 1 } }
        XCTAssertEqual(inked, Array(5..<15))
        // "1" starts with an empty unit; the digits are centred as a whole.
        XCTAssertEqual((0..<80).first { x in (0..<20).contains { mask[$0 * 80 + x] == 1 } }, 6)
        XCTAssertEqual(blockClock("10:42", cols: 80, rows: 20, heightFraction: 0.5, inCorner: true).count, 1600)
    }

    func testCornerClockSweepsOutFromTheCorner() {
        var digits = [Float](repeating: 0, count: 40 * 20)
        let near = 2 * 40 + 37, far = 4 * 40 + 28
        digits[near] = 1
        digits[far] = 1
        var grid = CellGrid(cols: 40, rows: 20)
        let scene = FlowScene(cols: 40, rows: 20, seed: 3)
        scene.clock = .corner(mask: digits, cols: 40, rows: 20)
        scene.clockReveal = 0.3
        scene.step(time: 1, dt: 0.1, grid: &grid)
        XCTAssertEqual(grid.bytes[near * 4 + 1], Ink.foreground)
        XCTAssertNotEqual(grid.bytes[far * 4 + 1], Ink.foreground)
        scene.clockReveal = 1
        scene.step(time: 1, dt: 0.1, grid: &grid)
        XCTAssertEqual(grid.bytes[far * 4 + 1], Ink.foreground)
    }
}
