import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift Support/GenerateIcon.swift <output.iconset>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fileManager = FileManager.default

try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for size in sizes {
    let image = NSImage(size: NSSize(width: size.pixels, height: size.pixels))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size.pixels, height: size.pixels)
    let scale = CGFloat(size.pixels) / 1024.0

    NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.15, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 210 * scale, yRadius: 210 * scale).fill()

    let box = NSRect(x: 190 * scale, y: 220 * scale, width: 644 * scale, height: 430 * scale)
    NSColor(calibratedRed: 0.88, green: 0.94, blue: 1.00, alpha: 1).setFill()
    NSBezierPath(roundedRect: box, xRadius: 70 * scale, yRadius: 70 * scale).fill()

    NSColor(calibratedRed: 0.33, green: 0.54, blue: 0.75, alpha: 1).setFill()
    let tray = NSBezierPath()
    tray.move(to: NSPoint(x: 220 * scale, y: 445 * scale))
    tray.line(to: NSPoint(x: 390 * scale, y: 445 * scale))
    tray.line(to: NSPoint(x: 442 * scale, y: 375 * scale))
    tray.line(to: NSPoint(x: 582 * scale, y: 375 * scale))
    tray.line(to: NSPoint(x: 634 * scale, y: 445 * scale))
    tray.line(to: NSPoint(x: 804 * scale, y: 445 * scale))
    tray.line(to: NSPoint(x: 804 * scale, y: 280 * scale))
    tray.line(to: NSPoint(x: 220 * scale, y: 280 * scale))
    tray.close()
    tray.fill()

    NSColor(calibratedRed: 0.98, green: 0.99, blue: 1.00, alpha: 1).setFill()
    let key = NSBezierPath(roundedRect: NSRect(x: 300 * scale, y: 625 * scale, width: 424 * scale, height: 190 * scale), xRadius: 55 * scale, yRadius: 55 * scale)
    key.fill()

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 108 * scale, weight: .semibold),
        .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.15, alpha: 1)
    ]
    let text = "Del ⌫" as NSString
    let textSize = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(x: rect.midX - textSize.width / 2, y: (715 * scale) - textSize.height / 2),
        withAttributes: attributes
    )

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("failed to render \(size.name)\n", stderr)
        exit(1)
    }

    try png.write(to: outputURL.appendingPathComponent(size.name))
}
