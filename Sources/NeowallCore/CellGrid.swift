/// The character buffer a scene writes and the renderer uploads as an RGBA8
/// texture: glyph index, ink index, intensity, unused.
public struct CellGrid {
    public static let blank: UInt8 = 0

    public let cols: Int
    public let rows: Int
    public var bytes: [UInt8]

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        bytes = [UInt8](repeating: 0, count: cols * rows * 4)
    }

    /// Glyph index of a printable ASCII character; anything else is blank.
    public static func glyph(_ ascii: UInt8) -> UInt8 {
        ascii > 32 && ascii < 127 ? ascii - 31 : blank
    }
}

extension UnsafeMutableBufferPointer where Element == UInt8 {
    @inline(__always)
    func setCell(_ index: Int, glyph: UInt8, ink: UInt8, intensity: Float) {
        let offset = index * 4
        self[offset] = glyph
        self[offset + 1] = ink
        self[offset + 2] = UInt8(Swift.max(0, Swift.min(1, intensity)) * 255)
        self[offset + 3] = 255
    }
}
