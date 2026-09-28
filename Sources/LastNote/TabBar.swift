import AppKit

/// Notepad++-style tabs: click to select, × or middle-click to close, right-click for a menu.
/// Used for documents and (in compact form) for console sessions.
final class TabBar: NSView {
    struct Item {
        var title: String
        var dirty: Bool
        var tooltip: String?
        var tint: NSColor? = nil
        /// Shown in a side-by-side pane (but not necessarily the active one).
        var visible = false
    }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNew: (() -> Void)?
    /// Context menu for the tab at an index.
    var menuForTab: ((Int) -> NSMenu?)?
    /// A tab was renamed inline (double-click or `beginRename`). Empty string = reset to default.
    var onRename: ((Int, String) -> Void)?
    /// ⌘-click: add the tab to / remove it from the side-by-side view.
    var onCommandClick: ((Int) -> Void)?

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
        // Update existing tab views in place; only add/remove views when the number of tabs
        // changes. Rebuilding on every change would destroy a tab while it is still handling the
        // click that caused the change.
        var tabs = stack.arrangedSubviews.compactMap { $0 as? TabItemView }
        while tabs.count > items.count { tabs.removeLast().removeFromSuperview() }
        while tabs.count < items.count {
            let tab = TabItemView(compact: compact)
            tab.onSelect = { [weak self] in self?.onSelect?($0) }
            tab.onClose = { [weak self] in self?.onClose?($0) }
            tab.menuProvider = { [weak self] in self?.menuForTab?($0) }
            tab.onRename = { [weak self] in self?.onRename?($0, $1) }
            tab.onCommandClick = { [weak self] in self?.onCommandClick?($0) }
            stack.addArrangedSubview(tab)
            tabs.append(tab)
        }
        for (i, item) in items.enumerated() {
            tabs[i].update(item: item, index: i, selected: i == selected, theme: theme, renamable: onRename != nil)
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
    var onClose: ((Int) -> Void)?
    var onRename: ((Int, String) -> Void)?
    var onCommandClick: ((Int) -> Void)?
    var menuProvider: ((Int) -> NSMenu?)?

    private var index = 0
    private var visibleInPane = false
    private var title = ""
    private var selected = false
    private var theme = Theme.dark
    private var tint: NSColor?
    private var renamable = true
    private let compact: Bool
    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let accent = CALayer()
    private var editor: NSTextField?
    private var editingWidth: NSLayoutConstraint?
    private var cancelled = false
    private var hovering = false { didSet { updateColors() } }

    init(compact: Bool) {
        self.compact = compact
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer?.masksToBounds = true

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
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(item: TabBar.Item, index: Int, selected: Bool, theme: Theme, renamable: Bool) {
        self.index = index
        self.title = item.title
        self.selected = selected
        self.theme = theme
        self.tint = item.tint
        self.renamable = renamable
        self.visibleInPane = item.visible
        toolTip = [item.tooltip, "⌘-click to show side by side"].compactMap { $0 }.joined(separator: "\n")
        label.stringValue = (item.dirty ? "● " : "") + item.title
        label.font = .systemFont(ofSize: compact ? 11 : 12, weight: selected ? .semibold : .regular)
        updateColors()
    }

    private func updateColors() {
        let base = theme.kind == .dark ? NSColor.white : NSColor.black
        let bg: NSColor
        // Selected = active; "visible" = shown in another side-by-side pane.
        if let tint {
            // Coloured tabs carry their colour, stronger when selected.
            bg = tint.withAlphaComponent(selected ? 0.75 : visibleInPane ? 0.6 : hovering ? 0.5 : 0.35)
        } else {
            bg = selected ? base.withAlphaComponent(0.14) : visibleInPane ? base.withAlphaComponent(0.1)
                : hovering ? base.withAlphaComponent(0.07) : .clear
        }
        layer?.backgroundColor = bg.cgColor
        label.textColor = selected || tint != nil ? theme.foreground : theme.chromeText.withAlphaComponent(0.8)
        closeButton.contentTintColor = theme.chromeText
        closeButton.alphaValue = selected || hovering ? 1 : 0.35
        accent.isHidden = !selected && !visibleInPane
        accent.backgroundColor = (tint?.blended(withFraction: 0.35, of: .white) ?? theme.style(.keyword).color)
            .withAlphaComponent(selected ? 1 : 0.45).cgColor
    }

    override func layout() {
        super.layout()
        // Non-flipped view: the top edge is at maxY.
        accent.frame = CGRect(x: 0, y: bounds.height - 2, width: bounds.width, height: 2)
    }

    /// Run a callback after the current event has been fully handled, so whatever it changes
    /// (even removing this tab) can't pull a view out from under AppKit mid-click.
    private func later(_ body: @escaping () -> Void) {
        DispatchQueue.main.async(execute: body)
    }

    // MARK: Mouse

    /// The whole tab is one click target, except the × button and the rename field.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit === closeButton || hit.isDescendant(of: closeButton) { return hit }
        if let editor, hit.isDescendant(of: editor) { return hit }
        return self
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
        let i = index
        if event.modifierFlags.contains(.command) {
            later { [weak self] in self?.onCommandClick?(i) }
            return
        }
        if event.clickCount == 2, renamable {
            beginEditing()
        } else if event.clickCount == 1 {
            later { [weak self] in self?.onSelect?(i) }
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        let i = index
        later { [weak self] in self?.onClose?(i) }
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?(index) }

    @objc private func close() {
        let i = index
        later { [weak self] in self?.onClose?(i) }
    }

    // MARK: Inline rename

    func beginEditing() {
        guard editor == nil, renamable else { return }
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
        // Give the field room to type in, even if the tab was narrow (removed when editing ends).
        let width = widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: label.leadingAnchor, constant: -2),
            field.trailingAnchor.constraint(equalTo: closeButton.trailingAnchor),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            width,
        ])
        editingWidth = width
        label.isHidden = true
        editor = field
        cancelled = false
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    /// Ends editing: first take the field out of the responder chain, then (after this event)
    /// remove it and report the new name.
    private func finishEditing(commit: Bool) {
        guard let field = editor else { return }
        editor = nil
        let text = field.stringValue
        let i = index, oldTitle = title
        if let w = window, let r = w.firstResponder as? NSView, r.isDescendant(of: field) || r === field.currentEditor() {
            w.makeFirstResponder(nil)
        }
        later { [weak self] in
            field.removeFromSuperview()
            self?.editingWidth?.isActive = false
            self?.editingWidth = nil
            self?.label.isHidden = false
            if commit, text != oldTitle { self?.onRename?(i, text) }
        }
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
}
