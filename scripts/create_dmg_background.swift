#!/usr/bin/env swift

import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: create_dmg_background.swift OUTPUT_PATH\n", stderr)
    exit(1)
}

let width = 660
let height = 420

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("Could not create the DMG background bitmap.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let bounds = NSRect(x: 0, y: 0, width: width, height: height)
let gradient = NSGradient(
    starting: NSColor(calibratedWhite: 0.97, alpha: 1),
    ending: NSColor(calibratedWhite: 0.90, alpha: 1)
)
gradient?.draw(in: bounds, angle: -90)

let centered = NSMutableParagraphStyle()
centered.alignment = .center

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1),
    .paragraphStyle: centered,
]

let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15),
    .foregroundColor: NSColor(calibratedWhite: 0.38, alpha: 1),
    .paragraphStyle: centered,
]

("Install OpenShelf" as NSString).draw(
    in: NSRect(x: 0, y: 350, width: width, height: 30),
    withAttributes: titleAttributes
)

("Drag OpenShelf into the Applications folder" as NSString).draw(
    in: NSRect(x: 0, y: 320, width: width, height: 24),
    withAttributes: subtitleAttributes
)

let arrowColor = NSColor(calibratedWhite: 0.35, alpha: 1)
arrowColor.setStroke()
arrowColor.setFill()

let arrow = NSBezierPath()
arrow.lineWidth = 6
arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 260, y: 210))
arrow.curve(
    to: NSPoint(x: 395, y: 210),
    controlPoint1: NSPoint(x: 300, y: 230),
    controlPoint2: NSPoint(x: 355, y: 230)
)
arrow.stroke()

let arrowhead = NSBezierPath()
arrowhead.move(to: NSPoint(x: 410, y: 210))
arrowhead.line(to: NSPoint(x: 390, y: 224))
arrowhead.line(to: NSPoint(x: 390, y: 196))
arrowhead.close()
arrowhead.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode the DMG background as PNG.\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
} catch {
    fputs("Could not write the DMG background: \(error)\n", stderr)
    exit(1)
}
