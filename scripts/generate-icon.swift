import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("FrankEnergyIcon.iconset", isDirectory: true)
let output = resources.appendingPathComponent("FrankEnergyIcon.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(name: String, points: Int, scale: Int)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 512, 2)
]

func drawIcon(pixelSize: Int) -> NSImage {
    let size = NSSize(width: pixelSize, height: pixelSize)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()

    let inset = CGFloat(pixelSize) * 0.08
    let rect = NSRect(x: inset, y: inset, width: CGFloat(pixelSize) - inset * 2, height: CGFloat(pixelSize) - inset * 2)
    let radius = CGFloat(pixelSize) * 0.19
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.0, green: 0.72, blue: 0.34, alpha: 1).setFill()
    path.fill()

    NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
    path.lineWidth = max(CGFloat(pixelSize) * 0.012, 1)
    path.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let frankFont = NSFont.systemFont(ofSize: CGFloat(pixelSize) * 0.22, weight: .black)
    let energyFont = NSFont.systemFont(ofSize: CGFloat(pixelSize) * 0.125, weight: .bold)
    let textColor = NSColor.white

    let frank = NSAttributedString(
        string: "frank",
        attributes: [.font: frankFont, .foregroundColor: textColor, .paragraphStyle: paragraph]
    )
    let energie = NSAttributedString(
        string: "energie",
        attributes: [.font: energyFont, .foregroundColor: textColor, .paragraphStyle: paragraph]
    )

    let frankHeight = frank.size().height
    let energyHeight = energie.size().height
    let totalHeight = frankHeight + energyHeight * 0.95
    let topY = rect.midY + totalHeight / 2 - frankHeight

    frank.draw(in: NSRect(x: rect.minX, y: topY, width: rect.width, height: frankHeight * 1.15))
    energie.draw(in: NSRect(x: rect.minX, y: topY - energyHeight * 0.88, width: rect.width, height: energyHeight * 1.2))

    return image
}

for item in sizes {
    let pixels = item.points * item.scale
    let image = drawIcon(pixelSize: pixels)
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        fatalError("Kon icon PNG niet maken voor \(item.name)")
    }

    try png.write(to: iconset.appendingPathComponent(item.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fatalError("iconutil faalde met status \(process.terminationStatus)")
}

try? FileManager.default.removeItem(at: iconset)
