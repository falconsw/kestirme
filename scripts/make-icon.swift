// Draws the Kestirme app icon (1024 px) to the path given as the first argument.
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Body (macOS icon grid: 824 px squircle centred, drop shadow below).
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
color(0x3A2BD8).setFill()
bodyPath.fill()
ctx.restoreGState()

ctx.saveGState()
bodyPath.addClip()
NSGradient(colors: [color(0x7B6CFF), color(0x4B36F0), color(0x2A1A9E)], atLocations: [0, 0.5, 1],
           colorSpace: .sRGB)!.draw(in: body, angle: -90)
// Soft glow top-left
let glow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
glow.draw(fromCenter: NSPoint(x: 330, y: 860), radius: 0, toCenter: NSPoint(x: 330, y: 860), radius: 620, options: [])
// Faint keyboard rows in the background
for (row, y) in [250, 175].enumerated() {
    let count = 7 - row
    let w: CGFloat = 92, gap: CGFloat = 16
    let total = CGFloat(count) * w + CGFloat(count - 1) * gap
    for i in 0..<count {
        let r = NSRect(x: 512 - total / 2 + CGFloat(i) * (w + gap), y: CGFloat(y), width: w, height: 58)
        NSColor.white.withAlphaComponent(0.07).setFill()
        NSBezierPath(roundedRect: r, xRadius: 16, yRadius: 16).fill()
    }
}
ctx.restoreGState()

// The key
let key = NSRect(x: 512 - 250, y: 380, width: 500, height: 470)
let depth: CGFloat = 34
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 50, color: NSColor.black.withAlphaComponent(0.45).cgColor)
color(0xBDB6F7).setFill()
NSBezierPath(roundedRect: key.offsetBy(dx: 0, dy: -depth), xRadius: 96, yRadius: 96).fill()
ctx.restoreGState()
color(0xA9A0F2).setFill()
NSBezierPath(roundedRect: key.offsetBy(dx: 0, dy: -depth), xRadius: 96, yRadius: 96).fill()
let top = NSBezierPath(roundedRect: key, xRadius: 96, yRadius: 96)
NSGradient(colors: [color(0xFFFFFF), color(0xEEEBFF)])!.draw(in: top, angle: -90)
color(0xFFFFFF, 0.9).setStroke()
top.lineWidth = 3
top.stroke()

// ⌘ glyph
let font = NSFont.systemFont(ofSize: 330, weight: .semibold)
let para = NSMutableParagraphStyle()
para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color(0x3F2EE0), .paragraphStyle: para]
let glyph = NSAttributedString(string: "⌘", attributes: attrs)
let gs = glyph.size()
glyph.draw(in: NSRect(x: key.midX - gs.width / 2, y: key.midY - gs.height / 2 + 6, width: gs.width, height: gs.height))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
