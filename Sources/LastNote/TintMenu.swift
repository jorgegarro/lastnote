import AppKit

/// "Tab Colour" menu shared by editor tabs and console tabs: window default, presets, or any
/// colour via the system colour panel (applied live while you drag in the panel).
enum TintMenu {
    static let presets: [(String, String)] = [
        ("Red", "#B3261E"), ("Orange", "#C0611B"), ("Yellow", "#B8930B"), ("Green", "#2E7D32"),
        ("Teal", "#00796B"), ("Blue", "#1565C0"), ("Indigo", "#3949AB"), ("Purple", "#6A1B9A"),
        ("Pink", "#AD1457"), ("Brown", "#5D4037"), ("Grey", "#546E7A"), ("Black", "#000000"),
    ]

    /// Builds a menu. `onPick(nil)` means "use the window tint".
    static func make(current: NSColor?, onPick: @escaping (NSColor?) -> Void) -> NSMenu {
        let menu = NSMenu(title: "Tab Colour")
        let none = ClosureMenuItem(title: "Window Tint (Default)") { onPick(nil) }
        none.state = current == nil ? .on : .off
        menu.addItem(none)
        menu.addItem(.separator())
        for (name, hex) in presets {
            let color = NSColor(hex: hex)!
            let item = ClosureMenuItem(title: name) { onPick(color) }
            item.image = swatch(color)
            item.state = current?.hexString == hex ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let custom = ClosureMenuItem(title: "Custom Colour…") {
            ColorPanelRouter.shared.pick(initial: current ?? AppSettings.shared.tintColor, onChange: onPick)
        }
        if let current, !presets.contains(where: { $0.1 == current.hexString }) {
            custom.image = swatch(current)
            custom.state = .on
        }
        menu.addItem(custom)
        return menu
    }

    static func swatch(_ color: NSColor, size: CGFloat = 12) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            color.setFill()
            path.fill()
            NSColor.secondaryLabelColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }
}

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

/// Routes the shared NSColorPanel to whoever asked last.
final class ColorPanelRouter: NSObject {
    static let shared = ColorPanelRouter()
    private var onChange: ((NSColor) -> Void)?

    func pick(initial: NSColor, onChange: @escaping (NSColor) -> Void) {
        self.onChange = nil  // don't fire for the initial colour
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = initial
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.isContinuous = true
        self.onChange = onChange
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(sender.color.usingColorSpace(.sRGB) ?? sender.color)
    }
}
