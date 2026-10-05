import AppKit

// A dot's glyph for the site (site/icons/<name>.png): the app's SF Symbol (Dot.symbol) in its tint,
// medium weight, 144×144, scaled so its longer side is 110 px, like the others.
// Usage: swift marketing/icons/render-icon.swift <symbol> <hex tint> <out.png>
//   e.g. swift marketing/icons/render-icon.swift camera.viewfinder FF2D55 site/icons/screenshot.png
let args = CommandLine.arguments
guard args.count == 4, let hex = UInt32(args[2], radix: 16) else {
    print("usage: render-icon.swift <symbol> <hex tint> <out.png>")
    exit(1)
}
let color = NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
let side = 144, target: CGFloat = 110

func render(pointSize: CGFloat) -> (NSBitmapImageRep, CGFloat) {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    let image = NSImage(systemSymbolName: args[1], accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = image.size
    image.draw(in: NSRect(x: (CGFloat(side) - size.width) / 2, y: (CGFloat(side) - size.height) / 2,
                          width: size.width, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    // The ink's longer side.
    var minX = side, minY = side, maxX = 0, maxY = 0
    for y in 0..<side { for x in 0..<side where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    return (rep, CGFloat(max(maxX - minX, maxY - minY) + 1))
}

// Measure at 100 pt, then draw at the size that makes the longer side 110 px.
let (_, measured) = render(pointSize: 100)
let (rep, longest) = render(pointSize: 100 * target / measured)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
print("\(args[3]): \(args[1]), longer side \(Int(longest)) px")
