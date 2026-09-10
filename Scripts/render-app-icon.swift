import AppKit

// Run from the repository root: swift Scripts/render-app-icon.swift
// The website's original favicon is the source of the S, not a substitute font.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let branding = root.appendingPathComponent("Branding")
let assets = root.appendingPathComponent("Sonexis/Assets.xcassets")
let sourceURL = branding.appendingPathComponent("sonexis-original-favicon.png")
let source = NSBitmapImageRep(data: try Data(contentsOf: sourceURL))!
let width = source.pixelsWide, height = source.pixelsHigh

// The pink mark sits over neutral dark scanlines. Red minus green isolates
// the original antialiased silhouette without redrawing its curves.
var coverage = [CGFloat](repeating: 0, count: width * height)
var peak: CGFloat = 0
for y in 0..<height {
    for x in 0..<width {
        let color = source.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        let value = max(0, color.redComponent - color.greenComponent) * color.alphaComponent
        coverage[y * width + x] = value
        peak = max(peak, value)
    }
}
precondition(peak > 0.25, "The source must contain the original pink S")
var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height {
    for x in 0..<width where coverage[y * width + x] / peak > 0.01 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
let markWidth = maxX - minX + 1, markHeight = maxY - minY + 1

func markImage(red: UInt8, green: UInt8, blue: UInt8) -> NSImage {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: markWidth, pixelsHigh: markHeight,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bitmapFormat: .alphaNonpremultiplied, bytesPerRow: 0, bitsPerPixel: 0)!
    let bytes = bitmap.bitmapData!
    for y in 0..<markHeight {
        for x in 0..<markWidth {
            let offset = y * bitmap.bytesPerRow + x * 4
            bytes[offset] = red; bytes[offset + 1] = green; bytes[offset + 2] = blue
            bytes[offset + 3] = UInt8(min(255, (coverage[(y + minY) * width + x + minX] / peak * 255).rounded()))
        }
    }
    return NSImage(cgImage: bitmap.cgImage!, size: NSSize(width: markWidth, height: markHeight))
}

let pinkMark = markImage(red: 255, green: 45, blue: 149) // Solid Sonexis #FF2D95.
let templateMark = markImage(red: 0, green: 0, blue: 0)

func render(pixels: Int, mark: NSImage, tile: Bool, inset: CGFloat, to url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()
    if tile {
        NSColor(srgbRed: 0.035, green: 0.035, blue: 0.06, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864),
                     xRadius: 190, yRadius: 190).fill()
    }
    let scale = (1024 - inset * 2) / max(mark.size.width, mark.size.height)
    let size = NSSize(width: mark.size.width * scale, height: mark.size.height * scale)
    mark.draw(in: NSRect(x: (1024 - size.width) / 2, y: (1024 - size.height) / 2,
                        width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url, options: .atomic)
}

try render(pixels: 1024, mark: pinkMark, tile: false, inset: 48,
           to: branding.appendingPathComponent("sonexis-mark.png"))
let markDirectory = assets.appendingPathComponent("SonexisMark.imageset")
for scale in 1...3 {
    try render(pixels: 24 * scale, mark: templateMark, tile: false, inset: 32,
               to: markDirectory.appendingPathComponent("mark@\(scale)x.png"))
}
let iconDirectory = assets.appendingPathComponent("AppIcon.appiconset")
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: iconDirectory.appendingPathComponent("Contents.json"))) as! [String: Any]
for entry in manifest["images"] as! [[String: String]] {
    let base = Int(entry["size"]!.split(separator: "x")[0])!
    let pixels = base * (entry["scale"] == "2x" ? 2 : 1)
    try render(pixels: pixels, mark: pinkMark, tile: true, inset: 176,
               to: iconDirectory.appendingPathComponent(entry["filename"]!))
}
try Data(contentsOf: iconDirectory.appendingPathComponent("icon_512x512@2x.png"))
    .write(to: assets.appendingPathComponent("DockMark.imageset/dock.png"), options: .atomic)
print("Rendered original favicon S into AppIcon, DockMark, SonexisMark, and Branding/sonexis-mark.png")
