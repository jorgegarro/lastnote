import AppKit

/// What one pane shows.
struct PaneItem {
    let view: NSView
    let title: String
    let tint: NSColor?
    /// Region colour painted behind the view; nil when the view paints its own background.
    let background: NSColor?
}

/// Up to three tabs shown side by side, with draggable dividers. Used by the editor and the
/// console. Pane hosts are reused (never rebuilt while handling their own clicks), and header
/// clicks are handled after the current event.
final class PaneArea: NSView, NSSplitViewDelegate {
    static let maxPanes = 3

    /// A pane's header was clicked: make it the active pane.
    var onActivate: ((Int) -> Void)?
    /// A pane's × was clicked: take that tab out of the side-by-side view.
    var onRemove: ((Int) -> Void)?

    private let split = PaneSplitView()
    private(set) var hosts: [PaneHost] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = self
        split.frame = bounds
        split.autoresizingMask = [.width, .height]
        addSubview(split)
    }

    required init?(coder: NSCoder) { fatalError() }

    var paneCount: Int { hosts.count }

    /// Index of the pane whose content contains `view`.
    func pane(containing view: NSView) -> Int? {
        hosts.firstIndex { view.isDescendant(of: $0) }
    }

    func show(_ items: [PaneItem], active: Int, theme: Theme) {
        let countChanged = items.count != hosts.count
        while hosts.count > items.count {
            let h = hosts.removeLast()
            h.clearContent()
            split.removeArrangedSubview(h)
            h.removeFromSuperview()
        }
        while hosts.count < items.count {
            let h = PaneHost()
            let i = hosts.count
            h.onActivate = { [weak self] in self?.onActivate?(i) }
            h.onRemove = { [weak self] in self?.onRemove?(i) }
            split.addArrangedSubview(h)
            hosts.append(h)
        }
        let multi = items.count > 1
        // First detach views that are moving to a different pane, then attach.
        for (i, item) in items.enumerated() where !(hosts[i].content === item.view) { hosts[i].clearContent() }
        for (i, item) in items.enumerated() {
            hosts[i].setContent(item.view)
            hosts[i].configure(title: item.title, tint: item.tint, background: item.background,
                               showsHeader: multi, active: multi && i == active, theme: theme)
        }
        split.color = theme.separator
        split.needsDisplay = true
        if countChanged { equalize() }
    }

    /// Give every pane the same width.
    func equalize() {
        let n = hosts.count
        guard n > 1 else { return }
        split.adjustSubviews()
        layoutSubtreeIfNeeded()
        let d = split.dividerThickness
        let each = (split.bounds.width - d * CGFloat(n - 1)) / CGFloat(n)
        for i in 0..<(n - 1) { split.setPosition(each * CGFloat(i + 1) + d * CGFloat(i), ofDividerAt: i) }
    }

    // MARK: NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        max(proposed, splitView.arrangedSubviews[index].frame.minX + 120)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        min(proposed, splitView.arrangedSubviews[index + 1].frame.maxX - 120)
    }
}

final class PaneSplitView: NSSplitView {
    var color: NSColor = .separatorColor
    override var dividerColor: NSColor { color }
}

/// One pane: an optional header (colour dot, name, ×) above the tab's view.
final class PaneHost: NSView {
    var onActivate: (() -> Void)?
    var onRemove: (() -> Void)?
    private(set) weak var content: NSView?

    private let header = PaneHeader()
    private let container = NSView()
    private var headerHeight: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for v in [header, container] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        headerHeight = header.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerHeight,
            container.topAnchor.constraint(equalTo: header.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        header.onClick = { [weak self] in DispatchQueue.main.async { self?.onActivate?() } }
        header.onClose = { [weak self] in DispatchQueue.main.async { self?.onRemove?() } }
    }

    required init?(coder: NSCoder) { fatalError() }

    func setContent(_ view: NSView) {
        if content === view, view.superview === container { return }
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]
        view.frame = container.bounds
        container.addSubview(view)
        content = view
    }

    func clearContent() {
        if let content, content.superview === container { content.removeFromSuperview() }
        content = nil
    }

    func configure(title: String, tint: NSColor?, background: NSColor?, showsHeader: Bool, active: Bool, theme: Theme) {
        layer?.backgroundColor = background?.cgColor
        header.isHidden = !showsHeader
        headerHeight.constant = showsHeader ? 20 : 0
        header.configure(title: title, tint: tint, active: active, theme: theme)
    }
}

private final class PaneHeader: NSView {
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let underline = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        underline.wantsLayer = true
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove from side by side")
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.isBordered = false
        closeButton.toolTip = "Remove from side by side"
        closeButton.target = self
        closeButton.action = #selector(close)
        for v in [dot, label, closeButton, underline] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 11),
            closeButton.heightAnchor.constraint(equalToConstant: 11),
            underline.leadingAnchor.constraint(equalTo: leadingAnchor),
            underline.trailingAnchor.constraint(equalTo: trailingAnchor),
            underline.bottomAnchor.constraint(equalTo: bottomAnchor),
            underline.heightAnchor.constraint(equalToConstant: 2),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, tint: NSColor?, active: Bool, theme: Theme) {
        label.stringValue = title
        label.textColor = active ? theme.foreground : theme.chromeText.withAlphaComponent(0.75)
        layer?.backgroundColor = theme.chrome.cgColor
        dot.layer?.backgroundColor = (tint ?? theme.chromeText.withAlphaComponent(0.4)).cgColor
        closeButton.contentTintColor = theme.chromeText
        underline.isHidden = !active
        underline.layer?.backgroundColor = (tint?.blended(withFraction: 0.35, of: .white) ?? theme.style(.keyword).color).cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit === closeButton ? hit : self
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    @objc private func close() { onClose?() }
}
