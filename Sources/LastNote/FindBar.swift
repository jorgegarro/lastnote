import AppKit
import SciKit

/// Inline Find / Replace bar shown under the editor. Supports match case, whole word and
/// regular expressions, highlights every match and shows the count.
final class FindBar: NSView, NSSearchFieldDelegate {
    var document: () -> Document? = { nil }
    var onClose: (() -> Void)?
    /// A user-triggered find/replace, for macro recording.
    var onRecord: ((MacroStep) -> Void)?

    let findField = NSSearchField()
    let replaceField = NSTextField()
    let matchCase = NSButton(checkboxWithTitle: "Match case", target: nil, action: nil)
    let wholeWord = NSButton(checkboxWithTitle: "Whole word", target: nil, action: nil)
    let regex = NSButton(checkboxWithTitle: "Regex", target: nil, action: nil)
    let countLabel = NSTextField(labelWithString: "")
    private var replaceRow: NSStackView!
    private var rows: NSStackView!

    var showsReplace = false {
        didSet { replaceRow.isHidden = !showsReplace }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        findField.placeholderString = "Find"
        findField.sendsWholeSearchString = false
        findField.sendsSearchStringImmediately = true
        findField.delegate = self
        findField.target = self
        findField.action = #selector(findFieldChanged)
        replaceField.placeholderString = "Replace with"
        replaceField.delegate = self
        for f in [findField, replaceField] as [NSTextField] {
            // Preferred width only: the bar must never stop the window from getting narrow.
            let w = f.widthAnchor.constraint(greaterThanOrEqualToConstant: 260)
            w.priority = .defaultLow
            w.isActive = true
            f.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        }
        for b in [matchCase, wholeWord, regex] {
            b.target = self
            b.action = #selector(optionsChanged)
            b.font = .systemFont(ofSize: 11)
        }
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor

        let prev = button("chevron.up", "Find previous (⇧⌘G)", #selector(findPrevious))
        let next = button("chevron.down", "Find next (⌘G / Enter)", #selector(findNext))
        let close = button("xmark", "Close (Esc)", #selector(closeBar))
        let findRow = NSStackView(views: [findField, prev, next, countLabel, NSView(), matchCase, wholeWord, regex, close])
        let replaceOne = NSButton(title: "Replace", target: self, action: #selector(replaceOne))
        let replaceAll = NSButton(title: "Replace All", target: self, action: #selector(replaceAll))
        for b in [replaceOne, replaceAll] { b.controlSize = .small; b.bezelStyle = .rounded }
        replaceRow = NSStackView(views: [replaceField, replaceOne, replaceAll, NSView()])
        for r in [findRow, replaceRow!] { r.spacing = 6; r.orientation = .horizontal }
        // On narrow windows the options and the match count drop out before anything else.
        for v in [regex, wholeWord, matchCase, countLabel] as [NSView] {
            findRow.setVisibilityPriority(.detachOnlyIfNecessary, for: v)
        }
        for r in [findRow, replaceRow!] { r.setClippingResistancePriority(.defaultLow, for: .horizontal) }
        rows = NSStackView(views: [findRow, replaceRow])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rows.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            findRow.widthAnchor.constraint(equalTo: rows.widthAnchor),
        ])
        replaceRow.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme(_ theme: Theme) {
        layer?.backgroundColor = theme.chrome.cgColor
    }

    private func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.toolTip = tip
        return b
    }

    func focusFind(prefill: String?) {
        if let prefill, !prefill.isEmpty, !prefill.contains("\n") { findField.stringValue = prefill }
        window?.makeFirstResponder(findField)
        findField.currentEditor()?.selectAll(nil)
        highlightAll()
    }

    // MARK: Searching

    private var flags: Int {
        var f = 0
        if matchCase.state == .on { f |= Int(SCFIND_MATCHCASE) }
        if wholeWord.state == .on { f |= Int(SCFIND_WHOLEWORD) }
        if regex.state == .on { f |= Int(SCFIND_REGEXP | SCFIND_CXX11REGEX) }
        return f
    }

    private var needle: String { findField.stringValue }

    /// Search `[from, to)` (to < from searches backwards). Returns the match range or nil.
    private func search(_ v: ScintillaView, from: Int, to: Int) -> (Int, Int)? {
        v.sci(SCI_SETSEARCHFLAGS, flags)
        v.sci(SCI_SETTARGETRANGE, from, to)
        let pos = v.sci(SCI_SEARCHINTARGET, needle.utf8.count, string: needle)
        return pos < 0 ? nil : (pos, v.sci(SCI_GETTARGETEND))
    }

    @discardableResult
    @objc func findNext() -> Bool { record(.next); return find(forward: true) }

    @discardableResult
    @objc func findPrevious() -> Bool { record(.previous); return find(forward: false) }

    private func record(_ action: MacroStep.FindAction) {
        onRecord?(MacroStep(kind: .find, findAction: action, find: findField.stringValue, replace: replaceField.stringValue,
                            matchCase: matchCase.state == .on, wholeWord: wholeWord.state == .on, regex: regex.state == .on))
    }

    /// Replay a recorded find/replace step (sets the fields like Notepad++'s dialog would).
    func perform(_ step: MacroStep) {
        findField.stringValue = step.find ?? ""
        replaceField.stringValue = step.replace ?? ""
        matchCase.state = step.matchCase ? .on : .off
        wholeWord.state = step.wholeWord ? .on : .off
        regex.state = step.regex ? .on : .off
        switch step.findAction {
        case .next: _ = find(forward: true)
        case .previous: _ = find(forward: false)
        case .replace: replaceOneNow()
        case .replaceAll: replaceAllNow()
        case nil: break
        }
    }

    private func find(forward: Bool) -> Bool {
        guard let v = document()?.view, !needle.isEmpty else { return false }
        let length = v.sci(SCI_GETLENGTH)
        let selStart = v.sci(SCI_GETSELECTIONSTART), selEnd = v.sci(SCI_GETSELECTIONEND)
        var match = forward ? search(v, from: selEnd, to: length) : search(v, from: selStart, to: 0)
        if match == nil {  // wrap around
            match = forward ? search(v, from: 0, to: length) : search(v, from: length, to: 0)
        }
        guard let (start, end) = match else {
            NSSound.beep()
            return false
        }
        v.sci(SCI_SETSEL, start, end)
        v.sci(SCI_ENSUREVISIBLEENFORCEPOLICY, v.sci(SCI_LINEFROMPOSITION, start))
        v.sci(SCI_SCROLLRANGE, end, start)
        return true
    }

    @objc func replaceOne() {
        record(.replace)
        replaceOneNow()
    }

    private func replaceOneNow() {
        guard let v = document()?.view, !needle.isEmpty else { return }
        let selStart = v.sci(SCI_GETSELECTIONSTART), selEnd = v.sci(SCI_GETSELECTIONEND)
        // Replace only if the current selection is itself a match.
        if let (s, e) = search(v, from: selStart, to: selEnd), s == selStart, e == selEnd {
            let message = regex.state == .on ? SCI_REPLACETARGETRE : SCI_REPLACETARGET
            let replacement = replaceField.stringValue
            v.sci(message, replacement.utf8.count, string: replacement)
            v.sci(SCI_SETSEL, v.sci(SCI_GETTARGETEND), v.sci(SCI_GETTARGETEND))
        }
        _ = find(forward: true)
        highlightAll()
    }

    @objc func replaceAll() {
        record(.replaceAll)
        replaceAllNow()
    }

    private func replaceAllNow() {
        guard let v = document()?.view, !needle.isEmpty else { return }
        let message = regex.state == .on ? SCI_REPLACETARGETRE : SCI_REPLACETARGET
        let replacement = replaceField.stringValue
        var count = 0
        var from = 0
        v.sci(SCI_BEGINUNDOACTION)
        while let (start, end) = search(v, from: from, to: v.sci(SCI_GETLENGTH)) {
            v.sci(message, replacement.utf8.count, string: replacement)
            let newEnd = v.sci(SCI_GETTARGETEND)
            from = end == start ? newEnd + 1 : newEnd  // step past empty regex matches
            count += 1
            if from > v.sci(SCI_GETLENGTH) || count > 1_000_000 { break }
        }
        v.sci(SCI_ENDUNDOACTION)
        countLabel.stringValue = "Replaced \(count)"
        highlightAll(updateLabel: false)
    }

    /// Mark every match with the find indicator and show the count.
    func highlightAll(updateLabel: Bool = true) {
        guard let v = document()?.view else { return }
        let length = v.sci(SCI_GETLENGTH)
        v.sci(SCI_SETINDICATORCURRENT, indicatorFind)
        v.sci(SCI_INDICATORCLEARRANGE, 0, length)
        guard !needle.isEmpty else { if updateLabel { countLabel.stringValue = "" }; return }
        var count = 0
        var from = 0
        while count < 100_000, let (start, end) = search(v, from: from, to: length) {
            if end > start { v.sci(SCI_INDICATORFILLRANGE, start, end - start) }
            from = max(end, start + 1)
            count += 1
        }
        if updateLabel { countLabel.stringValue = count == 0 ? "No results" : "\(count) match\(count == 1 ? "" : "es")" }
    }

    func clearHighlights() {
        guard let v = document()?.view else { return }
        v.sci(SCI_SETINDICATORCURRENT, indicatorFind)
        v.sci(SCI_INDICATORCLEARRANGE, 0, v.sci(SCI_GETLENGTH))
    }

    @objc private func findFieldChanged() { highlightAll() }
    @objc private func optionsChanged() { highlightAll() }

    @objc func closeBar() {
        clearHighlights()
        onClose?()
    }

    // Enter = next, Shift+Enter = previous, Esc = close.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if control === replaceField { replaceOne(); return true }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { _ = findPrevious() } else { _ = findNext() }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            closeBar()
            return true
        default:
            return false
        }
    }
}
