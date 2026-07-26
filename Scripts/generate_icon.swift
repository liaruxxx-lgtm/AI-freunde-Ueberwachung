#!/usr/bin/env swift

import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "/tmp/Freundeblick-AppIcon.png"
let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Icon bitmap could not be created")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
defer { NSGraphicsContext.restoreGraphicsState() }

let canvas = NSRect(x: 46, y: 46, width: 932, height: 932)
let background = NSBezierPath(roundedRect: canvas, xRadius: 220, yRadius: 220)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.27, green: 0.10, blue: 0.36, alpha: 1),
    NSColor(calibratedRed: 0.73, green: 0.18, blue: 0.39, alpha: 1),
    NSColor(calibratedRed: 0.97, green: 0.42, blue: 0.31, alpha: 1)
])!
gradient.draw(in: background, angle: -42)

NSColor.white.withAlphaComponent(0.10).setFill()
NSBezierPath(ovalIn: NSRect(x: 542, y: 420, width: 390, height: 390)).fill()

let connection = NSBezierPath()
connection.move(to: NSPoint(x: 330, y: 486))
connection.line(to: NSPoint(x: 512, y: 630))
connection.line(to: NSPoint(x: 706, y: 494))
connection.lineWidth = 28
connection.lineCapStyle = .round
connection.lineJoinStyle = .round
NSColor.white.withAlphaComponent(0.22).setStroke()
connection.stroke()

func drawPerson(centerX: CGFloat, headY: CGFloat, scale: CGFloat, alpha: CGFloat) {
    let headRadius = 82 * scale
    let headRect = NSRect(
        x: centerX - headRadius,
        y: headY - headRadius,
        width: headRadius * 2,
        height: headRadius * 2
    )
    NSColor.white.withAlphaComponent(alpha).setFill()
    NSBezierPath(ovalIn: headRect).fill()

    let bodyWidth = 250 * scale
    let bodyHeight = 170 * scale
    let body = NSBezierPath(
        roundedRect: NSRect(
            x: centerX - bodyWidth / 2,
            y: headY - headRadius - bodyHeight - 44 * scale,
            width: bodyWidth,
            height: bodyHeight
        ),
        xRadius: bodyHeight / 2,
        yRadius: bodyHeight / 2
    )
    body.fill()
}

drawPerson(centerX: 304, headY: 542, scale: 0.72, alpha: 0.58)
drawPerson(centerX: 720, headY: 542, scale: 0.72, alpha: 0.58)
drawPerson(centerX: 512, headY: 650, scale: 1.00, alpha: 0.96)

let sparkle = NSBezierPath()
sparkle.move(to: NSPoint(x: 790, y: 796))
sparkle.curve(
    to: NSPoint(x: 858, y: 864),
    controlPoint1: NSPoint(x: 832, y: 804),
    controlPoint2: NSPoint(x: 850, y: 822)
)
sparkle.curve(
    to: NSPoint(x: 926, y: 796),
    controlPoint1: NSPoint(x: 866, y: 822),
    controlPoint2: NSPoint(x: 884, y: 804)
)
sparkle.curve(
    to: NSPoint(x: 858, y: 728),
    controlPoint1: NSPoint(x: 884, y: 788),
    controlPoint2: NSPoint(x: 866, y: 770)
)
sparkle.curve(
    to: NSPoint(x: 790, y: 796),
    controlPoint1: NSPoint(x: 850, y: 770),
    controlPoint2: NSPoint(x: 832, y: 788)
)
sparkle.close()
NSColor(calibratedRed: 1, green: 0.82, blue: 0.48, alpha: 1).setFill()
sparkle.fill()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Icon PNG could not be encoded")
}
try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
