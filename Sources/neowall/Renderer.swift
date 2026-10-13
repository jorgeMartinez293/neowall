import AppKit
import Metal
import NeowallCore
import QuartzCore

/// Must match `Uniforms` in Shaders.swift.
private struct Uniforms {
    var origin = SIMD2<Float>()
    var cellSize = SIMD2<Float>()
    var tileSize = SIMD2<Float>()
    var viewport = SIMD2<Float>()
    var gridSize = SIMD2<UInt32>()
    var atlasColumns: UInt32 = 0
    var brightness: Float = 1
    var vignette: Float = 0
    var padding0: Float = 0
    var padding1 = SIMD2<Float>()
    var background = SIMD4<Float>()
    var inks: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
               SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
        = (.zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero)
}

/// Runs the scene on a character grid and draws it with a single full-screen
/// triangle: the fragment shader looks each pixel's cell up in a tiny grid
/// texture and its glyph in the font atlas.
///
/// Each step is drawn into whichever of two stacked layers is hidden, and the
/// top layer's opacity is then animated to reveal it. Core Animation runs that
/// cross-fade in the window server, so the motion between steps is smooth
/// without this process drawing, or even waking, in between.
///
/// An overlay renderer draws the ink alone on a transparent background.
final class Renderer {
    private struct GPU {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLRenderPipelineState
    }

    private static let gpu: GPU? = {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
            descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            return GPU(device: device, queue: queue, pipeline: try device.makeRenderPipelineState(descriptor: descriptor))
        } catch {
            NSLog("neowall: failed to build the render pipeline: \(error)")
            return nil
        }
    }()

    let layer = CALayer()
    private let bottom = CAMetalLayer()
    private let top = CAMetalLayer()
    private var showingTop = false
    private let overlay: Bool
    let seed: UInt64
    private var uniforms = Uniforms()
    private var grid = CellGrid(cols: 0, rows: 0)
    private var scene: FlowScene?
    private var cellPixels = CGSize.zero
    private var logoSize = 0.0
    private var clockFont = ""
    private var logoBounds: CGRect?
    private var clockBounds: CGRect?
    private var cellTexture: MTLTexture?
    private var atlasTexture: MTLTexture?

    init(overlay: Bool = false, seed: UInt64 = .random(in: .min ... .max)) {
        self.overlay = overlay
        self.seed = seed
        for metal in [bottom, top] {
            metal.device = Self.gpu?.device
            metal.pixelFormat = .bgra8Unorm
            metal.framebufferOnly = true
            metal.isOpaque = !overlay
            metal.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            metal.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer.addSublayer(metal)
        }
        // Transparent layers do not hide each other, so the bottom one fades
        // out as the top fades in, and adding the two keeps the ink's
        // strength constant through the fade. Rasterising the pair confines
        // the addition to them; otherwise the top layer would also add itself
        // to whatever is behind the window and every other step would flash.
        if overlay {
            top.compositingFilter = "plusL"
            layer.shouldRasterize = true
        }
    }

    /// Rebuilds the atlas, grid and scene for a drawable of `pixelSize`.
    func configure(pixelSize: CGSize, scale: CGFloat, config: Config, theme: Theme) {
        guard let gpu = Self.gpu, pixelSize.width > 0, pixelSize.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.rasterizationScale = scale
        for metal in [bottom, top] {
            metal.frame = layer.bounds
            metal.contentsScale = scale
            metal.drawableSize = pixelSize
        }
        top.removeAllAnimations()
        top.opacity = 0
        bottom.removeAllAnimations()
        bottom.opacity = 1
        showingTop = false
        CATransaction.commit()

        let cellHeight = max(8, (config.cellSize * scale).rounded())
        let atlas = GlyphAtlas(fontName: config.font, tileHeight: Int(cellHeight))
        let cellWidth = CGFloat(atlas.tileWidth)
        let cols = Int((pixelSize.width / cellWidth).rounded(.up))
        let rows = Int((pixelSize.height / cellHeight).rounded(.up))

        cellPixels = CGSize(width: cellWidth, height: cellHeight)
        logoSize = config.logoSize
        clockFont = config.clockFont
        clockBounds = nil
        let mask = LogoMask.make(
            logo: config.logo, cols: cols, rows: rows,
            cellSize: cellPixels, heightFraction: config.logoSize
        )
        logoBounds = LogoMask.bounds(of: mask, cols: cols, rows: rows)
        grid = CellGrid(cols: cols, rows: rows)
        scene = FlowScene(
            cols: cols, rows: rows, seed: seed, mask: mask,
            clearings: overlay ? lockScreenClearings(cols: cols, rows: rows) : []
        )

        let atlasDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: atlas.width, height: atlas.height, mipmapped: false
        )
        atlasTexture = gpu.device.makeTexture(descriptor: atlasDescriptor)
        atlasTexture?.replace(
            region: MTLRegionMake2D(0, 0, atlas.width, atlas.height), mipmapLevel: 0,
            withBytes: atlas.pixels, bytesPerRow: atlas.width
        )
        let cellDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: cols, height: rows, mipmapped: false
        )
        cellTexture = gpu.device.makeTexture(descriptor: cellDescriptor)

        // Centre the grid so the cells cut off at the edges are symmetric.
        uniforms.origin = SIMD2(
            Float(((pixelSize.width - CGFloat(cols) * cellWidth) / 2).rounded(.down)),
            Float(((pixelSize.height - CGFloat(rows) * cellHeight) / 2).rounded(.down))
        )
        uniforms.cellSize = SIMD2(Float(cellWidth), Float(cellHeight))
        uniforms.tileSize = SIMD2(Float(atlas.tileWidth), Float(atlas.tileHeight))
        uniforms.viewport = SIMD2(Float(pixelSize.width), Float(pixelSize.height))
        uniforms.gridSize = SIMD2(UInt32(cols), UInt32(rows))
        uniforms.atlasColumns = UInt32(GlyphAtlas.columns)
        uniforms.brightness = Float(config.brightness)
        uniforms.vignette = Float(config.vignette)
        uniforms.background = SIMD4(theme.background.r, theme.background.g, theme.background.b, overlay ? 0 : 1)
        withUnsafeMutableBytes(of: &uniforms.inks) { buffer in
            let inks = buffer.bindMemory(to: SIMD4<Float>.self)
            for (index, ink) in theme.inks.prefix(inks.count).enumerated() {
                inks[index] = SIMD4(ink.r, ink.g, ink.b, 1)
            }
        }
    }

    /// Gives the scene a clock that reads `time`. It stays hidden until revealed.
    func setClock(_ style: ClockStyle, time: String) {
        guard let scene else { return }
        let cols = grid.cols, rows = grid.rows
        switch style {
        case .off:
            scene.clock = nil
        case .logo:
            let mask = LogoMask.clock(
                time, font: clockFont, cols: cols, rows: rows, cellSize: cellPixels,
                heightFraction: logoSize * 0.4, inCorner: false
            )
            clockBounds = LogoMask.bounds(of: mask, cols: cols, rows: rows)
            scene.clock = .logo(mask: mask, cols: cols, rows: rows, seed: seed)
        case .corner:
            // Never fewer rows than the digits need to stay legible.
            scene.clock = .corner(mask: LogoMask.clock(
                time, font: clockFont, cols: cols, rows: rows, cellSize: cellPixels,
                heightFraction: max(0.1, 6.5 / Double(rows)), inCorner: true
            ), cols: cols, rows: rows)
        case .text:
            scene.clock = .text(time, cols: cols, rows: rows)
        }
    }

    /// Where the logo and the time that replaces it are, as fractions of the
    /// view from the top left, with a little room around them.
    var logoZone: CGRect {
        let fallback = CGRect(x: 0.4, y: 0.5 - logoSize / 2, width: 0.2, height: logoSize)
        let ink = [logoBounds, clockBounds].compactMap { $0 }
        return ink.dropFirst().reduce(ink.first ?? fallback) { $0.union($1) }.insetBy(dx: -0.02, dy: -0.03)
    }

    /// How far the clock has appeared, 0-1.
    var clockReveal: Float {
        get { scene?.clockReveal ?? 0 }
        set { scene?.clockReveal = newValue }
    }

    /// Steps the scene to `time` and shows the result, cross-fading from the
    /// previous frame over `fade` seconds at up to `frameRate` frames a second.
    /// A zero `fade` swaps the frame in at once.
    func step(time: Double, dt: Double, fade: Double, frameRate: Float) {
        guard let scene, let cellTexture else { return }
        scene.step(time: time, dt: dt, grid: &grid)
        cellTexture.replace(
            region: MTLRegionMake2D(0, 0, grid.cols, grid.rows), mipmapLevel: 0,
            withBytes: grid.bytes, bytesPerRow: grid.cols * 4
        )

        let fading = fade > 0 && frameRate > 0
        let revealTop = fading && !showingTop
        guard draw(into: revealTop ? top : bottom) else { return }
        guard revealTop != showingTop else { return }
        showingTop = revealTop

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Finish a little early so the layer is fully hidden again before
        // the next step draws into it.
        let duration = fading ? fade * 0.9 : 0
        self.fade(top, to: revealTop ? 1 : 0, duration: duration, frameRate: frameRate)
        if overlay { self.fade(bottom, to: revealTop ? 0 : 1, duration: duration, frameRate: frameRate) }
        CATransaction.commit()
    }

    private func fade(_ target: CALayer, to opacity: Float, duration: Double, frameRate: Float) {
        target.opacity = opacity
        guard duration > 0 else { return target.removeAllAnimations() }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1 - opacity
        animation.toValue = opacity
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: frameRate, maximum: frameRate, preferred: frameRate)
        target.add(animation, forKey: "fade")
    }

    private func draw(into target: CAMetalLayer) -> Bool {
        guard let gpu = Self.gpu, let cellTexture, let atlasTexture,
              let drawable = target.nextDrawable(), let commands = gpu.queue.makeCommandBuffer()
        else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.setRenderPipelineState(gpu.pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(cellTexture, index: 0)
        encoder.setFragmentTexture(atlasTexture, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
        return true
    }
}
