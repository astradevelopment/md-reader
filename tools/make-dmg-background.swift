#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Renders the installer window's backdrop: an arrow pointing from the app to the
// Applications folder. Deliberately wordless — the disk image is one file for
// both languages the app ships in.
//
// Usage:  swift tools/make-dmg-background.swift <output-dir>

let outDir = CommandLine.arguments.dropFirst().first ?? "build/dmg"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let width = 660
let height = 420

/// Where the two icons sit, in window points measured from the top-left.
let appCentre = CGPoint(x: 170, y: 190)
let destCentre = CGPoint(x: 490, y: 190)

func draw(scale: Int) -> Data? {
    let w = width * scale
    let h = height * scale
    guard let ctx = CGContext(
        data: nil, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let s = CGFloat(scale)
    ctx.scaleBy(x: s, y: s)
    // Flip to window coordinates: y downwards, origin top-left.
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)

    // A quiet vertical wash, light enough that both icons stay legible.
    let colours = [
        CGColor(red: 0.976, green: 0.980, blue: 0.988, alpha: 1),
        CGColor(red: 0.925, green: 0.933, blue: 0.949, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colours, locations: [0, 1]) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: CGFloat(height)),
            options: []
        )
    }

    // The arrow, from just past the app to just before the destination.
    let y = appCentre.y
    let startX = appCentre.x + 92
    let endX = destCentre.x - 92
    let headLength: CGFloat = 22
    let shaftEnd = endX - headLength

    ctx.setStrokeColor(CGColor(red: 0.62, green: 0.65, blue: 0.70, alpha: 1))
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: startX, y: y))
    ctx.addLine(to: CGPoint(x: shaftEnd, y: y))
    ctx.strokePath()

    ctx.setFillColor(CGColor(red: 0.62, green: 0.65, blue: 0.70, alpha: 1))
    ctx.move(to: CGPoint(x: endX, y: y))
    ctx.addLine(to: CGPoint(x: shaftEnd, y: y - 13))
    ctx.addLine(to: CGPoint(x: shaftEnd, y: y + 13))
    ctx.closePath()
    ctx.fillPath()

    guard let image = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
}

for scale in [1, 2] {
    let name = scale == 1 ? "background.png" : "background@2x.png"
    guard let data = draw(scale: scale) else {
        FileHandle.standardError.write("failed to render \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    let path = "\(outDir)/\(name)"
    try? data.write(to: URL(fileURLWithPath: path))
    print("→ \(path)")
}
