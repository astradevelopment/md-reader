#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Renders the MD Reader app icon at all sizes needed for macOS .icns.
// Usage:  swift tools/make-icon.swift [output-iconset-dir]

let outDir = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(px: Int, name: String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

func drawIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let rect = CGRect(x: 0, y: 0, width: s, height: s)

    // Squircle (rounded) background — Apple uses ~22.37% corner radius for macOS app icons.
    let radius = s * 0.2237
    let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    // Dark slate gradient (top → bottom)
    let bgColors = [
        CGColor(red: 0.14, green: 0.17, blue: 0.23, alpha: 1.0),
        CGColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1.0),
    ]
    let bgGradient = CGGradient(colorsSpace: cs, colors: bgColors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // Subtle inner highlight at top
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let glowColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.07),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ]
    let glow = CGGradient(colorsSpace: cs, colors: glowColors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(glow, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: s * 0.55), options: [])
    ctx.restoreGState()

    // Floating page
    let pageW = s * 0.62
    let pageH = s * 0.76
    let pageX = (s - pageW) / 2
    let pageY = (s - pageH) / 2 + s * 0.005
    let pageRect = CGRect(x: pageX, y: pageY, width: pageW, height: pageH)
    let pageRadius = max(2, s * 0.045)
    let pagePath = CGPath(roundedRect: pageRect, cornerWidth: pageRadius, cornerHeight: pageRadius, transform: nil)

    // Page shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.012),
        blur: s * 0.06,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45)
    )
    ctx.addPath(pagePath)
    ctx.setFillColor(CGColor(red: 0.985, green: 0.985, blue: 0.975, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Content lines inside the page
    let lineH      = s * 0.028
    let lineGap    = s * 0.034
    let leftMargin = pageX + pageW * 0.13
    let maxLineW   = pageW * 0.74
    let cornerR    = lineH * 0.4

    var y = pageY + pageH - s * 0.16

    func fillBar(width: CGFloat, height: CGFloat, color: CGColor) {
        ctx.setFillColor(color)
        let r = CGRect(x: leftMargin, y: y, width: width, height: height)
        let p = CGPath(roundedRect: r, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)
        ctx.addPath(p)
        ctx.fillPath()
    }

    let headingColor = CGColor(red: 0.11, green: 0.14, blue: 0.20, alpha: 1.0)
    let bodyColor    = CGColor(red: 0.62, green: 0.65, blue: 0.70, alpha: 1.0)
    let accentColor  = CGColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1.0)

    // H1 — fat, dark
    let h1H = lineH * 2.2
    fillBar(width: maxLineW * 0.78, height: h1H, color: headingColor)
    y -= h1H + lineGap * 1.6

    // Body
    fillBar(width: maxLineW * 1.0,  height: lineH, color: bodyColor); y -= lineH + lineGap
    fillBar(width: maxLineW * 0.92, height: lineH, color: bodyColor); y -= lineH + lineGap
    fillBar(width: maxLineW * 0.74, height: lineH, color: bodyColor); y -= lineH + lineGap * 1.3

    // Accent line (rendered highlight)
    fillBar(width: maxLineW * 0.48, height: lineH, color: accentColor); y -= lineH + lineGap

    // More body
    fillBar(width: maxLineW * 0.95, height: lineH, color: bodyColor); y -= lineH + lineGap
    fillBar(width: maxLineW * 0.6,  height: lineH, color: bodyColor)

    guard let cgImage = ctx.makeImage() else { return nil }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    guard let tiff = nsImage.tiffRepresentation,
          let rep  = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

for (px, name) in sizes {
    guard let data = drawIcon(size: px) else {
        print("✗ \(name) (failed)")
        continue
    }
    let url = URL(fileURLWithPath: "\(outDir)/\(name)")
    try? data.write(to: url)
    print("✓ \(name) (\(px)x\(px))")
}

print("\nDone. Convert to .icns with:")
print("  iconutil -c icns \(outDir)")
