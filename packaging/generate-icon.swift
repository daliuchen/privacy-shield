#!/usr/bin/env swift
// Generates AppIcon.iconset with all required sizes for macOS.
// Uses only CoreGraphics — no external dependencies needed.
import Cocoa

func createIcon(pixels: Int) -> NSBitmapImageRep {
    let s = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let scale = s / 1024.0

    // ── Background gradient ──
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        CGColor(red: 0.14, green: 0.15, blue: 0.24, alpha: 1),
        CGColor(red: 0.06, green: 0.07, blue: 0.12, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: s / 2, y: s),
                           end: CGPoint(x: s / 2, y: 0), options: [])

    // Move origin to center and scale so design space is -512..512
    ctx.translateBy(x: s / 2, y: s / 2)
    ctx.scaleBy(x: scale, y: scale)

    // ── Shield path ──
    let shield = CGMutablePath()
    shield.move(to: .init(x: 0, y: 310))
    shield.addCurve(to: .init(x: 270, y: 190),
                    control1: .init(x: 150, y: 310), control2: .init(x: 270, y: 280))
    shield.addCurve(to: .init(x: 0, y: -330),
                    control1: .init(x: 270, y: -10), control2: .init(x: 90, y: -230))
    shield.addCurve(to: .init(x: -270, y: 190),
                    control1: .init(x: -90, y: -230), control2: .init(x: -270, y: -10))
    shield.addCurve(to: .init(x: 0, y: 310),
                    control1: .init(x: -270, y: 280), control2: .init(x: -150, y: 310))
    shield.closeSubpath()

    // Shield fill — blue gradient, clipped to path
    ctx.saveGState()
    ctx.addPath(shield)
    ctx.clip()
    let sf = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        CGColor(red: 0.30, green: 0.58, blue: 0.98, alpha: 1),
        CGColor(red: 0.16, green: 0.38, blue: 0.82, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sf, start: .init(x: 0, y: 310),
                           end: .init(x: 0, y: -330), options: [])
    ctx.restoreGState()

    // Shield border
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.15))
    ctx.setLineWidth(4)
    ctx.addPath(shield)
    ctx.strokePath()

    // ── Lock body (rounded rect) ──
    let lockW: CGFloat = 130, lockH: CGFloat = 100
    let lockY: CGFloat = -100
    let lockRect = CGRect(x: -lockW / 2, y: lockY, width: lockW, height: lockH)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.addPath(CGPath(roundedRect: lockRect, cornerWidth: 16, cornerHeight: 16, transform: nil))
    ctx.fillPath()

    // ── Lock shackle ──
    let shR: CGFloat = 38
    let shBase = lockRect.maxY - 6
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.setLineWidth(20)
    ctx.setLineCap(.round)
    ctx.move(to: .init(x: -shR, y: shBase))
    ctx.addLine(to: .init(x: -shR, y: shBase + 44))
    ctx.addArc(center: .init(x: 0, y: shBase + 44), radius: shR,
               startAngle: .pi, endAngle: 0, clockwise: false)
    ctx.addLine(to: .init(x: shR, y: shBase))
    ctx.strokePath()

    // ── Keyhole ──
    let khR: CGFloat = 15
    let khY = lockY + lockH * 0.52
    ctx.setFillColor(CGColor(red: 0.16, green: 0.38, blue: 0.82, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: -khR, y: khY - khR, width: khR * 2, height: khR * 2))
    // Notch
    ctx.move(to: .init(x: -7, y: khY - khR + 2))
    ctx.addLine(to: .init(x: 0, y: lockY + 14))
    ctx.addLine(to: .init(x: 7, y: khY - khR + 2))
    ctx.closePath()
    ctx.fillPath()

    NSGraphicsContext.current = nil
    return rep
}

// ── Generate .iconset directory ──
let iconsetDir: String
if CommandLine.arguments.count > 1 {
    iconsetDir = CommandLine.arguments[1]
} else {
    iconsetDir = "AppIcon.iconset"
}

try FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16",      16),  ("icon_16x16@2x",    32),
    ("icon_32x32",      32),  ("icon_32x32@2x",    64),
    ("icon_128x128",   128),  ("icon_128x128@2x", 256),
    ("icon_256x256",   256),  ("icon_256x256@2x", 512),
    ("icon_512x512",   512),  ("icon_512x512@2x", 1024),
]

for (name, px) in variants {
    let rep = createIcon(pixels: px)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode \(name)")
    }
    let path = "\(iconsetDir)/\(name).png"
    try data.write(to: URL(fileURLWithPath: path))
}

print("Generated \(iconsetDir) (\(variants.count) images)")
