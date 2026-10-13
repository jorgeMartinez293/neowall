/// Per-cell fade (0-1) that clears breathing room around the logo: 1 on the
/// logo itself, falling to 0 at `radius` cell widths from its edge.
func logoHalo(mask: [Float], cols: Int, rows: Int, radius: Float, aspect: Float) -> [Float] {
    var halo = [Float](repeating: 0, count: mask.count)
    let reachX = Int(radius), reachY = Int(radius / aspect)
    for y in 0..<rows {
        for x in 0..<cols where mask[y * cols + x] > 0.5 {
            for ny in max(0, y - reachY)...min(rows - 1, y + reachY) {
                for nx in max(0, x - reachX)...min(cols - 1, x + reachX) {
                    let dx = Float(nx - x), dy = Float(ny - y) * aspect
                    let reach = 1 - (dx * dx + dy * dy).squareRoot() / radius
                    if reach > halo[ny * cols + nx] { halo[ny * cols + nx] = reach }
                }
            }
        }
    }
    return halo
}
