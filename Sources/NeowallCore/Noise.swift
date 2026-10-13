public struct SplitMix64 {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    public mutating func unit() -> Float {
        Float(next() >> 40) * (1.0 / 16_777_216.0)
    }

    /// Uniform in 0..<bound.
    public mutating func int(_ bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }
}

@inline(__always)
private func hash(_ x: Int32, _ y: Int32, _ z: Int32, _ seed: UInt32) -> Float {
    var h = UInt32(bitPattern: x) &* 0x85EB_CA6B ^ UInt32(bitPattern: y) &* 0xC2B2_AE35
        ^ UInt32(bitPattern: z) &* 0x27D4_EB2F ^ seed
    h ^= h >> 16
    h &*= 0x7FEB_352D
    h ^= h >> 15
    h &*= 0x846C_A68B
    h ^= h >> 16
    return Float(h >> 8) * (1.0 / 16_777_216.0)
}

@inline(__always)
private func fade(_ t: Float) -> Float {
    t * t * (3 - 2 * t)
}

@inline(__always)
private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * t
}

/// Smooth value noise in [0, 1).
@inline(__always)
func valueNoise(_ x: Float, _ y: Float, seed: UInt32) -> Float {
    let fx = x.rounded(.down), fy = y.rounded(.down)
    let ix = Int32(fx), iy = Int32(fy)
    let tx = fade(x - fx), ty = fade(y - fy)
    return lerp(
        lerp(hash(ix, iy, 0, seed), hash(ix &+ 1, iy, 0, seed), tx),
        lerp(hash(ix, iy &+ 1, 0, seed), hash(ix &+ 1, iy &+ 1, 0, seed), tx),
        ty
    )
}

@inline(__always)
func valueNoise(_ x: Float, _ y: Float, _ z: Float, seed: UInt32) -> Float {
    let fz = z.rounded(.down)
    let iz = Int32(fz)
    let fx = x.rounded(.down), fy = y.rounded(.down)
    let ix = Int32(fx), iy = Int32(fy)
    let tx = fade(x - fx), ty = fade(y - fy)
    func slice(_ z: Int32) -> Float {
        lerp(
            lerp(hash(ix, iy, z, seed), hash(ix &+ 1, iy, z, seed), tx),
            lerp(hash(ix, iy &+ 1, z, seed), hash(ix &+ 1, iy &+ 1, z, seed), tx),
            ty
        )
    }
    return lerp(slice(iz), slice(iz &+ 1), fade(z - fz))
}
