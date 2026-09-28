import AppKit
import SciKit

// Margin / marker / indicator numbers used throughout.
private let marginLineNumbers: Int = 0
private let marginBookmarks: Int = 1
private let marginFolding: Int = 2
let markerBookmark: Int = 24
private let indicatorSmartHighlight: Int = 8
let indicatorFind: Int = 9

enum LineEnding: String {
    case lf = "LF", crlf = "CRLF", cr = "CR"
    var sciMode: Int { self == .crlf ? Int(SC_EOL_CRLF) : self == .cr ? Int(SC_EOL_CR) : Int(SC_EOL_LF) }
    var title: String { self == .crlf ? "Windows (CR LF)" : self == .cr ? "Classic Mac (CR)" : "Unix (LF)" }
}

extension ScintillaView {
    /// Send a Scintilla message. `m` is one of the SCI_* constants.
    @discardableResult
    func sci(_ m: Int32, _ w: Int = 0, _ l: Int = 0) -> Int {
        Int(message(UInt32(m), wParam: UInt(bitPattern: w), lParam: l))
    }

    /// Send a message whose lParam is a C string.
    @discardableResult
    func sci(_ m: Int32, _ w: Int = 0, string: String) -> Int {
        string.withCString { sci(m, w, Int(bitPattern: $0)) }
    }

    func text(from start: Int, to end: Int) -> String {
        guard end > start else { return "" }
        var buffer = [CChar](repeating: 0, count: end - start + 1)
        return buffer.withUnsafeMutableBufferPointer { buf -> String in
            var range = Sci_TextRangeFull(chrg: Sci_CharacterRangeFull(cpMin: start, cpMax: end),
                                          lpstrText: buf.baseAddress)
            withUnsafeMutablePointer(to: &range) { sci(SCI_GETTEXTRANGEFULL, 0, Int(bitPattern: $0)) }
            return String(cString: buf.baseAddress!)
        }
    }
}

/// Scintilla colour: 0xTTBBGGRR where TT is our patched-in transparency (0 = opaque).
func sciColor(_ c: NSColor, transparency: Int = 0) -> Int {
    let s = c.usingColorSpace(.sRGB) ?? c
    let r = Int(round(s.redComponent * 255)), g = Int(round(s.greenComponent * 255)), b = Int(round(s.blueComponent * 255))
    return r | (g << 8) | (b << 16) | (transparency << 24)
}

/// Scintilla "ColourAlpha": 0xAABBGGRR with AA = alpha (0xFF = opaque), taken from the colour.
func sciRGBA(_ c: NSColor) -> Int {
    let s = c.usingColorSpace(.sRGB) ?? c
    return sciColor(s) | (Int(round(s.alphaComponent * 255)) << 24)
}

/// One open file (or untitled buffer) and the Scintilla view that edits it.
final class Document: NSObject, ScintillaNotificationProtocol {
    let view: ScintillaView
    private(set) var url: URL?
    private(set) var language: Language = .plainText
    private(set) var encoding: String.Encoding = .utf8
    private var hasBOM = false
    private(set) var lineEnding: LineEnding = .lf
    let untitledNumber: Int

    private(set) var isDirty = false {
        didSet { if isDirty != oldValue { onStateChange?() } }
    }

    /// Title/dirty-state changed.
    var onStateChange: (() -> Void)?
    /// Caret or selection moved.
    var onCaretChange: (() -> Void)?
    /// A macro-recordable editing action happened (only while Scintilla recording is on).
    var onMacroRecord: ((MacroStep) -> Void)?

    /// >0 while LastNote itself drives the editor (auto-indent, highlighting, multi-step
    /// commands): those Scintilla messages must not end up in a recorded macro.
    private var macroSuppression = 0

    @discardableResult
    func quietly<T>(_ body: () -> T) -> T {
        macroSuppression += 1
        defer { macroSuppression -= 1 }
        return body()
    }

    /// Tab colour; nil = use the window tint. Remembered per file.
    var tint: NSColor? {
        didSet {
            if let path = url?.path { AppSettings.shared.setTabTint(tint, forPath: path) }
            onStateChange?()
        }
    }

    /// User-chosen tab label; nil = the file name. Remembered per file. Doesn't rename the file.
    var customName: String? {
        didSet {
            // Trim; blank means "back to the file name". (Assigning here doesn't re-run didSet.)
            let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
            customName = (trimmed?.isEmpty ?? true) ? nil : trimmed
            if let path = url?.path { AppSettings.shared.setTabName(customName, forPath: path) }
            onStateChange?()
        }
    }

    /// The file's own name (or "new N" for an untitled buffer).
    var fileName: String { url?.lastPathComponent ?? "new \(untitledNumber)" }

    /// What the tab shows.
    var displayName: String { customName ?? fileName }

    /// Tab tooltip: the path, plus the file name when the tab has a custom name.
    var tooltip: String? {
        if let customName, let url { return "\(customName) — \(url.path)" }
        return url?.path
    }

    init(untitledNumber: Int) {
        self.untitledNumber = untitledNumber
        view = ScintillaView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        super.init()
        view.delegate = self
        configureEditor()
        applySettings()
    }

    deinit {
        // ScintillaView's delegate is unowned (unsafe_unretained); if the view outlives this
        // document even briefly, a notification would reach freed memory and crash.
        view.delegate = nil
    }

    convenience init(url: URL) throws {
        self.init(untitledNumber: 0)
        try load(from: url)
    }

    // MARK: File I/O

    func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        var text: String
        hasBOM = data.starts(with: [0xEF, 0xBB, 0xBF])
        if let s = String(data: hasBOM ? data.dropFirst(3) : data, encoding: .utf8) {
            text = s
            encoding = .utf8
        } else {
            var converted: NSString?
            var lossy: ObjCBool = false
            let raw = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: &lossy)
            if raw != 0, let converted {
                text = converted as String
                encoding = String.Encoding(rawValue: raw)
            } else {
                text = String(decoding: data, as: UTF8.self)
                encoding = .utf8
            }
        }
        lineEnding = Self.detectLineEnding(text)
        self.url = url
        tint = AppSettings.shared.tabTint(forPath: url.path)
        customName = AppSettings.shared.tabName(forPath: url.path)
        view.sci(SCI_SETEOLMODE, lineEnding.sciMode)
        view.setString(text)
        view.sci(SCI_EMPTYUNDOBUFFER)
        view.sci(SCI_SETSAVEPOINT)
        view.sci(SCI_GOTOPOS, 0)
        isDirty = false
        let firstLine = String(text.prefix(200).split(separator: "\n", maxSplits: 1).first ?? "")
        setLanguage(Language.detect(url: url, firstLine: firstLine))
        onStateChange?()
    }

    func save(to url: URL) throws {
        let text = view.string() ?? ""
        guard var data = text.data(using: encoding) else {
            throw NSError(domain: "LastNote", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The text can't be saved in the file's encoding (\(encodingName)).",
            ])
        }
        if hasBOM && encoding == .utf8 { data.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0) }
        try data.write(to: url, options: .atomic)
        let languageChanged = self.url?.pathExtension != url.pathExtension
        self.url = url
        if let tint { AppSettings.shared.setTabTint(tint, forPath: url.path) }
        if let customName { AppSettings.shared.setTabName(customName, forPath: url.path) }
        view.sci(SCI_SETSAVEPOINT)
        isDirty = false
        if languageChanged || language.name == Language.plainText.name {
            setLanguage(Language.detect(url: url, firstLine: currentFirstLine))
        }
        onStateChange?()
    }

    private var currentFirstLine: String {
        view.text(from: 0, to: view.sci(SCI_GETLINEENDPOSITION, 0))
    }

    var encodingName: String {
        switch encoding {
        case .utf8: return hasBOM ? "UTF-8 BOM" : "UTF-8"
        case .isoLatin1: return "ISO-8859-1"
        case .windowsCP1252: return "Windows-1252"
        case .utf16, .utf16LittleEndian: return "UTF-16 LE"
        case .utf16BigEndian: return "UTF-16 BE"
        case .macOSRoman: return "Mac Roman"
        case .ascii: return "ASCII"
        default: return String.localizedName(of: encoding)
        }
    }

    private static func detectLineEnding(_ text: String) -> LineEnding {
        var lf = 0, crlf = 0, cr = 0
        var prevCR = false
        for u in text.utf8.prefix(1_000_000) {
            if u == 0x0A { if prevCR { crlf += 1; cr -= 1 } else { lf += 1 } }
            if u == 0x0D { cr += 1 }
            prevCR = u == 0x0D
        }
        if crlf > lf && crlf >= cr { return .crlf }
        if cr > lf { return .cr }
        return .lf
    }

    func convertLineEndings(to eol: LineEnding) {
        lineEnding = eol
        view.sci(SCI_SETEOLMODE, eol.sciMode)
        view.sci(SCI_CONVERTEOLS, eol.sciMode)
        onStateChange?()
    }

    // MARK: Configuration

    private func configureEditor() {
        let v = view
        v.sci(SCI_SETCODEPAGE, Int(SC_CP_UTF8))
        v.sci(SCI_SETMULTIPLESELECTION, 1)
        v.sci(SCI_SETADDITIONALSELECTIONTYPING, 1)
        v.sci(SCI_SETMULTIPASTE, Int(SC_MULTIPASTE_EACH))
        v.sci(SCI_SETVIRTUALSPACEOPTIONS, Int(SCVS_RECTANGULARSELECTION))
        v.sci(SCI_SETSCROLLWIDTH, 1)
        v.sci(SCI_SETSCROLLWIDTHTRACKING, 1)
        v.sci(SCI_SETENDATLASTLINE, 0)
        v.sci(SCI_SETCARETLINEVISIBLEALWAYS, 1)
        v.sci(SCI_SETCARETLINELAYER, Int(SC_LAYER_UNDER_TEXT))
        v.sci(SCI_SETSELECTIONLAYER, Int(SC_LAYER_UNDER_TEXT))
        v.sci(SCI_SETCARETWIDTH, 2)
        v.sci(SCI_SETINDENTATIONGUIDES, Int(SC_IV_LOOKBOTH))
        v.sci(SCI_SETMARGINS, 3)

        v.sci(SCI_SETMARGINTYPEN, marginLineNumbers, Int(SC_MARGIN_NUMBER))
        v.sci(SCI_SETMARGINTYPEN, marginBookmarks, Int(SC_MARGIN_SYMBOL))
        v.sci(SCI_SETMARGINMASKN, marginBookmarks, 1 << markerBookmark)
        v.sci(SCI_SETMARGINWIDTHN, marginBookmarks, 14)
        v.sci(SCI_SETMARGINSENSITIVEN, marginBookmarks, 1)
        v.sci(SCI_MARKERDEFINE, markerBookmark, Int(SC_MARK_BOOKMARK))

        v.sci(SCI_SETMARGINTYPEN, marginFolding, Int(SC_MARGIN_SYMBOL))
        v.sci(SCI_SETMARGINMASKN, marginFolding, Int(SC_MASK_FOLDERS))
        v.sci(SCI_SETMARGINWIDTHN, marginFolding, 14)
        v.sci(SCI_SETMARGINSENSITIVEN, marginFolding, 1)
        v.sci(SCI_SETAUTOMATICFOLD, Int(SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE))
        v.sci(SCI_SETFOLDFLAGS, Int(SC_FOLDFLAG_LINEAFTER_CONTRACTED))
        let folderMarkers: [(Int32, Int32)] = [
            (SC_MARKNUM_FOLDEROPEN, SC_MARK_BOXMINUS), (SC_MARKNUM_FOLDER, SC_MARK_BOXPLUS),
            (SC_MARKNUM_FOLDERSUB, SC_MARK_VLINE), (SC_MARKNUM_FOLDERTAIL, SC_MARK_LCORNER),
            (SC_MARKNUM_FOLDEREND, SC_MARK_BOXPLUSCONNECTED), (SC_MARKNUM_FOLDEROPENMID, SC_MARK_BOXMINUSCONNECTED),
            (SC_MARKNUM_FOLDERMIDTAIL, SC_MARK_TCORNER),
        ]
        for (num, symbol) in folderMarkers { v.sci(SCI_MARKERDEFINE, Int(num), Int(symbol)) }

        v.sci(SCI_INDICSETSTYLE, indicatorSmartHighlight, Int(INDIC_ROUNDBOX))
        v.sci(SCI_INDICSETUNDER, indicatorSmartHighlight, 1)
        v.sci(SCI_INDICSETALPHA, indicatorSmartHighlight, 90)
        v.sci(SCI_INDICSETOUTLINEALPHA, indicatorSmartHighlight, 160)
        v.sci(SCI_INDICSETSTYLE, indicatorFind, Int(INDIC_ROUNDBOX))
        v.sci(SCI_INDICSETUNDER, indicatorFind, 1)
        v.sci(SCI_INDICSETALPHA, indicatorFind, 110)
        v.sci(SCI_INDICSETOUTLINEALPHA, indicatorFind, 200)

    }

    /// Re-apply fonts, colours and view options from `AppSettings`.
    func applySettings() {
        let settings = AppSettings.shared
        let theme = Theme.named(settings.theme)
        let v = view
        let font = settings.editorFont

        v.setStringProperty(SCI_STYLESETFONT, parameter: Int(STYLE_DEFAULT), value: font.fontName)
        v.sci(SCI_STYLESETSIZEFRACTIONAL, Int(STYLE_DEFAULT), Int(font.pointSize * 100))
        v.sci(SCI_STYLESETFORE, Int(STYLE_DEFAULT), sciColor(theme.foreground))
        // Text background is always fully clear; the window's tint/background layer shows through.
        v.sci(SCI_STYLESETBACK, Int(STYLE_DEFAULT), sciColor(theme.background, transparency: 255))
        v.sci(SCI_STYLECLEARALL)

        for (style, token) in language.styles {
            let ts = theme.style(token)
            v.sci(SCI_STYLESETFORE, Int(style), sciColor(ts.color))
            v.sci(SCI_STYLESETBOLD, Int(style), ts.bold ? 1 : 0)
            v.sci(SCI_STYLESETITALIC, Int(style), ts.italic ? 1 : 0)
        }

        let gutterTransparency = 255 - Int(round(theme.gutter.alphaComponent * 255))
        v.sci(SCI_STYLESETFORE, Int(STYLE_LINENUMBER), sciColor(theme.lineNumber))
        v.sci(SCI_STYLESETBACK, Int(STYLE_LINENUMBER), sciColor(theme.gutter, transparency: gutterTransparency))
        v.sci(SCI_STYLESETFORE, Int(STYLE_BRACELIGHT), sciColor(theme.braceMatch))
        v.sci(SCI_STYLESETBOLD, Int(STYLE_BRACELIGHT), 1)
        v.sci(SCI_STYLESETFORE, Int(STYLE_BRACEBAD), sciColor(theme.style(.error).color))
        v.sci(SCI_STYLESETFORE, Int(STYLE_INDENTGUIDE), sciColor(theme.whitespace))
        v.sci(SCI_SETFOLDMARGINCOLOUR, 1, sciColor(theme.gutter, transparency: gutterTransparency))
        v.sci(SCI_SETFOLDMARGINHICOLOUR, 1, sciColor(theme.gutter, transparency: gutterTransparency))

        for num in [SC_MARKNUM_FOLDEROPEN, SC_MARKNUM_FOLDER, SC_MARKNUM_FOLDERSUB, SC_MARKNUM_FOLDERTAIL,
                    SC_MARKNUM_FOLDEREND, SC_MARKNUM_FOLDEROPENMID, SC_MARKNUM_FOLDERMIDTAIL] {
            v.sci(SCI_MARKERSETFORETRANSLUCENT, Int(num), sciRGBA(theme.foreground))
            v.sci(SCI_MARKERSETBACKTRANSLUCENT, Int(num), sciRGBA(theme.lineNumber))
            v.sci(SCI_MARKERSETBACKSELECTEDTRANSLUCENT, Int(num), sciRGBA(theme.braceMatch))
        }
        v.sci(SCI_MARKERENABLEHIGHLIGHT, 1)
        v.sci(SCI_MARKERSETFORE, markerBookmark, sciColor(theme.style(.keyword).color))
        v.sci(SCI_MARKERSETBACK, markerBookmark, sciColor(theme.style(.keyword).color))

        v.sci(SCI_SETELEMENTCOLOUR, Int(SC_ELEMENT_CARET), sciRGBA(theme.caret))
        v.sci(SCI_SETELEMENTCOLOUR, Int(SC_ELEMENT_CARET_LINE_BACK), sciRGBA(theme.caretLine))
        v.sci(SCI_SETELEMENTCOLOUR, Int(SC_ELEMENT_SELECTION_BACK), sciRGBA(theme.selection))
        v.sci(SCI_SETELEMENTCOLOUR, Int(SC_ELEMENT_SELECTION_ADDITIONAL_BACK), sciRGBA(theme.selection.withAlphaComponent(0.6)))
        v.sci(SCI_SETELEMENTCOLOUR, Int(SC_ELEMENT_SELECTION_SECONDARY_BACK), sciRGBA(theme.selection.withAlphaComponent(0.5)))
        v.sci(SCI_SETELEMENTCOLOUR, Int(SC_ELEMENT_SELECTION_INACTIVE_BACK), sciRGBA(theme.selection.withAlphaComponent(0.45)))
        v.sci(SCI_SETELEMENTCOLOUR, Int(SC_ELEMENT_WHITE_SPACE), sciRGBA(theme.whitespace))
        v.sci(SCI_INDICSETFORE, indicatorSmartHighlight, sciColor(theme.smartHighlight))
        v.sci(SCI_INDICSETFORE, indicatorFind, sciColor(theme.findHighlight))

        v.sci(SCI_SETTABWIDTH, settings.tabWidth)
        v.sci(SCI_SETUSETABS, settings.useSpaces ? 0 : 1)
        v.sci(SCI_SETWRAPMODE, settings.wordWrap ? Int(SC_WRAP_WORD) : Int(SC_WRAP_NONE))
        v.sci(SCI_SETVIEWWS, settings.showWhitespace ? Int(SCWS_VISIBLEALWAYS) : Int(SCWS_INVISIBLE))
        v.sci(SCI_SETVIEWEOL, settings.showLineEndings ? 1 : 0)
        updateLineNumberMargin()
        v.scrollView.scrollerKnobStyle = settings.theme == .dark ? .light : .dark
    }

    func setLanguage(_ lang: Language) {
        language = lang
        if !SciBridge.setLexer(lang.lexer, on: view) {
            _ = SciBridge.setLexer("null", on: view)
        }
        for (i, words) in lang.keywords.enumerated() {
            view.sci(SCI_SETKEYWORDS, i, string: words)
        }
        view.setLexerProperty("fold", value: "1")
        view.setLexerProperty("fold.compact", value: "0")
        view.setLexerProperty("fold.comment", value: "1")
        for (key, value) in lang.properties { view.setLexerProperty(key, value: value) }
        applySettings()
        view.sci(SCI_COLOURISE, 0, -1)
        onStateChange?()
    }

    private var lineNumberDigits = 0

    private func updateLineNumberMargin() {
        let digits = max(3, String(view.sci(SCI_GETLINECOUNT)).count)
        let width = view.sci(SCI_TEXTWIDTH, Int(STYLE_LINENUMBER), string: String(repeating: "9", count: digits + 1))
        view.sci(SCI_SETMARGINWIDTHN, marginLineNumbers, width)
        lineNumberDigits = digits
    }

    // MARK: Notifications from Scintilla

    func notification(_ notification: UnsafeMutablePointer<SCNotification>!) {
        guard let n = notification?.pointee else { return }
        switch Int32(n.nmhdr.code) {
        case SCN_SAVEPOINTLEFT:
            isDirty = true
        case SCN_SAVEPOINTREACHED:
            isDirty = false
        case SCN_UPDATEUI:
            if n.updated & Int32(SC_UPDATE_SELECTION | SC_UPDATE_CONTENT) != 0 {
                updateBraceMatch()
                if n.updated & Int32(SC_UPDATE_SELECTION) != 0 { updateSmartHighlight() }
                onCaretChange?()
            }
        case SCN_MODIFIED:
            if n.linesAdded != 0, String(view.sci(SCI_GETLINECOUNT)).count != lineNumberDigits {
                updateLineNumberMargin()
            }
        case SCN_CHARADDED:
            if n.ch == 10 || n.ch == 13 { autoIndent() }
        case SCN_MACRORECORD:
            guard macroSuppression == 0, let step = MacroStep.from(notification: n) else { break }
            onMacroRecord?(step)
        case SCN_MARGINCLICK:
            if Int(n.margin) == marginBookmarks {
                toggleBookmark(line: view.sci(SCI_LINEFROMPOSITION, n.position))
            }
        default:
            break
        }
    }

    // MARK: Editing helpers

    /// Copy the previous line's indentation after a newline (also used by macro playback, since
    /// replayed text doesn't fire the "character typed" notification).
    func autoIndent() { quietly { autoIndentNow() } }

    private func autoIndentNow() {
        let v = view
        let pos = v.sci(SCI_GETCURRENTPOS)
        let line = v.sci(SCI_LINEFROMPOSITION, pos)
        guard line > 0, v.sci(SCI_GETSELECTIONS) == 1 else { return }
        let indent = v.sci(SCI_GETLINEINDENTATION, line - 1)
        guard indent > 0 else { return }
        v.sci(SCI_SETLINEINDENTATION, line, indent)
        v.sci(SCI_GOTOPOS, v.sci(SCI_GETLINEINDENTPOSITION, line))
    }

    private func updateBraceMatch() { quietly { updateBraceMatchNow() } }

    private func updateBraceMatchNow() {
        let v = view
        let pos = v.sci(SCI_GETCURRENTPOS)
        let braces: Set<Int> = Set("()[]{}".utf8.map(Int.init))
        var bracePos = -1
        if pos > 0, braces.contains(v.sci(SCI_GETCHARAT, pos - 1)) { bracePos = pos - 1 }
        else if braces.contains(v.sci(SCI_GETCHARAT, pos)) { bracePos = pos }
        if bracePos >= 0 {
            let match = v.sci(SCI_BRACEMATCH, bracePos, 0)
            if match >= 0 { v.sci(SCI_BRACEHIGHLIGHT, bracePos, match) }
            else { v.sci(SCI_BRACEBADLIGHT, bracePos) }
        } else {
            v.sci(SCI_BRACEHIGHLIGHT, -1, -1)
        }
    }

    /// Notepad++ "smart highlighting": selecting a whole word marks its other occurrences.
    private func updateSmartHighlight() { quietly { updateSmartHighlightNow() } }

    private func updateSmartHighlightNow() {
        let v = view
        let length = v.sci(SCI_GETLENGTH)
        v.sci(SCI_SETINDICATORCURRENT, indicatorSmartHighlight)
        v.sci(SCI_INDICATORCLEARRANGE, 0, length)
        let start = v.sci(SCI_GETSELECTIONSTART), end = v.sci(SCI_GETSELECTIONEND)
        guard end > start, end - start < 200, v.sci(SCI_GETSELECTIONS) == 1, length < 5_000_000,
              v.sci(SCI_WORDSTARTPOSITION, start, 1) == start, v.sci(SCI_WORDENDPOSITION, end - 1, 1) == end,
              v.sci(SCI_LINEFROMPOSITION, start) == v.sci(SCI_LINEFROMPOSITION, end)
        else { return }
        let word = v.text(from: start, to: end)
        guard !word.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let savedStart = v.sci(SCI_GETTARGETSTART), savedEnd = v.sci(SCI_GETTARGETEND)
        v.sci(SCI_SETSEARCHFLAGS, Int(SCFIND_MATCHCASE | SCFIND_WHOLEWORD))
        var from = 0
        var count = 0
        while count < 5000 {
            v.sci(SCI_SETTARGETRANGE, from, length)
            let found = v.sci(SCI_SEARCHINTARGET, word.utf8.count, string: word)
            if found < 0 { break }
            let foundEnd = v.sci(SCI_GETTARGETEND)
            if found != start { v.sci(SCI_INDICATORFILLRANGE, found, foundEnd - found) }
            from = max(foundEnd, found + 1)
            count += 1
        }
        v.sci(SCI_SETTARGETRANGE, savedStart, savedEnd)
    }

    func toggleBookmark(line: Int? = nil) {
        let l = line ?? view.sci(SCI_LINEFROMPOSITION, view.sci(SCI_GETCURRENTPOS))
        if view.sci(SCI_MARKERGET, l) & (1 << markerBookmark) != 0 {
            view.sci(SCI_MARKERDELETE, l, markerBookmark)
        } else {
            view.sci(SCI_MARKERADD, l, markerBookmark)
        }
    }

    func gotoBookmark(forward: Bool) {
        let v = view
        let current = v.sci(SCI_LINEFROMPOSITION, v.sci(SCI_GETCURRENTPOS))
        let mask = 1 << markerBookmark
        var line = forward ? v.sci(SCI_MARKERNEXT, current + 1, mask) : v.sci(SCI_MARKERPREVIOUS, current - 1, mask)
        if line < 0 {  // wrap around
            line = forward ? v.sci(SCI_MARKERNEXT, 0, mask) : v.sci(SCI_MARKERPREVIOUS, v.sci(SCI_GETLINECOUNT), mask)
        }
        if line >= 0 { gotoLine(line) }
    }

    func gotoLine(_ line: Int) {
        view.sci(SCI_ENSUREVISIBLEENFORCEPOLICY, line)
        view.sci(SCI_GOTOLINE, line)
        view.sci(SCI_VERTICALCENTRECARET)
    }

    /// Comment or uncomment the selected lines with the language's line-comment prefix.
    func toggleLineComment() {
        guard let prefix = language.lineComment else { NSSound.beep(); return }
        let v = view
        let firstLine = v.sci(SCI_LINEFROMPOSITION, v.sci(SCI_GETSELECTIONSTART))
        var lastLine = v.sci(SCI_LINEFROMPOSITION, v.sci(SCI_GETSELECTIONEND))
        if lastLine > firstLine, v.sci(SCI_GETSELECTIONEND) == v.sci(SCI_POSITIONFROMLINE, lastLine) { lastLine -= 1 }
        let lines = Array(firstLine...lastLine)
        let nonBlank = lines.filter { v.sci(SCI_GETLINEINDENTPOSITION, $0) < v.sci(SCI_GETLINEENDPOSITION, $0) }
        func hasPrefix(_ l: Int) -> Bool {
            let p = v.sci(SCI_GETLINEINDENTPOSITION, l)
            return v.text(from: p, to: min(p + prefix.utf8.count, v.sci(SCI_GETLINEENDPOSITION, l))) == prefix
        }
        let uncomment = !nonBlank.isEmpty && nonBlank.allSatisfy(hasPrefix)
        let column = nonBlank.map { v.sci(SCI_GETLINEINDENTATION, $0) }.min() ?? 0
        v.sci(SCI_BEGINUNDOACTION)
        for l in nonBlank.reversed() {
            if uncomment {
                let p = v.sci(SCI_GETLINEINDENTPOSITION, l)
                var len = prefix.utf8.count
                if v.sci(SCI_GETCHARAT, p + len) == 32 { len += 1 }
                v.sci(SCI_DELETERANGE, p, len)
            } else {
                let p = v.sci(SCI_FINDCOLUMN, l, column)
                v.sci(SCI_INSERTTEXT, p, string: prefix + " ")
            }
        }
        v.sci(SCI_ENDUNDOACTION)
    }

    func trimTrailingWhitespace() {
        let v = view
        v.sci(SCI_BEGINUNDOACTION)
        for line in (0..<v.sci(SCI_GETLINECOUNT)).reversed() {
            let start = v.sci(SCI_POSITIONFROMLINE, line)
            let end = v.sci(SCI_GETLINEENDPOSITION, line)
            var p = end
            while p > start, [9, 32].contains(v.sci(SCI_GETCHARAT, p - 1)) { p -= 1 }
            if p < end { v.sci(SCI_DELETERANGE, p, end - p) }
        }
        v.sci(SCI_ENDUNDOACTION)
    }

    func sortLines(descending: Bool) {
        let v = view
        let firstLine = v.sci(SCI_LINEFROMPOSITION, v.sci(SCI_GETSELECTIONSTART))
        var lastLine = v.sci(SCI_LINEFROMPOSITION, v.sci(SCI_GETSELECTIONEND))
        if firstLine == lastLine { lastLine = v.sci(SCI_GETLINECOUNT) - 1 }
        let start = v.sci(SCI_POSITIONFROMLINE, firstLine)
        let firstSelected = firstLine
        let end = v.sci(SCI_GETLINEENDPOSITION, lastLine)
        let eol = lineEnding == .crlf ? "\r\n" : lineEnding == .cr ? "\r" : "\n"
        var lines = v.text(from: start, to: end).components(separatedBy: eol)
        lines.sort { descending ? $0.localizedStandardCompare($1) == .orderedDescending : $0.localizedStandardCompare($1) == .orderedAscending }
        v.sci(SCI_SETTARGETRANGE, start, end)
        v.sci(SCI_REPLACETARGET, -1, string: lines.joined(separator: eol))
        v.sci(SCI_SETSEL, v.sci(SCI_POSITIONFROMLINE, firstSelected), v.sci(SCI_GETLINEENDPOSITION, lastLine))
    }

    // MARK: Status

    struct CaretInfo {
        var line: Int, column: Int, selectedChars: Int, selectedLines: Int, lineCount: Int, length: Int
    }

    var caretInfo: CaretInfo {
        let v = view
        let pos = v.sci(SCI_GETCURRENTPOS)
        let start = v.sci(SCI_GETSELECTIONSTART), end = v.sci(SCI_GETSELECTIONEND)
        let selLines = end > start ? v.sci(SCI_LINEFROMPOSITION, end) - v.sci(SCI_LINEFROMPOSITION, start) + 1 : 0
        return CaretInfo(line: v.sci(SCI_LINEFROMPOSITION, pos) + 1,
                         column: v.sci(SCI_GETCOLUMN, pos) + 1,
                         selectedChars: v.sci(SCI_COUNTCHARACTERS, start, end),
                         selectedLines: selLines,
                         lineCount: v.sci(SCI_GETLINECOUNT),
                         length: v.sci(SCI_GETLENGTH))
    }
}
