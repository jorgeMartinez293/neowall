import Foundation

/// How the scene tells the time: by turning the logo into it or drawing it in
/// the top right corner when asked, or as small text that is always there.
public enum ClockStyle: String, CaseIterable {
    case off, logo, corner, text
}

/// The time as the clock shows it: "14:05", or "2:05" on a 12-hour clock.
public func clockText(_ date: Date, twentyFourHour: Bool, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    let hour = parts.hour ?? 0, minute = parts.minute ?? 0
    return twentyFourHour
        ? String(format: "%02d:%02d", hour, minute)
        : String(format: "%d:%02d", (hour + 11) % 12 + 1, minute)
}

/// A clock for the scene to draw over its flow.
public struct ClockLayer {
    /// Coverage (0-1) per cell of digits drawn in ink like the logo; empty for none.
    var mask: [Float] = []
    /// Literal characters, each a cell index and a glyph.
    var text: [(cell: Int, glyph: UInt8)] = []
    /// Per-cell fade (0-1) that clears the flow from around the clock.
    var halo: [Float]
    /// When each cell appears, as a fraction of the reveal; empty for all at once.
    var delay: [Float] = []
    /// How long a cell takes to appear, as a fraction of the reveal.
    var softness: Float = 0.35
    /// Whether the logo dissolves to make room for the digits.
    var replacesLogo = false

    /// Digits that the logo dissolves into, grain by grain: each cell turns
    /// at a moment set by a noise field, so the change spreads in patches, and
    /// plays back the same way in reverse. `mask` holds one coverage value per cell.
    public static func logo(mask: [Float], cols: Int, rows: Int, seed: UInt64 = 0) -> ClockLayer {
        let seed = UInt32(truncatingIfNeeded: seed)
        var delay = [Float](repeating: 0, count: mask.count)
        var low = Float.infinity, high = -Float.infinity
        for y in 0..<rows {
            for x in 0..<cols {
                let px = Float(x), py = Float(y) * FlowScene.aspect
                let value = 0.7 * valueNoise(px / 6, py / 6, seed: seed &+ 21)
                    + 0.3 * valueNoise(px / 1.5, py / 1.5, seed: seed &+ 22)
                delay[y * cols + x] = value
                // Only the middle of the screen matters to the range.
                if abs(x - cols / 2) < cols / 4, abs(y - rows / 2) < rows / 4 {
                    low = min(low, value)
                    high = max(high, value)
                }
            }
        }
        let range = max(high - low, 0.001)
        for index in delay.indices { delay[index] = max(0, min(1, (delay[index] - low) / range)) }
        return ClockLayer(
            mask: mask,
            halo: logoHalo(mask: mask, cols: cols, rows: rows, radius: 9, aspect: FlowScene.aspect),
            delay: delay, softness: 0.45, replacesLogo: true
        )
    }

    /// Digits in the top right corner, drawn by a front that sweeps out from it.
    public static func corner(mask: [Float], cols: Int, rows: Int) -> ClockLayer {
        let halo = logoHalo(mask: mask, cols: cols, rows: rows, radius: 6, aspect: FlowScene.aspect)
        var delay = [Float](repeating: 0, count: halo.count)
        var farthest: Float = 1
        for y in 0..<rows {
            for x in 0..<cols where halo[y * cols + x] > 0 {
                let dx = Float(cols - 1 - x), dy = Float(y) * FlowScene.aspect
                delay[y * cols + x] = (dx * dx + dy * dy).squareRoot()
                farthest = max(farthest, delay[y * cols + x])
            }
        }
        for index in delay.indices { delay[index] /= farthest }
        return ClockLayer(mask: mask, halo: halo, delay: delay)
    }

    /// `string` in the font's own glyphs, near the top right corner and clear
    /// of the menu bar.
    public static func text(_ string: String, cols: Int, rows: Int) -> ClockLayer {
        let glyphs = string.utf8.map(CellGrid.glyph)
        let row = min(rows - 1, max(0, rows / 16))
        let start = cols - glyphs.count - max(2, cols / 40)
        var mask = [Float](repeating: 0, count: cols * rows)
        var text: [(cell: Int, glyph: UInt8)] = []
        for (offset, glyph) in glyphs.enumerated() where start + offset >= 0 && start + offset < cols && rows > 0 {
            let cell = row * cols + start + offset
            mask[cell] = 1
            text.append((cell, glyph))
        }
        return ClockLayer(
            text: text,
            halo: logoHalo(mask: mask, cols: cols, rows: rows, radius: 4, aspect: FlowScene.aspect)
        )
    }
}

/// The time in digits built from whole cells, three units wide and five tall,
/// as a coverage mask: centred, or set into the top right corner.
/// `heightFraction` is the digits' height as a fraction of the grid's.
public func blockClock(_ time: String, cols: Int, rows: Int, heightFraction: Double, inCorner: Bool) -> [Float] {
    let shapes: [Character: [String]] = [
        "0": ["###", "# #", "# #", "# #", "###"], "1": [" # ", "## ", " # ", " # ", "###"],
        "2": ["###", "  #", "###", "#  ", "###"], "3": ["###", "  #", "###", "  #", "###"],
        "4": ["# #", "# #", "###", "  #", "  #"], "5": ["###", "#  ", "###", "  #", "###"],
        "6": ["###", "#  ", "###", "# #", "###"], "7": ["###", "  #", "  #", "  #", "  #"],
        "8": ["###", "# #", "###", "# #", "###"], "9": ["###", "# #", "###", "  #", "###"],
        ":": [" ", "#", " ", "#", " "],
    ]
    var mask = [Float](repeating: 0, count: cols * rows)
    let glyphs = time.compactMap { shapes[$0] }
    guard !glyphs.isEmpty else { return mask }
    // A unit is as many columns wide as makes it square on screen.
    let unitY = max(1, Int((heightFraction * Double(rows) / 5).rounded()))
    let unitX = unitY * Int(FlowScene.aspect)
    let width = (glyphs.reduce(0) { $0 + $1[0].count } + glyphs.count - 1) * unitX
    let inset = Int(Double(rows) * 0.07)
    var left = inCorner ? cols - inset * Int(FlowScene.aspect) - width : (cols - width) / 2
    let top = inCorner ? inset : (rows - 5 * unitY) / 2
    for glyph in glyphs {
        for (unitRow, line) in glyph.enumerated() {
            for (unitColumn, mark) in line.enumerated() where mark == "#" {
                for y in top + unitRow * unitY..<top + (unitRow + 1) * unitY where y >= 0 && y < rows {
                    for x in left + unitColumn * unitX..<left + (unitColumn + 1) * unitX where x >= 0 && x < cols {
                        mask[y * cols + x] = 1
                    }
                }
            }
        }
        left += (glyph[0].count + 1) * unitX
    }
    return mask
}
