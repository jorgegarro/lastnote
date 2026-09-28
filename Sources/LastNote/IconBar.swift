import AppKit

/// Notepad++-style bar of icons for the most-used commands. It sits in the title-bar row, to the
/// right of the window buttons. Buttons send their action down the responder chain, so edit
/// commands go to whatever has focus (editor or console).
final class IconBar: NSView {
    struct Item {
        let symbol: String
        let tip: String
        let action: Selector
    }

    static let groups: [[Item]] = [
        [
            Item(symbol: "doc.badge.plus", tip: "New (⌘N)", action: #selector(MainWindowController.newDocument(_:))),
            Item(symbol: "folder", tip: "Open… (⌘O)", action: #selector(MainWindowController.openDocument(_:))),
            Item(symbol: "square.and.arrow.down", tip: "Save (⌘S)", action: #selector(MainWindowController.saveDocument(_:))),
            Item(symbol: "square.and.arrow.down.on.square", tip: "Save All (⌥⌘S)", action: #selector(MainWindowController.saveAllDocuments(_:))),
            Item(symbol: "xmark.square", tip: "Close Tab (⌘W)", action: #selector(MainWindowController.closeTab(_:))),
        ],
        [
            Item(symbol: "scissors", tip: "Cut (⌘X)", action: #selector(NSText.cut(_:))),
            Item(symbol: "doc.on.doc", tip: "Copy (⌘C)", action: #selector(NSText.copy(_:))),
            Item(symbol: "doc.on.clipboard", tip: "Paste (⌘V)", action: #selector(NSText.paste(_:))),
        ],
        [
            Item(symbol: "arrow.uturn.backward", tip: "Undo (⌘Z)", action: Selector(("undo:"))),
            Item(symbol: "arrow.uturn.forward", tip: "Redo (⇧⌘Z)", action: Selector(("redo:"))),
        ],
        [
            Item(symbol: "magnifyingglass", tip: "Find (⌘F)", action: #selector(MainWindowController.showFind(_:))),
            Item(symbol: "arrow.left.arrow.right", tip: "Replace (⌥⌘F)", action: #selector(MainWindowController.showReplace(_:))),
            Item(symbol: "arrow.down.to.line", tip: "Go to Line (⌘L)", action: #selector(MainWindowController.goToLine(_:))),
        ],
        [
            Item(symbol: "plus.magnifyingglass", tip: "Zoom In (⌘=)", action: #selector(MainWindowController.zoomIn(_:))),
            Item(symbol: "minus.magnifyingglass", tip: "Zoom Out (⌘-)", action: #selector(MainWindowController.zoomOut(_:))),
        ],
        [
            Item(symbol: "arrow.turn.down.left", tip: "Word Wrap (⌥Z)", action: #selector(MainWindowController.toggleWordWrap(_:))),
            Item(symbol: "paragraphsign", tip: "Show All Characters", action: #selector(MainWindowController.toggleShowAllCharacters(_:))),
            Item(symbol: "text.bubble", tip: "Toggle Comment (⌘/)", action: #selector(MainWindowController.toggleComment(_:))),
            Item(symbol: "bookmark", tip: "Toggle Bookmark (⌘F2)", action: #selector(MainWindowController.toggleBookmark(_:))),
        ],
        [
            Item(symbol: "record.circle", tip: "Start/Stop Recording Macro (⌃⇧R)", action: #selector(MainWindowController.toggleMacroRecording(_:))),
            Item(symbol: "play.circle", tip: "Playback Macro (⌃⇧P)", action: #selector(MainWindowController.playMacro(_:))),
        ],
        [
            Item(symbol: "terminal", tip: "Show/Hide Console (⌃`)", action: #selector(MainWindowController.toggleConsole(_:))),
            Item(symbol: "plus.rectangle.on.rectangle", tip: "New Console Tab (⌃⇧`)", action: #selector(MainWindowController.newConsoleTab(_:))),
            Item(symbol: "play.fill", tip: "Run File in Console (⌘R)", action: #selector(MainWindowController.runInConsole(_:))),
        ],
        [
            Item(symbol: "circle.lefthalf.filled", tip: "Transparent Window (⌥⌘T)", action: #selector(MainWindowController.toggleTransparency(_:))),
            Item(symbol: "slider.horizontal.3", tip: "Transparency & Tint…", action: #selector(MainWindowController.showAppearancePopover(_:))),
            Item(symbol: "paintpalette", tip: "Tab Colour…", action: #selector(MainWindowController.showTabColorMenu(_:))),
            Item(symbol: "rectangle.stack", tip: "Sessions (save / load window layout & colours)", action: #selector(MainWindowController.showSessionsMenu(_:))),
        ],
    ]

    private let stack = NSStackView()
    private(set) var buttons: [Selector: NSButton] = [:]
    let pathLabel = NSTextField(labelWithString: "")
    private var theme = Theme.dark

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        var priority: Float = 1000
        for (g, group) in IconBar.groups.enumerated() {
            if g > 0 {
                let sep = SeparatorView()
                stack.addArrangedSubview(sep)
                stack.setVisibilityPriority(NSStackView.VisibilityPriority(rawValue: priority), for: sep)
            }
            for item in group {
                let b = IconButton(symbol: item.symbol, tip: item.tip, action: item.action)
                stack.addArrangedSubview(b)
                stack.setVisibilityPriority(NSStackView.VisibilityPriority(rawValue: priority), for: b)
                buttons[item.action] = b
            }
            priority -= 50  // later groups disappear first when the window is narrow
        }

        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.alignment = .right
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        pathLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        addSubview(pathLabel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            pathLabel.leadingAnchor.constraint(greaterThanOrEqualTo: stack.trailingAnchor, constant: 16),
            pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            pathLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)
        // Let the window squeeze the bar: the stack then drops whole groups (lowest visibility
        // priority first) instead of forcing the window to stay wide.
        stack.setClippingResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The icon bar covers the title-bar row, so handle the title-bar double-click here,
    /// honouring System Settings ▸ Desktop & Dock ▸ "Double-click a window's title bar to".
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Buttons get their clicks; everything else (gaps, separators, the path) counts as title bar.
        guard let hit = super.hitTest(point) else { return nil }
        return hit is NSButton ? hit : self
    }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2, let window else { return super.mouseDown(with: event) }
        let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
        switch action {
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)  // "Maximize" / "Fill": fill the screen
        }
    }

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        pathLabel.textColor = theme.chromeText.withAlphaComponent(0.7)
        for case let s as SeparatorView in stack.arrangedSubviews { s.color = theme.separator }
        buttons.values.forEach { ($0 as? IconButton)?.theme = theme }
    }

    /// Highlight toggles that are on; dim commands that can't run right now.
    func update(on: Set<Selector>, disabled: Set<Selector>) {
        for (sel, b) in buttons {
            guard let b = b as? IconButton else { continue }
            b.isOn = on.contains(sel)
            b.isEnabled = !disabled.contains(sel)
        }
    }
}

final class IconButton: NSButton {
    var theme = Theme.dark { didSet { refresh() } }
    var isOn = false { didSet { if isOn != oldValue { refresh() } } }
    override var isEnabled: Bool { didSet { refresh() } }
    private var hovering = false { didSet { refresh() } }

    init(symbol: String, tip: String, action: Selector) {
        super.init(frame: .zero)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(config)
        imagePosition = .imageOnly
        isBordered = false
        toolTip = tip
        self.action = action
        target = nil  // responder chain
        wantsLayer = true
        layer?.cornerRadius = 5
        refusesFirstResponder = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    private func refresh() {
        let base = theme.kind == .dark ? NSColor.white : NSColor.black
        let accent = theme.style(.keyword).color
        contentTintColor = isOn ? accent : theme.chromeText
        alphaValue = isEnabled ? 1 : 0.35
        let bg: NSColor = isOn ? accent.withAlphaComponent(0.18) : (hovering && isEnabled ? base.withAlphaComponent(0.1) : .clear)
        layer?.backgroundColor = bg.cgColor
    }
}

private final class SeparatorView: NSView {
    var color: NSColor = .separatorColor { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 9).isActive = true
        heightAnchor.constraint(equalToConstant: 16).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSRect(x: 4, y: 0, width: 1, height: bounds.height).fill()
    }
}
