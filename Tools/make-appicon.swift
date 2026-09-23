#!/usr/bin/env swift
//
// Renders the iOS app icon from internal/api/web/favicon.svg.
//
//   swift Tools/make-appicon.swift
//
// Writes TemporalWordflow/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
// — a full-bleed ultraviolet square with the favicon's white four-pointed star.
// The corner radius the SVG carries is dropped on purpose: iOS masks app icons
// itself, and a pre-rounded icon would show a dark halo inside the mask.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024
/// The favicon is authored in a 64×64 viewBox with y pointing down.
let viewBox: CGFloat = 64
let scale = CGFloat(side) / viewBox

let ultraviolet = CGColor(srgbRed: 0x44 / 255, green: 0x4C / 255, blue: 0xE7 / 255, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

/// `M32 7c2 15 10 23 25 25-15 2-23 10-25 25-2-15-10-23-25-25 15-2 23-10 25-25Z`,
/// resolved from the SVG's relative cubics into absolute 64-space points.
func starPath() -> CGPath {
    // Flip y (SVG grows downwards, CoreGraphics upwards) and scale to the canvas.
    let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: CGFloat(side))
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 32, y: 7), transform: transform)
    path.addCurve(to: CGPoint(x: 57, y: 32),
                  control1: CGPoint(x: 34, y: 22),
                  control2: CGPoint(x: 42, y: 30),
                  transform: transform)
    path.addCurve(to: CGPoint(x: 32, y: 57),
                  control1: CGPoint(x: 42, y: 34),
                  control2: CGPoint(x: 34, y: 42),
                  transform: transform)
    path.addCurve(to: CGPoint(x: 7, y: 32),
                  control1: CGPoint(x: 30, y: 42),
                  control2: CGPoint(x: 22, y: 34),
                  transform: transform)
    path.addCurve(to: CGPoint(x: 32, y: 7),
                  control1: CGPoint(x: 22, y: 30),
                  control2: CGPoint(x: 30, y: 22),
                  transform: transform)
    path.closeSubpath()
    return path
}

// App icons must be opaque, so the context carries no alpha channel.
guard let context = CGContext(data: nil,
                              width: side,
                              height: side,
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    FileHandle.standardError.write(Data("could not create the bitmap context\n".utf8))
    exit(1)
}

context.setShouldAntialias(true)
context.interpolationQuality = .high
context.setFillColor(ultraviolet)
context.fill(CGRect(x: 0, y: 0, width: side, height: side))
context.setFillColor(white)
context.addPath(starPath())
context.fillPath()

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("could not render the icon\n".utf8))
    exit(1)
}

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let output = repoRoot
    .appendingPathComponent("TemporalWordflow/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")

try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)

guard let destination = CGImageDestinationCreateWithURL(output as CFURL,
                                                        UTType.png.identifier as CFString,
                                                        1,
                                                        nil) else {
    FileHandle.standardError.write(Data("could not open \(output.path)\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("could not write \(output.path)\n".utf8))
    exit(1)
}

let bytes = (try? FileManager.default.attributesOfItem(atPath: output.path))?[.size] as? Int ?? 0
print("wrote \(output.path) — \(side)×\(side), \(bytes) bytes")
