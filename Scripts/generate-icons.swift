// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// Generates the Observatory app icon set for iOS, macOS, and watchOS.
//
// The icon shows a couple of days of geomagnetic field variation as a glowing trace over a
// faint grid, framed by a rim that matches the platform's icon shape (rounded square for
// iOS/macOS, circle for watchOS). Run with:  swift Scripts/generate-icons.swift
//
// Writes PNGs and Contents.json into Resources/App/Assets.xcassets/AppIcon.appiconset and
// Resources/Watch/Assets.xcassets/AppIcon.appiconset.

import CoreGraphics
import ImageIO
import Foundation

enum IconShape { case iosFullBleed, macPadded, watchCircle }

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

// A couple of days of plausible geomagnetic variation: two diurnal cycles plus finer ripples.
func variation(_ t: Double) -> Double {
    0.55 * sin(2 * .pi * 2 * t - .pi / 2)
        + 0.17 * sin(2 * .pi * 5 * t + 0.6)
        + 0.10 * sin(2 * .pi * 13 * t + 1.2)
        + 0.05 * sin(2 * .pi * 27 * t + 0.3)
}

func drawIcon(size: Int, shape: IconShape) -> CGImage {
    let s = CGFloat(size)
    let space = CGColorSpaceCreateDeviceRGB()
    // iOS/watch icons must be opaque, full-bleed squares (the system applies the mask).
    // macOS icons are a padded rounded tile with transparent corners.
    let opaque = shape != .macPadded
    let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space, bitmapInfo: alpha.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // The region the artwork fills, and the path of the icon's shape (for clipping mac and
    // for the rim everywhere).
    let body: CGRect
    let bodyPath: CGPath
    switch shape {
    case .iosFullBleed, .watchCircle:
        body = CGRect(x: 0, y: 0, width: s, height: s)
        bodyPath = CGPath(rect: body, transform: nil)
    case .macPadded:
        let pad = s * 0.085
        body = CGRect(x: pad, y: pad, width: s - 2 * pad, height: s - 2 * pad)
        bodyPath = CGPath(roundedRect: body, cornerWidth: body.width * 0.18, cornerHeight: body.width * 0.18, transform: nil)
    }

    // A subtle shadow gives the padded macOS icon its "floating tile" look.
    if shape == .macPadded {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                      color: rgb(0, 0, 0, 0.45))
        ctx.addPath(bodyPath)
        ctx.setFillColor(rgb(0.03, 0.06, 0.11, 1))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    // Background gradient.
    let bg = CGGradient(colorsSpace: space,
                        colors: [rgb(0.06, 0.18, 0.36), rgb(0.02, 0.04, 0.09)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: body.midX, y: body.maxY),
                           end: CGPoint(x: body.midX, y: body.minY), options: [])

    // Faint grid behind the trace.
    ctx.setStrokeColor(rgb(0.62, 0.76, 1.0, 0.12))
    ctx.setLineWidth(max(0.75, s * 0.004))
    let cols = 8, rows = 6
    for i in 1..<cols {
        let x = body.minX + body.width * CGFloat(i) / CGFloat(cols)
        ctx.move(to: CGPoint(x: x, y: body.minY)); ctx.addLine(to: CGPoint(x: x, y: body.maxY))
    }
    for j in 1..<rows {
        let y = body.minY + body.height * CGFloat(j) / CGFloat(rows)
        ctx.move(to: CGPoint(x: body.minX, y: y)); ctx.addLine(to: CGPoint(x: body.maxX, y: y))
    }
    ctx.strokePath()

    // The field-variation trace.
    let plot = body.insetBy(dx: body.width * 0.13, dy: body.height * 0.22)
    let count = 260
    var points: [CGPoint] = []
    points.reserveCapacity(count + 1)
    for i in 0...count {
        let t = Double(i) / Double(count)
        let x = plot.minX + plot.width * CGFloat(t)
        let y = plot.midY + plot.height * 0.5 * CGFloat(variation(t))
        points.append(CGPoint(x: x, y: y))
    }
    let trace = CGMutablePath()
    trace.addLines(between: points)

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    // Glow.
    ctx.setStrokeColor(rgb(0.30, 0.72, 1.0, 0.45))
    ctx.setLineWidth(max(2, s * 0.05))
    ctx.addPath(trace); ctx.strokePath()
    // Crisp line.
    ctx.setStrokeColor(rgb(0.87, 0.96, 1.0, 1.0))
    ctx.setLineWidth(max(1.5, s * 0.022))
    ctx.addPath(trace); ctx.strokePath()
    // Dot at the most recent point.
    if let last = points.last {
        let r = max(2, s * 0.026)
        ctx.setFillColor(rgb(1, 1, 1, 1))
        ctx.fillEllipse(in: CGRect(x: last.x - r, y: last.y - r, width: 2 * r, height: 2 * r))
    }

    ctx.restoreGState()  // drop the clip

    // Rim matching the icon shape, inset so it reads inside the system mask.
    let rimWidth = max(2, s * 0.026)
    let inset = rimWidth * (shape == .macPadded ? 0.5 : 1.6)
    let rimRect = body.insetBy(dx: inset, dy: inset)
    let rimPath: CGPath
    switch shape {
    case .watchCircle:
        rimPath = CGPath(ellipseIn: rimRect, transform: nil)
    case .iosFullBleed:
        rimPath = CGPath(roundedRect: rimRect, cornerWidth: s * 0.2237 - inset, cornerHeight: s * 0.2237 - inset, transform: nil)
    case .macPadded:
        rimPath = CGPath(roundedRect: rimRect, cornerWidth: body.width * 0.18 - inset, cornerHeight: body.width * 0.18 - inset, transform: nil)
    }
    ctx.addPath(rimPath)
    ctx.setStrokeColor(rgb(0.42, 0.80, 1.0, 0.92))
    ctx.setLineWidth(rimWidth)
    ctx.strokePath()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("Could not create \(path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let root = URL(fileURLWithPath: CommandLine.arguments.first.map {
    URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path
} ?? FileManager.default.currentDirectoryPath)
// Robust root: this script lives in Scripts/, so go up one from its directory.
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()

let appSet = projectRoot.appendingPathComponent("Resources/App/Assets.xcassets/AppIcon.appiconset")
let watchSet = projectRoot.appendingPathComponent("Resources/Watch/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: appSet, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: watchSet, withIntermediateDirectories: true)

// iOS single-size icon (full bleed).
writePNG(drawIcon(size: 1024, shape: .iosFullBleed), to: appSet.appendingPathComponent("icon-ios-1024.png").path)

// macOS icon set (padded rounded rect).
let macSizes = [16, 32, 64, 128, 256, 512, 1024]
for px in macSizes {
    writePNG(drawIcon(size: px, shape: .macPadded), to: appSet.appendingPathComponent("icon-mac-\(px).png").path)
}

// watchOS single-size icon (circular).
writePNG(drawIcon(size: 1024, shape: .watchCircle), to: watchSet.appendingPathComponent("icon-watch-1024.png").path)

// Contents.json for the app (iOS + macOS).
let appContents = """
{
  "images" : [
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024", "filename" : "icon-ios-1024.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16", "filename" : "icon-mac-16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16", "filename" : "icon-mac-32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32", "filename" : "icon-mac-32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32", "filename" : "icon-mac-64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon-mac-128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon-mac-256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon-mac-256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon-mac-512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon-mac-512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon-mac-1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try! appContents.write(to: appSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let watchContents = """
{
  "images" : [
    { "idiom" : "universal", "platform" : "watchos", "size" : "1024x1024", "filename" : "icon-watch-1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try! watchContents.write(to: watchSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

// Also drop the three masters into /tmp for a quick look.
writePNG(drawIcon(size: 512, shape: .iosFullBleed), to: "/tmp/icon-preview-ios.png")
writePNG(drawIcon(size: 512, shape: .macPadded), to: "/tmp/icon-preview-mac.png")
writePNG(drawIcon(size: 512, shape: .watchCircle), to: "/tmp/icon-preview-watch.png")

print("Wrote app + watch icon sets and Contents.json; previews in /tmp/icon-preview-*.png")
