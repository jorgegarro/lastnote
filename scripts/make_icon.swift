// Draws the LastNote app icon ("Cursor Monogram"): a bold "L" followed by a glowing text caret on
// deep charcoal, with a strip of coloured tabs (the per-tab tints) along the bottom.
// Usage: swift scripts/make_icon.swift out.png   (scripts/make_icns.sh builds the .icns from it)
// Other explored designs live in scripts/icon-options/.
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func hex(_ s: String, _ a: CGFloat = 1) -> CGColor {
    let v = UInt32(s.dropFirst(), radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
func rr(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }
func gradient(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locs)! }

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// Work in top-left coordinates.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// macOS icon grid: 824pt rounded square with a soft drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyRadius: CGFloat = 185
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: hex("#000000", 0.35))
ctx.addPath(rr(body, bodyRadius)); ctx.setFillColor(hex("#000000")); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(rr(body, bodyRadius)); ctx.clip()
// Charcoal background with a faint blue glow behind the letter.
ctx.drawLinearGradient(gradient([hex("#23262F"), hex("#0D0F14")], [0, 1]), start: CGPoint(x: 200, y: 100), end: CGPoint(x: 824, y: 924), options: [])
ctx.drawRadialGradient(gradient([hex("#5B8CFF", 0.28), hex("#5B8CFF", 0)], [0, 1]),
                       startCenter: CGPoint(x: 512, y: 430), startRadius: 0, endCenter: CGPoint(x: 512, y: 430), endRadius: 460, options: [])
// The "L".
ctx.setFillColor(hex("#F5F7FB"))
ctx.addPath(rr(CGRect(x: 330, y: 230, width: 110, height: 460), 30)); ctx.fillPath()
ctx.addPath(rr(CGRect(x: 330, y: 600, width: 300, height: 90), 30)); ctx.fillPath()
// The glowing caret.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 30, color: hex("#5B8CFF", 0.9))
ctx.addPath(rr(CGRect(x: 666, y: 330, width: 38, height: 360), 19)); ctx.setFillColor(hex("#6FA0FF")); ctx.fillPath()
ctx.restoreGState()
// Coloured tabs.
let colours = ["#E5484D", "#F5A524", "#30A46C", "#3E63DD", "#8E4EC6"]
let tabW: CGFloat = 118, gap: CGFloat = 14
let startX = 512 - (CGFloat(colours.count) * tabW + CGFloat(colours.count - 1) * gap) / 2
for (i, c) in colours.enumerated() {
    ctx.addPath(rr(CGRect(x: startX + CGFloat(i) * (tabW + gap), y: 780, width: tabW, height: 40), 20))
    ctx.setFillColor(hex(c)); ctx.fillPath()
}
ctx.restoreGState()

// Subtle rim highlight.
ctx.addPath(rr(body.insetBy(dx: 2, dy: 2), bodyRadius - 2)); ctx.setStrokeColor(hex("#FFFFFF", 0.16)); ctx.setLineWidth(4); ctx.strokePath()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
