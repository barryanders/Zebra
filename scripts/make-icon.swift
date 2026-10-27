import AppKit
import Foundation
let target = CommandLine.arguments[1]
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("daylight-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let dimension = CGFloat(pixels)
        let inset = dimension * 0.07
        let rect = NSRect(x: inset, y: inset, width: dimension - inset * 2, height: dimension - inset * 2)
        NSColor(calibratedRed: 0.91, green: 0.90, blue: 0.86, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: dimension * 0.19, yRadius: dimension * 0.19).fill()
        if let symbol = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: dimension * 0.48, weight: .light)) {
            let tinted = symbol.withSymbolConfiguration(.init(paletteColors: [NSColor(calibratedRed: 0.27, green: 0.40, blue: 0.49, alpha: 1)])) ?? symbol
            tinted.draw(in: NSRect(x: dimension * 0.25, y: dimension * 0.25, width: dimension * 0.5, height: dimension * 0.5))
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = bitmap.representation(using: .png, properties: [:])!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: folder.appendingPathComponent(name))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", folder.path, "-o", target]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 { exit(process.terminationStatus) }
