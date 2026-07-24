#!/usr/bin/env swift
// Generates Resources/AppIcon.icns — a flat "locked dock" mark: dark squircle,
// a dock shelf with three app tiles, and a padlock over the center tile.
// Deterministic (no external assets) so the icon can be regenerated any time:
//   swift Scripts/gen-icon.swift
import AppKit
import CoreGraphics

func drawIcon(size: CGFloat, into context: CGContext) {
    let s = size / 1024.0  // design in 1024-space, scale to target

    // Background squircle (approximated rounded rect, Big Sur corner ratio).
    let bgRect = CGRect(x: 0, y: 0, width: 1024 * s, height: 1024 * s)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 230 * s, cornerHeight: 230 * s, transform: nil)
    context.addPath(bgPath)
    context.clip()

    let colors = [
        CGColor(red: 0.13, green: 0.17, blue: 0.26, alpha: 1),  // top: deep slate blue
        CGColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1),  // bottom: near-black navy
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 512 * s, y: 1024 * s),
        end: CGPoint(x: 512 * s, y: 0),
        options: []
    )

    // Dock shelf: translucent bar near the bottom.
    let shelf = CGRect(x: 132 * s, y: 148 * s, width: 760 * s, height: 190 * s)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    context.addPath(CGPath(roundedRect: shelf, cornerWidth: 48 * s, cornerHeight: 48 * s, transform: nil))
    context.fillPath()

    // Three app tiles on the shelf; the center one is the "kept" one.
    let tileSize = 132 * s
    let tileY = 177 * s
    let tileColors: [CGColor] = [
        CGColor(red: 0.42, green: 0.50, blue: 0.62, alpha: 1),
        CGColor(red: 0.36, green: 0.78, blue: 0.65, alpha: 1),  // center: teal accent
        CGColor(red: 0.42, green: 0.50, blue: 0.62, alpha: 1),
    ]
    let tileXs: [CGFloat] = [186, 446, 706]
    for (i, x) in tileXs.enumerated() {
        let tile = CGRect(x: x * s, y: tileY, width: tileSize, height: tileSize)
        context.setFillColor(tileColors[i])
        context.addPath(CGPath(roundedRect: tile, cornerWidth: 30 * s, cornerHeight: 30 * s, transform: nil))
        context.fillPath()
    }

    // Padlock above the center tile: shackle + body in warm off-white.
    let lockColor = CGColor(red: 0.96, green: 0.96, blue: 0.93, alpha: 1)
    let bodyW = 300 * s, bodyH = 230 * s
    let bodyX = (1024 * s - bodyW) / 2
    let bodyY = 420 * s
    context.setFillColor(lockColor)
    context.addPath(CGPath(
        roundedRect: CGRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH),
        cornerWidth: 44 * s, cornerHeight: 44 * s, transform: nil
    ))
    context.fillPath()

    // Shackle: thick arc centered over the body.
    context.setStrokeColor(lockColor)
    context.setLineWidth(64 * s)
    context.setLineCap(.round)
    let shackleRadius = 108 * s
    let shackleCenter = CGPoint(x: 512 * s, y: bodyY + bodyH - 6 * s)
    context.addArc(
        center: shackleCenter, radius: shackleRadius,
        startAngle: 0, endAngle: .pi, clockwise: false
    )
    context.strokePath()

    // Keyhole: small dark dot + stem on the body.
    context.setFillColor(CGColor(red: 0.09, green: 0.11, blue: 0.17, alpha: 1))
    let keyR = 34 * s
    context.addEllipse(in: CGRect(x: 512 * s - keyR, y: bodyY + bodyH * 0.48, width: keyR * 2, height: keyR * 2))
    context.fillPath()
    context.addPath(CGPath(
        roundedRect: CGRect(x: 512 * s - 14 * s, y: bodyY + 34 * s, width: 28 * s, height: 90 * s),
        cornerWidth: 14 * s, cornerHeight: 14 * s, transform: nil
    ))
    context.fillPath()
}

func writePNG(size: Int, to url: URL) {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    drawIcon(size: CGFloat(size), into: ctx)
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let root = scriptDir.deletingLastPathComponent()
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in entries {
    writePNG(size: size, to: iconset.appendingPathComponent("\(name).png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "AppIcon.icns written" : "iconutil failed (\(task.terminationStatus))")
