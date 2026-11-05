#!/usr/bin/env swift
// CleanPilot app icon, generated from the approved dachshund artwork.
// CoreGraphics only: deterministic resizing without CoreImage, fonts, or GPU access.
import CoreGraphics
import Foundation
import ImageIO

private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

// Keep the approved artwork as the single source for every Dock and in-app size.
// Resolve beside this script so invocation does not depend on the working directory.
func loadMaster() -> CGImage {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("AppIcon-master.png")
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Cannot load CleanPilot icon artwork: \(sourceURL.path)")
    }
    guard image.width == image.height, image.width >= 1024 else {
        fatalError("CleanPilot icon artwork must be square and at least 1024 px")
    }
    return image
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
let master = loadMaster()
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
