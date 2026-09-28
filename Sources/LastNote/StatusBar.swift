import AppKit

/// Bottom status bar: language, caret position, encoding, line endings, plus quick toggles for
/// the console and the transparency popover.
final class StatusBar: NSView {
    let languageButton = StatusBar.textButton()
    let positionLabel = StatusBar.label()
    let lengthLabel = StatusBar.label()
    let encodingLabel = StatusBar.label()
    let eolButton = StatusBar.textButton()
    let appearanceButton = StatusBar.iconButton("circle.lefthalf.filled", "Transparency & tint")
    let consoleButton = StatusBar.iconButton("terminal", "Show/hide console (⌃`)")
    /// Shown while a macro is being recorded.
    let recordingLabel: NSTextField = {
        let l = NSTextField(labelWithString: "● REC")
        l.font = .systemFont(ofSize: 11, weight: .bold)
        l.textColor = .systemRed
        l.toolTip = "Recording a macro — ⌃⇧R to stop"
        l.isHidden = true
        return l
    }()
    private let separatorLine = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        separatorLine.wantsLayer = true
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separatorLine)

        let left = NSStackView(views: [languageButton, lengthLabel])
        let right = NSStackView(views: [recordingLabel, positionLabel, encodingLabel, eolButton, consoleButton, appearanceButton])
        for s in [left, right] {
            s.spacing = 16
            s.translatesAutoresizingMaskIntoConstraints = false
            addSubview(s)
        }
        right.setCustomSpacing(10, after: eolButton)
        right.setCustomSpacing(4, after: consoleButton)
        NSLayoutConstraint.activate([
            separatorLine.topAnchor.constraint(equalTo: topAnchor),
            separatorLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 1),
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            right.centerYAnchor.constraint(equalTo: centerYAnchor),
            left.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme(_ theme: Theme) {
        layer?.backgroundColor = theme.chrome.cgColor
        separatorLine.layer?.backgroundColor = theme.separator.cgColor
        for l in [positionLabel, lengthLabel, encodingLabel] { l.textColor = theme.chromeText }
        for b in [languageButton, eolButton] {
            b.attributedTitle = NSAttributedString(string: b.title, attributes: [
                .foregroundColor: theme.chromeText, .font: NSFont.systemFont(ofSize: 11),
            ])
        }
        for b in [appearanceButton, consoleButton] { b.contentTintColor = theme.chromeText }
    }

    func setButtonTitle(_ button: NSButton, _ title: String, theme: Theme) {
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: theme.chromeText, .font: NSFont.systemFont(ofSize: 11),
        ])
    }

    private static func label() -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        return l
    }

    private static func textButton() -> NSButton {
        let b = NSButton(title: "", target: nil, action: nil)
        b.isBordered = false
        b.font = .systemFont(ofSize: 11)
        return b
    }

    private static func iconButton(_ symbol: String, _ tip: String) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: nil, action: nil)
        b.isBordered = false
        b.toolTip = tip
        b.imageScaling = .scaleProportionallyDown
        return b
    }
}
