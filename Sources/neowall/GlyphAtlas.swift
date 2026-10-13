import AppKit
import CoreText

/// Printable ASCII (33...126) rasterised into a grid of equal tiles, sized so
/// that one line of the font is exactly `tileHeight` pixels tall.
struct GlyphAtlas {
    static let columns = 16
    private static let characters = Array(UInt16(33)...UInt16(126))

    let tileWidth: Int
    let tileHeight: Int
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(fontName: String, tileHeight: Int) {
        let reference = Self.font(named: fontName, size: 100) as CTFont
        let lineHeight = CTFontGetAscent(reference) + CTFontGetDescent(reference) + CTFontGetLeading(reference)
        let font = CTFontCreateCopyWithAttributes(reference, CGFloat(tileHeight) * 100 / lineHeight, nil, nil)

        var characters = Self.characters
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
        let advance = advances.map(\.width).max() ?? CGFloat(tileHeight) / 2

        let tileWidth = max(1, Int(advance.rounded()))
        let rowCount = (glyphs.count + Self.columns - 1) / Self.columns
        let width = tileWidth * Self.columns
        let height = tileHeight * rowCount
        let baseline = CTFontGetDescent(font) + CTFontGetLeading(font) / 2

        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.setShouldSmoothFonts(false)
            context.setFillColor(gray: 1, alpha: 1)
            for (index, glyph) in glyphs.enumerated() {
                // The bitmap's first row is the top of the image, so tile rows
                // count down from the top in Core Graphics coordinates.
                let tile = CGRect(
                    x: (index % Self.columns) * tileWidth,
                    y: height - (index / Self.columns + 1) * tileHeight,
                    width: tileWidth, height: tileHeight
                )
                var position = CGPoint(
                    x: tile.minX + (CGFloat(tileWidth) - advances[index].width) / 2,
                    y: tile.minY + baseline
                )
                var glyph = glyph
                context.saveGState()
                context.clip(to: tile)
                CTFontDrawGlyphs(font, &glyph, &position, 1, context)
                context.restoreGState()
            }
        }

        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    private static func font(named name: String, size: CGFloat) -> NSFont {
        NSFont(name: name, size: size)
            ?? NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
