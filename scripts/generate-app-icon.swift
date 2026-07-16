#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let iconRootURL = rootURL.appendingPathComponent("Packaging/AppIcon", isDirectory: true)
let iconsetURL = iconRootURL.appendingPathComponent("AgentUsageMonitor.iconset", isDirectory: true)
let icnsURL = iconRootURL.appendingPathComponent("AgentUsageMonitor.icns")

try fileManager.createDirectory(at: iconRootURL, withIntermediateDirectories: true)
if fileManager.fileExists(atPath: iconsetURL.path) {
    try fileManager.removeItem(at: iconsetURL)
}
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

struct IconColor {
    static let backgroundTop = NSColor(red: 0.175, green: 0.155, blue: 0.135, alpha: 1.0)
    static let backgroundBottom = NSColor(red: 0.325, green: 0.235, blue: 0.170, alpha: 1.0)
    static let track = NSColor(red: 0.920, green: 0.855, blue: 0.725, alpha: 0.24)
    static let meter = NSColor(red: 0.835, green: 0.585, blue: 0.335, alpha: 1.0)
    static let meterHighlight = NSColor(red: 0.965, green: 0.760, blue: 0.465, alpha: 1.0)
    static let mark = NSColor(red: 0.985, green: 0.960, blue: 0.910, alpha: 1.0)
    static let markSecondary = NSColor(red: 0.820, green: 0.760, blue: 0.650, alpha: 1.0)
}

let iconFiles: [(pixels: Int, name: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for iconFile in iconFiles {
    let image = makeIcon(size: iconFile.pixels)
    try writePNG(image, to: iconsetURL.appendingPathComponent(iconFile.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw NSError(
        domain: "AgentUsageMonitor.Icon",
        code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: "iconutil failed to create \(icnsURL.path)"]
    )
}

print("Generated \(icnsURL.path)")

func makeIcon(size pixels: Int) -> NSImage {
    let scale = CGFloat(pixels) / 1024.0
    let image = NSImage(size: NSSize(width: pixels, height: pixels))

    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else {
        return image
    }

    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))

    drawBase(in: context, scale: scale)
    drawMeter(in: context, scale: scale)
    drawHub(in: context, scale: scale)

    return image
}

func drawBase(in context: CGContext, scale: CGFloat) {
    let rect = CGRect(x: 86 * scale, y: 86 * scale, width: 852 * scale, height: 852 * scale)
    let radius = 214 * scale
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18 * scale), blur: 36 * scale, color: NSColor.black.withAlphaComponent(0.24).cgColor)
    context.addPath(path)
    context.clip()

    let colors = [IconColor.backgroundTop.cgColor, IconColor.backgroundBottom.cgColor] as CFArray
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 512 * scale, y: 938 * scale),
        end: CGPoint(x: 512 * scale, y: 86 * scale),
        options: []
    )
    context.restoreGState()

    context.saveGState()
    context.addPath(path)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
    context.setLineWidth(2 * scale)
    context.strokePath()
    context.restoreGState()
}

func drawMeter(in context: CGContext, scale: CGFloat) {
    let center = CGPoint(x: 512 * scale, y: 512 * scale)
    let radius = 304 * scale
    let width = max(2, 74 * scale)

    context.saveGState()
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setStrokeColor(IconColor.track.cgColor)
    context.addArc(center: center, radius: radius, startAngle: radians(132), endAngle: radians(408), clockwise: false)
    context.strokePath()

    context.setStrokeColor(IconColor.meter.cgColor)
    context.addArc(center: center, radius: radius, startAngle: radians(132), endAngle: radians(340), clockwise: false)
    context.strokePath()

    context.setStrokeColor(IconColor.meterHighlight.cgColor)
    context.setLineWidth(max(1, 18 * scale))
    context.addArc(center: center, radius: radius + 29 * scale, startAngle: radians(132), endAngle: radians(216), clockwise: false)
    context.strokePath()
    context.restoreGState()
}

func drawHub(in context: CGContext, scale: CGFloat) {
    let center = CGPoint(x: 512 * scale, y: 512 * scale)
    let nodes = [
        CGPoint(x: 512 * scale, y: 655 * scale),
        CGPoint(x: 384 * scale, y: 438 * scale),
        CGPoint(x: 640 * scale, y: 438 * scale)
    ]

    context.saveGState()
    context.setLineWidth(max(1, 17 * scale))
    context.setLineCap(.round)
    context.setStrokeColor(IconColor.markSecondary.withAlphaComponent(0.76).cgColor)
    for node in nodes {
        context.move(to: center)
        context.addLine(to: node)
        context.strokePath()
    }
    context.restoreGState()

    drawCircle(center: center, radius: 54 * scale, color: IconColor.mark, in: context)
    drawCircle(center: nodes[0], radius: 41 * scale, color: IconColor.mark, in: context)
    drawCircle(center: nodes[1], radius: 38 * scale, color: IconColor.mark, in: context)
    drawCircle(center: nodes[2], radius: 38 * scale, color: IconColor.mark, in: context)

    drawCircle(center: CGPoint(x: 512 * scale, y: 512 * scale), radius: 18 * scale, color: IconColor.meter, in: context)
}

func drawCircle(center: CGPoint, radius: CGFloat, color: NSColor, in context: CGContext) {
    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    context.saveGState()
    context.setFillColor(color.cgColor)
    context.fillEllipse(in: rect)
    context.restoreGState()
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(
            domain: "AgentUsageMonitor.Icon",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to render \(url.lastPathComponent)"]
        )
    }

    try pngData.write(to: url)
}

func radians(_ degrees: CGFloat) -> CGFloat {
    degrees * .pi / 180
}
