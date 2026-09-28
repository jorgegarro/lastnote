// Draws three candidate LastNote icons. Usage: swift options.swift <outdir>
import AppKit

let size: CGFloat = 1024
let outDir = CommandLine.arguments.dropFirst().first ?? "."
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func hex(_ s: String, _ a: CGFloat = 1) -> CGColor {
    let v = UInt32(s.dropFirst(), radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
func rr(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }
func gradient(_ colors: [CGColor], _ locs: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locs)! }

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyRadius: CGFloat = 185

/// Render one icon; drawing uses top-left coordinates.
func render(_ name: String, _ draw: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    // Shared: drop shadow + squircle clip.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: hex("#000000", 0.35))
    ctx.addPath(rr(body, bodyRadius)); ctx.setFillColor(hex("#000000")); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(rr(body, bodyRadius)); ctx.clip()
    draw(ctx)
    ctx.restoreGState()
    ctx.addPath(rr(body.insetBy(dx: 2, dy: 2), bodyRadius - 2)); ctx.setStrokeColor(hex("#FFFFFF", 0.16)); ctx.setLineWidth(4); ctx.strokePath()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}

func text(_ ctx: CGContext, _ s: String, font: NSFont, color: CGColor, at p: CGPoint) {
    // Text in a flipped context: flip locally around the baseline.
    let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!])
    let line = CTLineCreateWithAttributedString(attr)
    ctx.saveGState()
    ctx.translateBy(x: p.x, y: p.y)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// ── Option A: "Aurora Glass" — a frosted glass pane over an aurora, echoing the tinted,
// see-through window. Faint text lines and a prompt etched into the glass.
render("A-aurora-glass") { ctx in
    ctx.drawLinearGradient(gradient([hex("#12C2E9"), hex("#6A5AE0"), hex("#F64F9A"), hex("#FF9A5A")], [0, 0.4, 0.75, 1]),
                           start: CGPoint(x: 100, y: 120), end: CGPoint(x: 924, y: 924), options: [])
    // Soft light blobs for depth.
    ctx.drawRadialGradient(gradient([hex("#FFFFFF", 0.45), hex("#FFFFFF", 0)], [0, 1]),
                           startCenter: CGPoint(x: 300, y: 250), startRadius: 0, endCenter: CGPoint(x: 300, y: 250), endRadius: 420, options: [])
    // Glass pane.
    let pane = CGRect(x: 214, y: 214, width: 596, height: 596)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: hex("#1A0B3D", 0.35))
    ctx.addPath(rr(pane, 90)); ctx.setFillColor(hex("#FFFFFF", 0.22)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(rr(pane, 90)); ctx.clip()
    ctx.drawLinearGradient(gradient([hex("#FFFFFF", 0.35), hex("#FFFFFF", 0.05)], [0, 1]),
                           start: CGPoint(x: pane.minX, y: pane.minY), end: CGPoint(x: pane.maxX, y: pane.maxY), options: [])
    ctx.restoreGState()
    ctx.addPath(rr(pane.insetBy(dx: 2, dy: 2), 88)); ctx.setStrokeColor(hex("#FFFFFF", 0.7)); ctx.setLineWidth(5); ctx.strokePath()
    // Text lines.
    let widths: [CGFloat] = [330, 400, 260, 360]
    for (i, w) in widths.enumerated() {
        ctx.addPath(rr(CGRect(x: pane.minX + 80, y: pane.minY + 110 + CGFloat(i) * 72, width: w, height: 26), 13))
        ctx.setFillColor(hex("#FFFFFF", 0.85)); ctx.fillPath()
    }
    // Prompt.
    text(ctx, ">_", font: .monospacedSystemFont(ofSize: 150, weight: .heavy), color: hex("#FFFFFF"), at: CGPoint(x: pane.minX + 70, y: pane.maxY - 60))
}

// ── Option B: "Legal Pad" — the classic yellow notepad (Notepad++'s spirit), spiral-bound, with
// a green terminal prompt scribbled at the bottom.
render("B-legal-pad") { ctx in
    ctx.drawLinearGradient(gradient([hex("#2B3445"), hex("#141923")], [0, 1]), start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    let pad = CGRect(x: 232, y: 196, width: 560, height: 660)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 16), blur: 30, color: hex("#000000", 0.5))
    ctx.addPath(rr(pad, 34)); ctx.setFillColor(hex("#FFE27A")); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(rr(pad, 34)); ctx.clip()
    ctx.drawLinearGradient(gradient([hex("#FFEFA8"), hex("#FFD84D")], [0, 1]), start: CGPoint(x: 0, y: pad.minY), end: CGPoint(x: 0, y: pad.maxY), options: [])
    // Ruled lines + red margin.
    ctx.setStrokeColor(hex("#6FA8DC", 0.8)); ctx.setLineWidth(5)
    var y = pad.minY + 150
    while y < pad.maxY - 30 { ctx.move(to: CGPoint(x: pad.minX, y: y)); ctx.addLine(to: CGPoint(x: pad.maxX, y: y)); y += 62 }
    ctx.strokePath()
    ctx.setStrokeColor(hex("#E5484D", 0.85)); ctx.setLineWidth(6)
    ctx.move(to: CGPoint(x: pad.minX + 96, y: pad.minY)); ctx.addLine(to: CGPoint(x: pad.minX + 96, y: pad.maxY)); ctx.strokePath()
    ctx.restoreGState()
    // Binding strip + spiral rings.
    ctx.addPath(rr(CGRect(x: pad.minX, y: pad.minY, width: pad.width, height: 70), 34)); ctx.setFillColor(hex("#3A4254")); ctx.fillPath()
    ctx.fill(CGRect(x: pad.minX, y: pad.minY + 36, width: pad.width, height: 34))
    for i in 0..<7 {
        let x = pad.minX + 62 + CGFloat(i) * 73
        ctx.addPath(rr(CGRect(x: x, y: pad.minY - 36, width: 26, height: 96), 13)); ctx.setFillColor(hex("#D9DEE8")); ctx.fillPath()
        ctx.addPath(rr(CGRect(x: x + 6, y: pad.minY - 30, width: 8, height: 84), 4)); ctx.setFillColor(hex("#FFFFFF", 0.8)); ctx.fillPath()
    }
    // Handwritten-ish text strokes and a prompt.
    ctx.setStrokeColor(hex("#26324A", 0.8)); ctx.setLineWidth(12); ctx.setLineCap(.round)
    for (i, w) in [300.0, 360.0].enumerated() {
        let yy = pad.minY + 150 + CGFloat(i) * 62 - 16
        ctx.move(to: CGPoint(x: pad.minX + 130, y: yy)); ctx.addLine(to: CGPoint(x: pad.minX + 130 + CGFloat(w), y: yy))
    }
    ctx.strokePath()
    text(ctx, ">_", font: .monospacedSystemFont(ofSize: 170, weight: .black), color: hex("#1E9E57"), at: CGPoint(x: pad.minX + 124, y: pad.maxY - 90))
}

// ── Option C: "Cursor Monogram" — minimal and modern: a bold "L" whose foot is a blinking text
// caret, on deep charcoal, with a strip of coloured tabs (the per-tab tints) along the bottom.
render("C-cursor-monogram") { ctx in
    ctx.drawLinearGradient(gradient([hex("#23262F"), hex("#0D0F14")], [0, 1]), start: CGPoint(x: 200, y: 100), end: CGPoint(x: 824, y: 924), options: [])
    ctx.drawRadialGradient(gradient([hex("#5B8CFF", 0.28), hex("#5B8CFF", 0)], [0, 1]),
                           startCenter: CGPoint(x: 512, y: 430), startRadius: 0, endCenter: CGPoint(x: 512, y: 430), endRadius: 460, options: [])
    // "L": vertical stem + foot, rounded.
    let stem = CGRect(x: 330, y: 230, width: 110, height: 460)
    ctx.addPath(rr(stem, 30)); ctx.setFillColor(hex("#F5F7FB")); ctx.fillPath()
    let foot = CGRect(x: 330, y: 600, width: 300, height: 90)
    ctx.addPath(rr(foot, 30)); ctx.fillPath()
    // Caret after the L.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: hex("#5B8CFF", 0.9))
    ctx.addPath(rr(CGRect(x: 666, y: 330, width: 38, height: 360), 19)); ctx.setFillColor(hex("#6FA0FF")); ctx.fillPath()
    ctx.restoreGState()
    // Coloured tab strip.
    let colours = ["#E5484D", "#F5A524", "#30A46C", "#3E63DD", "#8E4EC6"]
    let stripY: CGFloat = 780, tabW: CGFloat = 118, gap: CGFloat = 14
    let startX = 512 - (CGFloat(colours.count) * tabW + CGFloat(colours.count - 1) * gap) / 2
    for (i, c) in colours.enumerated() {
        ctx.addPath(rr(CGRect(x: startX + CGFloat(i) * (tabW + gap), y: stripY, width: tabW, height: 40), 20))
        ctx.setFillColor(hex(c)); ctx.fillPath()
    }
}
print("done")
