#!/usr/bin/env swift
// CleanPilot app icon. Vector geometry mirrors design/cleanpilot-logo.svg.
// CoreGraphics only: deterministic rendering without CoreImage, fonts, or GPU access.
import CoreGraphics
import Foundation
import ImageIO

private let canvas: CGFloat = 1024
private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ rgb: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [
        CGFloat((rgb >> 16) & 255) / 255,
        CGFloat((rgb >> 8) & 255) / 255,
        CGFloat(rgb & 255) / 255, alpha
    ])!
}

func polygon(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path
}

func renderMaster() -> CGImage? {
    let pixels = 2048
    guard let context = CGContext(data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    context.translateBy(x: 0, y: canvas)
    context.scaleBy(x: 1, y: -1)
    context.setAllowsAntialiasing(true)
    let tile = CGPath(roundedRect: CGRect(x: 88, y: 88, width: 848, height: 848),
                      cornerWidth: 190, cornerHeight: 190, transform: nil)
    context.saveGState()
    context.addPath(tile)
    context.clip()
    if let gradient = CGGradient(colorsSpace: colorSpace,
        colors: [color(0x12253F), color(0x2177B4)] as CFArray, locations: [0, 1]) {
        context.drawLinearGradient(gradient, start: CGPoint(x: 88, y: 936),
                                   end: CGPoint(x: 936, y: 88),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    context.restoreGState()
    context.addPath(CGPath(roundedRect: CGRect(x: 89, y: 89, width: 846, height: 846),
                           cornerWidth: 189, cornerHeight: 189, transform: nil))
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.18))
    context.setLineWidth(2)
    context.strokePath()

    // Open C: the flight path. Rounded ends remain legible at Dock sizes.
    let orbit = CGMutablePath()
    orbit.move(to: CGPoint(x: 596, y: 302))
    orbit.addCurve(to: CGPoint(x: 318, y: 444),
                   control1: CGPoint(x: 468, y: 246), control2: CGPoint(x: 350, y: 312))
    orbit.addCurve(to: CGPoint(x: 554, y: 734),
                   control1: CGPoint(x: 264, y: 612), control2: CGPoint(x: 388, y: 744))
    orbit.addCurve(to: CGPoint(x: 666, y: 688),
                   control1: CGPoint(x: 602, y: 732), control2: CGPoint(x: 640, y: 716))
    context.addPath(orbit)
    context.setStrokeColor(color(0xF6FFFC))
    context.setLineWidth(82)
    context.setLineCap(.round)
    context.strokePath()

    // A mint navigation arrow: forward motion and the Pilot half of the name.
    context.setFillColor(color(0x95F1D4))
    context.addPath(polygon([
        CGPoint(x: 460, y: 474), CGPoint(x: 788, y: 310),
        CGPoint(x: 662, y: 640), CGPoint(x: 590, y: 528)
    ]))
    context.fillPath()
    context.move(to: CGPoint(x: 590, y: 528))
    context.addLine(to: CGPoint(x: 732, y: 374))
    context.setStrokeColor(color(0x123D55))
    context.setLineWidth(12)
    context.setLineCap(.round)
    context.strokePath()
    return context.makeImage()
}

func resized(_ image: CGImage, pixels: Int) -> CGImage? {
    // Repeated halving keeps the 16/32 px silhouettes clean.
    var current = image
    while current.width > pixels {
        let side = max(pixels, current.width / 2)
        guard let context = CGContext(data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(current, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let next = context.makeImage() else { return nil }
        current = next
    }
    return current
}

let destination = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
guard let master = renderMaster() else { fatalError("Cannot render CleanPilot icon") }
let sizes = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, pixels) in sizes {
    guard let image = resized(master, pixels: pixels),
          let png = CGImageDestinationCreateWithURL(destination.appendingPathComponent(name) as CFURL,
                                                     "public.png" as CFString, 1, nil) else {
        fatalError("Cannot generate \(name)")
    }
    CGImageDestinationAddImage(png, image, nil)
    guard CGImageDestinationFinalize(png) else { fatalError("Cannot save \(name)") }
    print("CleanPilot \(name) — \(pixels) px")
}
