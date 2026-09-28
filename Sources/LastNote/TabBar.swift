import AppKit

/// Notepad++-style tabs: click to select, × or middle-click to close, right-click for a menu.
/// Used for documents and (in compact form) for console sessions.
final class TabBar: NSView {
    struct Item { var title: String; var dirty: Bool; var tooltip: String?; var tint: NSColor? = nil }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNew: (() -> Void)?
    /// Context menu for the tab at an index.
    var menuForTab: ((Int) -> NSMenu?)?
    /// A tab was renamed inline (double-click or `beginRename`). Empty string = reset to default.
    var onRename: ((Int, String) -> Void)?

    let compact: Bool
    private let stack = NSStackView()
    private let newButton = NSButton()
    private var theme = Theme.dark
    /// Paint our own chrome background (off when embedded in a header that already has one).
    var drawsBackground = true

    init(compact: Bool = false) {
        self.compact = compact
        super.init(frame: .zero)
        wantsLayer = true
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.distribution = .fill
        stack.alignment = .bottom
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        newButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New tab")
        newButton.isBordered = false
        newButton.target = self
        newButton.action = #selector(newTab)
        newButton.toolTip = compact ? "New console tab (⌃⇧`)" : "New tab (⌘N)"
        newButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(newButton)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: compact ? 2 : 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            newButton.leadingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 6),
            newButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            newButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            newButton.widthAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func newTab() { onNew?() }

    func reload(items: [Item], selected: Int, theme: Theme) {
        self.theme = theme
        layer?.backgroundColor = drawsBackground ? theme.chrome.cgColor : nil
        newButton.contentTintColor = theme.chromeText
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (i, item) in items.enumerated() {
            let tab = TabItemView(item: item, index: i, selected: i == selected, theme: theme, compact: compact)
            tab.onSelect = { [weak self] in self?.onSelect?($0) }
            tab.onClose = { [weak self] in self?.onClose?($0) }
            tab.menuProvider = { [weak self] in self?.menuForTab?($0) }
            tab.onRename = onRename == nil ? nil : { [weak self] in self?.onRename?($0, $1) }
            stack.addArrangedSubview(tab)
        }
    }

    /// Start inline editing of a tab's name.
    func beginRename(at index: Int) {
        guard stack.arrangedSubviews.indices.contains(index) else { return }
        (stack.arrangedSubviews[index] as? TabItemView)?.beginEditing()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onNew?() }  // double-click empty tab area = new tab (like Notepad++)
        else { super.mouseDown(with: event) }
    }
}

private final class TabItemView: NSView, NSTextFieldDelegate {
    var onSelect: ((Int) -> Void)?
    var onRename: ((Int, String) -> Void)?
    private var editor: NSTextField?
    private let title: String
    var onClose: ((Int) -> Void)?
    var menuProvider: ((Int) -> NSMenu?)?
    private let index: Int
    private let selected: Bool
    private let theme: Theme
    private let tint: NSColor?
    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let accent = CALayer()
    private var hovering = false { didSet { updateColors() } }

    init(item: TabBar.Item, index: Int, selected: Bool, theme: Theme, compact: Bool) {
        self.index = index
        self.selected = selected
        self.theme = theme
        self.tint = item.tint
        self.title = item.title
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer?.masksToBounds = true
        toolTip = item.tooltip

        label.stringValue = (item.dirty ? "● " : "") + item.title
        label.font = .systemFont(ofSize: compact ? 11 : 12, weight: selected ? .semibold : .regular)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(close)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        accent.name = "accent"
        layer?.addSublayer(accent)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: compact ? 21 : 27),
            widthAnchor.constraint(lessThanOrEqualToConstant: compact ? 180 : 220),
            widthAnchor.constraint(greaterThanOrEqualToConstant: compact ? 60 : 70),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: compact ? 12 : 14),
            closeButton.heightAnchor.constraint(equalToConstant: compact ? 12 : 14),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateColors() {
        let base = theme.kind == .dark ? NSColor.white : NSColor.black
        let bg: NSColor
        if let tint {
            // Coloured tabs carry their colour, stronger when selected.
            bg = tint.withAlphaComponent(selected ? 0.75 : hovering ? 0.5 : 0.35)
        } else {
            bg = selected ? base.withAlphaComponent(0.14) : hovering ? base.withAlphaComponent(0.07) : .clear
        }
        layer?.backgroundColor = bg.cgColor
        label.textColor = selected || tint != nil ? theme.foreground : theme.chromeText.withAlphaComponent(0.8)
        closeButton.contentTintColor = theme.chromeText
        closeButton.alphaValue = selected || hovering ? 1 : 0.35
        accent.isHidden = !selected
        accent.backgroundColor = (tint?.blended(withFraction: 0.35, of: .white) ?? theme.style(.keyword).color).cgColor
    }

    override func layout() {
        super.layout()
        // Non-flipped view: the top edge is at maxY.
        accent.frame = CGRect(x: 0, y: bounds.height - 2, width: bounds.width, height: 2)
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {
        // Control-click is the Mac "right click"; AppKit only turns it into a context menu if the
        // view doesn't handle mouseDown itself, so do it here.
        if event.modifierFlags.contains(.control) {
            if let menu = menuProvider?(index) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
            return
        }
        if event.clickCount == 2, onRename != nil { beginEditing() } else if event.clickCount == 1 { onSelect?(index) }
    }

    // MARK: Inline rename

    func beginEditing() {
        guard editor == nil, onRename != nil else { return }
        let field = NSTextField(string: title)
        field.font = label.font
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.backgroundColor = theme.kind == .dark ? NSColor.black.withAlphaComponent(0.5) : NSColor.white.withAlphaComponent(0.8)
        field.textColor = theme.foreground
        field.delegate = self
        field.placeholderString = "Default name"
        field.cell?.isScrollable = true
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: label.leadingAnchor, constant: -2),
            field.trailingAnchor.constraint(equalTo: closeButton.trailingAnchor),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            // Give the field room to type in, even if the tab was narrow.
            widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
        label.isHidden = true
        editor = field
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private var cancelled = false

    private func finishEditing(commit: Bool) {
        guard let field = editor else { return }
        editor = nil
        let text = field.stringValue
        field.removeFromSuperview()
        label.isHidden = false
        if commit, text != title { onRename?(index, text) }  // may rebuild the tab bar
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            cancelled = true
            finishEditing(commit: false)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            finishEditing(commit: true)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Clicking elsewhere commits, like Finder.
        if !cancelled { finishEditing(commit: true) }
        cancelled = false
    }
    override func otherMouseDown(with event: NSEvent) { if event.buttonNumber == 2 { onClose?(index) } }
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?(index) }
    @objc private func close() { onClose?(index) }
}
