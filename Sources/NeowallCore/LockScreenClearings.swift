/// Per-cell fade (0-1) that keeps the scene off the lock screen's clock and
/// password field, which sit below the overlay: 1 over each, falling to 0 a
/// little way outside.
public func lockScreenClearings(cols: Int, rows: Int) -> [Float] {
    // Centre and radii of each ellipse as fractions of the screen, from the top left.
    let zones: [(x: Float, y: Float, radiusX: Float, radiusY: Float)] = [
        (0.5, 0.16, 0.24, 0.15),  // date and clock
        (0.5, 0.88, 0.15, 0.13),  // avatar and password field
    ]
    var clearings = [Float](repeating: 0, count: cols * rows)
    for y in 0..<rows {
        for x in 0..<cols {
            let u = (Float(x) + 0.5) / Float(cols), v = (Float(y) + 0.5) / Float(rows)
            for zone in zones {
                let dx = (u - zone.x) / zone.radiusX, dy = (v - zone.y) / zone.radiusY
                let reach = max(0, min(1, (1.4 - (dx * dx + dy * dy).squareRoot()) / 0.4))
                if reach > clearings[y * cols + x] { clearings[y * cols + x] = reach }
            }
        }
    }
    return clearings
}
