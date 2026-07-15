// SPDX-FileCopyrightText: 2026 Twarge LLC
// SPDX-License-Identifier: Apache-2.0
//
// Builds the Observatory/Geomagnetic app icon set from a single source artwork (e.g. the
// magnetosphere render) instead of drawing it procedurally. Run:
//
//     swift Scripts/make-app-icons.swift [source.png] [bleed]
//
// Defaults: source = Resources/AppIconSource.png, bleed = 1.10
//
// Per-platform rules the App Store enforces:
//   • iOS / iPadOS / watchOS — a full-bleed, OPAQUE, square PNG with NO rounded corners and
//     NO alpha channel. The system rounds iOS and circular-masks the watch. (A pre-rounded
//     icon with transparent corners is rejected: "icon can't contain an alpha channel".)
//   • macOS — the rounded "squircle" baked in, centered with padding + transparency + a soft
//     shadow (the classic Big Sur icon grid).
//
// `bleed` (>1) scales the artwork up and center-crops so any drawn frame/rounded border in
// the source is pushed off the edge, giving a clean full-bleed scene. Use 1.0 to keep the
// source framing intact.

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let args = CommandLine.arguments
let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()
let sourcePath = args.count > 1 ? args[1]
    : projectRoot.appendingPathComponent("Resources/AppIconSource.png").path
let bleed = CGFloat(args.count > 2 ? (Double(args[2]) ?? 1.10) : 1.10)

func loadImage(_ path: String) -> CGImage {
    guard FileManager.default.fileExists(atPath: path) else {
        fatalError("Source image not found: \(path)\nSave your artwork there (square PNG, ≥1024px) and re-run.")
    }
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fatalError("Could not decode image at \(path)")
    }
    return img
}

// Draw `img` to fill `box` (aspect-fill), scaled by `bleed`, clipped to `box`.
func drawAspectFill(_ img: CGImage, in box: CGRect, ctx: CGContext) {
    let iw = CGFloat(img.width), ih = CGFloat(img.height)
    let scale = max(box.width / iw, box.height / ih) * bleed
    let w = iw * scale, h = ih * scale
    let rect = CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    ctx.saveGState()
    ctx.addRect(box); ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(img, in: rect)
    ctx.restoreGState()
}

let space = CGColorSpaceCreateDeviceRGB()

// Opaque full-bleed square (iOS / watchOS).
func renderFullBleed(_ src: CGImage, size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.setFillColor(CGColor(red: 0.01, green: 0.02, blue: 0.05, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    drawAspectFill(src, in: CGRect(x: 0, y: 0, width: s, height: s), ctx: ctx)
    return ctx.makeImage()!
}

// Padded rounded squircle with a soft shadow + transparent margin (macOS).
func renderMac(_ src: CGImage, size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    let pad = s * 0.085
    let body = CGRect(x: pad, y: pad, width: s - 2 * pad, height: s - 2 * pad)
    let radius = body.width * 0.2237
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
    ctx.addPath(bodyPath)
    ctx.setFillColor(CGColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    drawAspectFill(src, in: body, ctx: ctx)
    ctx.restoreGState()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Could not create \(path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let source = loadImage(sourcePath)
let appSet = projectRoot.appendingPathComponent("Resources/App/Assets.xcassets/AppIcon.appiconset")
let watchSet = projectRoot.appendingPathComponent("Resources/Watch/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: appSet, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: watchSet, withIntermediateDirectories: true)

writePNG(renderFullBleed(source, size: 1024), to: appSet.appendingPathComponent("icon-ios-1024.png").path)
for px in [16, 32, 64, 128, 256, 512, 1024] {
    writePNG(renderMac(source, size: px), to: appSet.appendingPathComponent("icon-mac-\(px).png").path)
}
writePNG(renderFullBleed(source, size: 1024), to: watchSet.appendingPathComponent("icon-watch-1024.png").path)

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

writePNG(renderFullBleed(source, size: 512), to: "/tmp/icon-preview-ios.png")
writePNG(renderMac(source, size: 512), to: "/tmp/icon-preview-mac.png")
print("Wrote app + watch icon sets from \(sourcePath) (bleed \(bleed)). Previews: /tmp/icon-preview-*.png")
