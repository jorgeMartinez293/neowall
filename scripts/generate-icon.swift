#!/usr/bin/env swift
// Draws the neowall app icon: yellow dots on black, the wallpaper reduced to
// one idea, a density ramp flowing across a grid of cells.
//
//   swift scripts/generate-icon.swift           # previews in icon-variants/
//   swift scripts/generate-icon.swift install   # writes Resources/AppIcon.icns
import AppKit

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255, alpha: 1
    )
}

let background: UInt32 = 0x0a0a0a
let yellow: UInt32 = 0xffd60a

/// The density ramp as a field of dots: a wave of weight crossing the grid.
/// Drawn in a 1024 point canvas.
func drawMark(_ context: CGContext) {
    let count = 5
    let pitch: CGFloat = 112
    let origin = 512 - pitch * CGFloat(count - 1) / 2
    context.setFillColor(color(yellow))
    for row in 0..<count {
        for col in 0..<count {
            // Phase runs along the diagonal, bent a little so the front curves.
            let phase = CGFloat(col) * 0.62 + CGFloat(row) * 0.62 + sin(CGFloat(col - row) * 0.55) * 0.5
            let weight = 0.5 + 0.5 * sin(phase * 1.15 - 1.2)
            let radius = 14 + 34 * weight
            context.fillEllipse(in: CGRect(
                x: origin + CGFloat(col) * pitch - radius, y: origin + CGFloat(row) * pitch - radius,
                width: radius * 2, height: radius * 2
            ))
        }
    }
}

func render(pixels: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    // The macOS icon grid: an 824 point body centred in a 1024 point canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    context.addPath(CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil))
    context.clip()
    context.setFillColor(color(background))
    context.fill(body)
    drawMark(context)
    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: Output

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let arguments = CommandLine.arguments.dropFirst()

if arguments.first == "install" {
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        write(render(pixels: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
        write(render(pixels: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
    }
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
    try! iconutil.run()
    iconutil.waitUntilExit()
    try? FileManager.default.removeItem(at: iconset)
    print("Resources/AppIcon.icns")
} else {
    let directory = root.appendingPathComponent("icon-variants")
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for pixels in [1024, 128, 64, 32] {
        write(render(pixels: pixels), to: directory.appendingPathComponent("halftone-\(pixels).png"))
    }
    print("icon-variants/")
}
