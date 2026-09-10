import AppKit

let width = 1440
let height = 880
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(colors: [
    NSColor(calibratedRed: 0.985, green: 0.975, blue: 0.995, alpha: 1),
    NSColor(calibratedRed: 0.945, green: 0.920, blue: 0.965, alpha: 1)
])!.draw(in: canvas, angle: -90)

let wave = NSBezierPath()
wave.move(to: NSPoint(x: 570, y: 420))
wave.curve(to: NSPoint(x: 870, y: 420),
           controlPoint1: NSPoint(x: 660, y: 470),
           controlPoint2: NSPoint(x: 780, y: 370))
wave.lineWidth = 7
wave.lineCapStyle = .round
NSColor(calibratedRed: 0.93, green: 0.16, blue: 0.43, alpha: 1).setStroke()
wave.stroke()

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 870, y: 420))
arrow.line(to: NSPoint(x: 838, y: 438))
arrow.move(to: NSPoint(x: 870, y: 420))
arrow.line(to: NSPoint(x: 850, y: 389))
arrow.lineWidth = 7
arrow.lineCapStyle = .round
arrow.stroke()

let titleStyle: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 46, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.13, green: 0.10, blue: 0.16, alpha: 1),
    .kern: -0.6
]
let title = NSAttributedString(string: "Drag Sonexis to Applications", attributes: titleStyle)
title.draw(at: NSPoint(x: (CGFloat(width) - title.size().width) / 2, y: 720))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render background")
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
