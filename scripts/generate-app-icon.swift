#!/usr/bin/env swift
//
// Programmatic RedFluent VPN app icon generator.
// Approximates the Default variant from the design spec:
//   - Dark near-black square base (iOS rounds the corners automatically)
//   - Red brand circle taking ~78% of the canvas
//   - White paper-plane mark from SF Symbols, slightly upper-right
//   - Subtle radial highlight for depth
//
// Usage:
//   swift scripts/generate-app-icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// To replace with the real designed icon later, just drop a 1024x1024 PNG
// at the same path and skip this script.

import Cocoa

guard CommandLine.arguments.count >= 2 else {
    print("usage: swift generate-app-icon.swift <output.png>")
    exit(2)
}

let outputPath = CommandLine.arguments[1]
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    print("error: no graphics context")
    exit(1)
}

// 1. Dark background — full bleed; iOS rounds the corners of the icon shape automatically.
ctx.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1.0))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// 2. Subtle inner shadow for depth on the dark base.
let baseShadowGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.55),
        CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
    ] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawRadialGradient(
    baseShadowGradient,
    startCenter: CGPoint(x: size / 2, y: size / 2 - 80),
    startRadius: 0,
    endCenter:   CGPoint(x: size / 2, y: size / 2),
    endRadius:   size * 0.72,
    options: []
)

// 3. Red brand circle.
let inset: CGFloat = size * 0.11
let circleRect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
ctx.setFillColor(CGColor(red: 0.93, green: 0.16, blue: 0.18, alpha: 1.0))
ctx.fillEllipse(in: circleRect)

// 4. Specular highlight on the red circle (top-left lift).
ctx.saveGState()
ctx.addEllipse(in: circleRect)
ctx.clip()
let specular = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 0.45),
        CGColor(red: 1.0, green: 0.20, blue: 0.20, alpha: 0.0),
    ] as CFArray,
    locations: [0.0, 1.0]
)!
ctx.drawRadialGradient(
    specular,
    startCenter: CGPoint(x: size / 2 - size * 0.10, y: size / 2 + size * 0.14),
    startRadius: 0,
    endCenter:   CGPoint(x: size / 2 - size * 0.10, y: size / 2 + size * 0.14),
    endRadius:   size * 0.42,
    options: []
)
ctx.restoreGState()

// 5. White paper plane mark from SF Symbols.
let symbolPointSize: CGFloat = size * 0.50
let cfg = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
if let raw = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {

    let drawSize = raw.size
    let center = CGPoint(x: size / 2, y: size / 2)
    let drawRect = NSRect(
        x: center.x - drawSize.width / 2,
        y: center.y - drawSize.height / 2 - drawSize.height * 0.05,
        width: drawSize.width,
        height: drawSize.height
    )

    // Render the symbol then tint white via source-atop fill.
    let tinted = NSImage(size: drawSize, flipped: false) { rect in
        raw.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
} else {
    // Fallback: draw a simple white triangle if SF Symbols are unavailable.
    let cx = size / 2
    let cy = size / 2
    let armLong:  CGFloat = size * 0.20
    let armShort: CGFloat = size * 0.12
    let path = NSBezierPath()
    path.move(to: NSPoint(x: cx + armLong, y: cy + armLong))
    path.line(to: NSPoint(x: cx - armLong, y: cy - armShort))
    path.line(to: NSPoint(x: cx - armShort, y: cy))
    path.line(to: NSPoint(x: cx - armShort, y: cy + armLong))
    path.close()
    NSColor.white.setFill()
    path.fill()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    print("error: could not encode PNG")
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote app icon to \(outputPath) (\(png.count) bytes)")
