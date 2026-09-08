import AppKit

// Run from the repository root: swift Scripts/render-app-icon.swift
// Rasterize the shared vector mark into the app icon's required pixel sizes.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Sonexis/Assets.xcassets")
let svg = try String(contentsOf: assets.appendingPathComponent("SonexisMark.imageset/mark.svg"), encoding: .utf8)
let pathExpression = try NSRegularExpression(pattern: " d=\"([^\"]+)\"")
let match = pathExpression.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg))!
let pathData = String(svg[Range(match.range(at: 1), in: svg)!])
let tokenExpression = try NSRegularExpression(pattern: "[A-Za-z]|-?[0-9]+(?:\\.[0-9]+)?")
let tokens = tokenExpression.matches(in: pathData, range: NSRange(pathData.startIndex..., in: pathData))
    .map { String(pathData[Range($0.range, in: pathData)!]) }
let mark = NSBezierPath()
var index = 0
func point() -> NSPoint {
    defer { index += 2 }
    return NSPoint(x: Double(tokens[index])!, y: Double(tokens[index + 1])!)
}
while index < tokens.count {
    let command = tokens[index]
    index += 1
    switch command {
    case "M": mark.move(to: point())
    case "L": mark.line(to: point())
    case "C":
        let first = point(), second = point(), end = point()
        mark.curve(to: end, controlPoint1: first, controlPoint2: second)
    case "Z": mark.close()
    default: fatalError("Unsupported SVG command: \(command)")
    }
}
let directory = assets.appendingPathComponent("AppIcon.appiconset")
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("Contents.json"))) as! [String: Any]
for entry in manifest["images"] as! [[String: String]] {
    let base = Int(entry["size"]!.split(separator: "x")[0])!
    let pixels = base * (entry["scale"] == "2x" ? 2 : 1)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(pixels) / 1024)
    scale.concat()
    // A dark rounded tile with transparent outer margins, matching macOS icon spacing.
    let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190)
    NSColor(calibratedRed: 0.035, green: 0.035, blue: 0.06, alpha: 1).setFill()
    tile.fill()
    let transform = NSAffineTransform()
    transform.translateX(by: 128, yBy: 896)
    transform.scaleX(by: 32, yBy: -32)
    transform.concat()
    NSColor(srgbRed: 1, green: 45.0 / 255, blue: 149.0 / 255, alpha: 1).setFill()
    mark.fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(entry["filename"]!))
}
print("Rendered all AppIcon sizes from SonexisMark")

// Keep a normal image asset for the running Dock icon, outside AppIcon processing.
let dockDirectory = assets.appendingPathComponent("DockMark.imageset")
try FileManager.default.createDirectory(at: dockDirectory, withIntermediateDirectories: true)
let dockPNG = try Data(contentsOf: directory.appendingPathComponent("icon_512x512@2x.png"))
try dockPNG.write(to: dockDirectory.appendingPathComponent("dock.png"))
