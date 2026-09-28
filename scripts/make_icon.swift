// Draws the LastNote app icon. Usage: swift scripts/make_icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// Work in top-left coordinates.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func hex(_ s: String, _ a: CGFloat = 1) -> CGColor {
    let v = UInt32(s.dropFirst(), radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }
func topRounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.minX, y: r.maxY))
    p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + radius, y: r.minY), radius: radius)
    p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + radius), radius: radius)
    p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
    p.closeSubpath()
    return p
}

// Body: macOS icon grid, 824pt squircle-ish rounded square with a deep glassy gradient.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: hex("#000000", 0.35))
ctx.addPath(rounded(body, 185)); ctx.setFillColor(hex("#1B1F27")); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(rounded(body, 185)); ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [hex("#4B3FA8"), hex("#243B7A"), hex("#10131C")] as CFArray, locations: [0, 0.45, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 200, y: 100), end: CGPoint(x: 820, y: 924), options: [])
// Soft glass sheen across the top.
let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [hex("#FFFFFF", 0.22), hex("#FFFFFF", 0)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 470), options: [])
ctx.restoreGState()
ctx.addPath(rounded(body.insetBy(dx: 2, dy: 2), 183)); ctx.setStrokeColor(hex("#FFFFFF", 0.14)); ctx.setLineWidth(4); ctx.strokePath()

// Coloured tabs (the per-tab tints), active one first and merged with the page.
let tabs: [(CGFloat, String, CGFloat)] = [(232, "#E5484D", 205), (402, "#30A46C", 222), (572, "#3E63DD", 222)]
for (x, color, top) in tabs.reversed() {
    ctx.addPath(topRounded(CGRect(x: x, y: top, width: 158, height: 290 - top), 22))
    ctx.setFillColor(hex(color)); ctx.fillPath()
}

// The note page.
let page = CGRect(x: 212, y: 262, width: 600, height: 372)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: hex("#000000", 0.35))
ctx.addPath(rounded(page, 34)); ctx.setFillColor(hex("#F5F7FC")); ctx.fillPath()
ctx.restoreGState()
// Active-tab accent along the top of the page.
ctx.saveGState(); ctx.addPath(rounded(page, 34)); ctx.clip()
ctx.setFillColor(hex("#E5484D")); ctx.fill(CGRect(x: page.minX, y: page.minY, width: page.width, height: 14))
ctx.restoreGState()
// Syntax-coloured "code" lines with a line-number gutter.
let rows: [[(CGFloat, CGFloat, String)]] = [
    [(0, 110, "#3E63DD"), (126, 190, "#8B93A7")],
    [(44, 130, "#D6409F"), (190, 150, "#8B93A7")],
    [(44, 250, "#30A46C")],
    [(0, 96, "#3E63DD"), (112, 120, "#E5A000"), (248, 90, "#8B93A7")],
]
for (i, row) in rows.enumerated() {
    let y = page.minY + 62 + CGFloat(i) * 70
    ctx.setFillColor(hex("#C3C9D6")); ctx.addPath(rounded(CGRect(x: page.minX + 36, y: y, width: 26, height: 24), 8)); ctx.fillPath()
    for (dx, w, color) in row {
        ctx.setFillColor(hex(color)); ctx.addPath(rounded(CGRect(x: page.minX + 96 + dx, y: y, width: w, height: 24), 12)); ctx.fillPath()
    }
}

// Console strip with a prompt.
let consoleRect = CGRect(x: 212, y: 662, width: 600, height: 170)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: hex("#000000", 0.4))
ctx.addPath(rounded(consoleRect, 34)); ctx.setFillColor(hex("#0B0F17", 0.92)); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(rounded(consoleRect.insetBy(dx: 1.5, dy: 1.5), 33)); ctx.setStrokeColor(hex("#FFFFFF", 0.12)); ctx.setLineWidth(3); ctx.strokePath()
// ">" chevron
let chevron = CGMutablePath()
let cx = consoleRect.minX + 60, cy = consoleRect.midY
chevron.move(to: CGPoint(x: cx, y: cy - 34)); chevron.addLine(to: CGPoint(x: cx + 40, y: cy)); chevron.addLine(to: CGPoint(x: cx, y: cy + 34))
ctx.addPath(chevron); ctx.setStrokeColor(hex("#3FD17A")); ctx.setLineWidth(20); ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath()
// "_" cursor
ctx.setFillColor(hex("#3FD17A")); ctx.addPath(rounded(CGRect(x: cx + 76, y: cy + 22, width: 86, height: 20), 10)); ctx.fillPath()
// Faint output text
ctx.setFillColor(hex("#FFFFFF", 0.28)); ctx.addPath(rounded(CGRect(x: cx + 200, y: cy - 8, width: 250, height: 18), 9)); ctx.fillPath()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
