import AppKit
import CoreText
import NeowallCore

/// Rasterises the centre logo straight into grid resolution: one coverage
/// value per cell.
enum LogoMask {
    /// `apple` maps to the Apple logo glyph that system fonts carry in the
    /// private use area; any other value is drawn as text.
    static func make(logo: String, cols: Int, rows: Int, cellSize: CGSize, heightFraction: Double) -> [Float] {
        rasterise(
            logo == "none" ? "" : logo == "apple" ? "\u{F8FF}" : logo, font: .systemFont(ofSize: 200, weight: .bold),
            cols: cols, rows: rows, cellSize: cellSize, heightFraction: heightFraction, inCorner: false
        )
    }

    /// The time in large digits, centred like the logo or set into the top
    /// right corner.
    static func clock(_ time: String, font: String, cols: Int, rows: Int, cellSize: CGSize,
                      heightFraction: Double, inCorner: Bool) -> [Float] {
        guard font != "blocks" else {
            return blockClock(time, cols: cols, rows: rows, heightFraction: heightFraction, inCorner: inCorner)
        }
        return rasterise(
            time, font: clockFont(font),
            cols: cols, rows: rows, cellSize: cellSize, heightFraction: heightFraction, inCorner: inCorner
        )
    }

    /// A design of the system font by keyword, or an installed font by name.
    private static func clockFont(_ name: String) -> NSFont {
        let system = NSFont.systemFont(ofSize: 200, weight: .bold)
        let designs: [String: NSFontDescriptor.SystemDesign] = [
            "system": .default, "rounded": .rounded, "serif": .serif, "mono": .monospaced,
        ]
        let font = designs[name].map { system.fontDescriptor.withDesign($0).flatMap { NSFont(descriptor: $0, size: 200) } ?? system }
            ?? NSFont(name: name, size: 200)
            ?? NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: 200)
            ?? system
        // Digits of one width keep the time from shifting as it changes.
        let tabular = font.fontDescriptor.addingAttributes([.featureSettings: [[
            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
        ]]])
        return NSFont(descriptor: tabular, size: 200) ?? font
    }

    /// The box around a mask's ink as fractions of the grid, from the top left.
    static func bounds(of mask: [Float], cols: Int, rows: Int) -> CGRect? {
        var minX = cols, maxX = -1, minY = rows, maxY = -1
        for y in 0..<rows {
            for x in 0..<cols where mask[y * cols + x] > 0.08 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(
            x: CGFloat(minX) / CGFloat(cols), y: CGFloat(minY) / CGFloat(rows),
            width: CGFloat(maxX - minX + 1) / CGFloat(cols), height: CGFloat(maxY - minY + 1) / CGFloat(rows)
        )
    }

    private static func rasterise(_ text: String, font: NSFont, cols: Int, rows: Int, cellSize: CGSize,
                                  heightFraction: Double, inCorner: Bool) -> [Float] {
        var mask = [Float](repeating: 0, count: cols * rows)
        guard !text.isEmpty, cols > 0, rows > 0 else { return mask }

        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: NSColor.white]
        ))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        guard bounds.width > 0, bounds.height > 0 else { return mask }

        let viewWidth = CGFloat(cols) * cellSize.width
        let viewHeight = CGFloat(rows) * cellSize.height
        let scale = min(viewHeight * heightFraction / bounds.height, viewWidth * 0.8 / bounds.width)

        var pixels = [UInt8](repeating: 0, count: cols * rows)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: cols, height: rows, bitsPerComponent: 8,
                bytesPerRow: cols, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            // One bitmap pixel is one cell, so screen pixels shrink by the cell size.
            context.scaleBy(x: 1 / cellSize.width, y: 1 / cellSize.height)
            if inCorner {
                // Inset far enough to clear the menu bar.
                let inset = viewHeight * 0.07
                context.translateBy(
                    x: viewWidth - inset - bounds.width * scale / 2,
                    y: viewHeight - inset - bounds.height * scale / 2
                )
            } else {
                context.translateBy(x: viewWidth / 2, y: viewHeight / 2)
            }
            context.scaleBy(x: scale, y: scale)
            context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
            CTLineDraw(line, context)
        }
        for index in mask.indices { mask[index] = Float(pixels[index]) / 255 }
        return mask
    }
}
