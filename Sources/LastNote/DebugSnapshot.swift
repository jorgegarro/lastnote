import AppKit

/// Development aid: `LASTNOTE_SNAPSHOT=/path/out.png` renders the main window to a PNG shortly
/// after launch (the desktop/blur behind the window isn't captured, only the window's own layers).
enum DebugSnapshot {
    /// CGWindowListCreateImage is hidden from the current SDK but still exported; a process may
    /// always capture its own windows.
    private static func windowServerImage(_ window: NSWindow) -> CGImage? {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen(nil, RTLD_NOW), let sym = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let fn = unsafeBitCast(sym, to: Fn.self)
        // listOptions 8 = kCGWindowListOptionIncludingWindow; imageOptions 1 = boundsIgnoreFraming
        return fn(.null, 8, UInt32(window.windowNumber), 1)?.takeRetainedValue()
    }

    private static func allSubviews(_ v: NSView) -> [NSView] { v.subviews + v.subviews.flatMap(allSubviews) }

    private static func dump(_ v: NSView, _ depth: Int) {
        let bg = v.layer?.backgroundColor.map { NSColor(cgColor: $0)?.description ?? "?" } ?? "-"
        print(String(repeating: "  ", count: depth) + "\(type(of: v)) \(v.frame) hidden=\(v.isHidden) opaque=\(v.isOpaque) bg=\(bg)")
        v.subviews.forEach { dump($0, depth + 1) }
    }

    static func scheduleIfRequested(_ window: NSWindow?) {
        guard let path = ProcessInfo.processInfo.environment["LASTNOTE_SNAPSHOT"], let window else { return }
        let delay = Double(ProcessInfo.processInfo.environment["LASTNOTE_SNAPSHOT_DELAY"] ?? "") ?? 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let image = windowServerImage(window) {
                // Real composited pixels (including what's behind a transparent window).
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                if ProcessInfo.processInfo.environment["LASTNOTE_SNAPSHOT_QUIT"] == "1" { exit(0) }
                return
            }
            guard let view = window.contentView?.superview ?? window.contentView else { return }
            let scale = window.backingScaleFactor
            let size = view.bounds.size
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
            rep.size = size
            if let layer = view.layer, let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                // Render the layer tree (captures layer-backed views such as the terminal).
                layer.render(in: ctx.cgContext)
                // Views that draw on demand (the terminal) aren't in the layer contents; draw them directly.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = ctx
                for tv in allSubviews(view) where String(describing: type(of: tv)).contains("TerminalView") {
                    guard let r = tv.bitmapImageRepForCachingDisplay(in: tv.bounds) else { continue }
                    tv.cacheDisplay(in: tv.bounds, to: r)
                    let frame = tv.convert(tv.bounds, to: view)
                    let flipped = NSRect(x: frame.minX, y: view.isFlipped ? size.height - frame.maxY : frame.minY, width: frame.width, height: frame.height)
                    r.draw(in: flipped, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
                NSGraphicsContext.restoreGraphicsState()
            } else {
                view.cacheDisplay(in: view.bounds, to: rep)
            }
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            if ProcessInfo.processInfo.environment["LASTNOTE_SNAPSHOT_TREE"] == "1" { dump(view, 0) }
            if ProcessInfo.processInfo.environment["LASTNOTE_SNAPSHOT_QUIT"] == "1" { exit(0) }
        }
    }
}
