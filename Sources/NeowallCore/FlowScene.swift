/// Domain-warped noise rendered through an ASCII density ramp.
public final class FlowScene {
    /// Cell height divided by cell width, as the noise coordinates assume.
    static let aspect: Float = 2

    private static let ramp = Array(" .:-=+*#%@".utf8).map(CellGrid.glyph)
    /// Noise units per cell width.
    private static let scale: Float = 1.0 / 16.0
    /// The warp and hue fields vary slowly, so they are evaluated on a coarse
    /// lattice and interpolated per cell.
    private static let coarseX = 4
    private static let coarseY = 2

    private let cols: Int
    private let rows: Int
    private let coarseCols: Int
    private let coarseRows: Int
    private let seed: UInt32
    private let logoMask: [Float]
    private let logoFade: [Float]
    /// The logo's mask and halo with the clock's blended in.
    private var mask: [Float]
    private var halo: [Float]
    private var warpX: [Float]
    private var warpY: [Float]
    private var hue: [Float]

    /// `mask` holds one coverage value (0-1) per cell for the centre logo, and
    /// `clearings` one fade (0-1) per cell for areas the scene should leave empty.
    public init(cols: Int, rows: Int, seed: UInt64, mask: [Float] = [], clearings: [Float] = []) {
        let mask = mask.count == cols * rows ? mask : [Float](repeating: 0, count: cols * rows)
        self.cols = cols
        self.rows = rows
        self.seed = UInt32(truncatingIfNeeded: seed)
        logoMask = mask
        self.mask = mask
        var halo = logoHalo(mask: mask, cols: cols, rows: rows, radius: 9, aspect: Self.aspect)
        if clearings.count == halo.count {
            for index in halo.indices { halo[index] = max(halo[index], clearings[index]) }
        }
        logoFade = halo
        self.halo = halo
        coarseCols = cols / Self.coarseX + 2
        coarseRows = rows / Self.coarseY + 2
        let count = coarseCols * coarseRows
        warpX = [Float](repeating: 0, count: count)
        warpY = [Float](repeating: 0, count: count)
        hue = [Float](repeating: 0, count: count)
    }

    /// The clock to draw, if any. It costs nothing until it is revealed.
    public var clock: ClockLayer? {
        didSet { compose() }
    }

    /// How far the clock has appeared, 0-1.
    public var clockReveal: Float = 0 {
        didSet { if clockReveal != oldValue { compose() } }
    }

    /// Blends the clock into the mask and halo that `step` reads, so a step
    /// costs the same with a clock as without one.
    private func compose() {
        guard let clock, clockReveal > 0, clock.halo.count == logoFade.count else {
            mask = logoMask
            halo = logoFade
            return
        }
        let soft = clock.softness
        for index in halo.indices {
            let reveal = clock.delay.isEmpty ? clockReveal
                : max(0, min(1, (clockReveal * (1 + soft) - clock.delay[index]) / soft))
            let digits = clock.mask.isEmpty ? 0 : clock.mask[index] * reveal
            if clock.replacesLogo {
                // Each cell turns from the logo's coverage to the digits'.
                mask[index] = logoMask[index] * (1 - reveal) + digits
                halo[index] = logoFade[index] * (1 - reveal) + clock.halo[index] * reveal
            } else {
                mask[index] = max(logoMask[index], digits)
                halo[index] = max(logoFade[index], clock.halo[index] * reveal)
            }
        }
    }

    /// Advances the simulation to `time` seconds and writes every cell of `grid`.
    public func step(time: Double, dt: Double, grid: inout CellGrid) {
        let scale = Self.scale
        let aspect = Self.aspect
        let warpTime = Float(time * 0.07)
        let hueTime = Float(time * 0.03)
        let drift = Float(time * 0.02)

        for cy in 0..<coarseRows {
            for cx in 0..<coarseCols {
                let x = Float(cx * Self.coarseX) * scale
                let y = Float(cy * Self.coarseY) * aspect * scale
                let index = cy * coarseCols + cx
                warpX[index] = valueNoise(x * 0.6, y * 0.6, warpTime, seed: seed &+ 1)
                warpY[index] = valueNoise(x * 0.6 + 31.4, y * 0.6 + 7.7, warpTime, seed: seed &+ 2)
                hue[index] = valueNoise(x * 0.3, y * 0.3, hueTime, seed: seed &+ 3)
            }
        }

        let ramp = Self.ramp
        let top = ramp.count - 1
        let coarseCols = coarseCols
        let seed = seed
        warpX.withUnsafeBufferPointer { warpX in
            warpY.withUnsafeBufferPointer { warpY in
                hue.withUnsafeBufferPointer { hue in
                    grid.bytes.withUnsafeMutableBufferPointer { cells in
                        for y in 0..<rows {
                            let cy = y / Self.coarseY
                            let ty = Float(y % Self.coarseY) / Float(Self.coarseY)
                            for x in 0..<cols {
                                let cx = x / Self.coarseX
                                let tx = Float(x % Self.coarseX) / Float(Self.coarseX)
                                let i = cy * coarseCols + cx
                                func sample(_ field: UnsafeBufferPointer<Float>) -> Float {
                                    let upper = field[i] + (field[i + 1] - field[i]) * tx
                                    let lower = field[i + coarseCols]
                                        + (field[i + coarseCols + 1] - field[i + coarseCols]) * tx
                                    return upper + (lower - upper) * ty
                                }
                                let px = Float(x) * scale + (sample(warpX) - 0.5) * 3 + drift
                                let py = Float(y) * aspect * scale + (sample(warpY) - 0.5) * 3
                                var value = 0.65 * valueNoise(px, py, seed: seed)
                                    + 0.35 * valueNoise(px * 2.3, py * 2.3, seed: seed &+ 9)
                                value = max(0, min(0.999, (value - 0.3) / 0.56))

                                let index = y * cols + x
                                let logo = mask[index]
                                if logo > 0.08 {
                                    // Solid interior shimmers through the dense
                                    // end of the ramp; edges thin out by coverage.
                                    let level = logo > 0.9 ? top - 2 + Int(value * 3) : Int(logo * Float(top))
                                    cells.setCell(index, glyph: ramp[min(top, level)], ink: Ink.foreground,
                                                  intensity: 0.8 + 0.2 * value)
                                    continue
                                }

                                value *= 1 - min(1, halo[index] * 1.6)
                                let level = Int(value * Float(ramp.count))
                                let tint = sample(hue)
                                let ink = level <= 2 ? Ink.soft : tint < 0.46 ? Ink.a : tint < 0.58 ? Ink.b : Ink.c
                                cells.setCell(index, glyph: ramp[level], ink: ink, intensity: 0.3 + 0.7 * value)
                            }
                        }
                        if let clock, clockReveal > 0 {
                            for (cell, glyph) in clock.text {
                                cells.setCell(cell, glyph: glyph, ink: Ink.foreground, intensity: 0.85 * clockReveal)
                            }
                        }
                    }
                }
            }
        }
    }
}
