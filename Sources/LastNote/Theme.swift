import AppKit

/// Semantic token categories. Each language maps its lexer's style numbers onto these.
enum Token {
    case plain, comment, docComment, keyword, keyword2, type, function, string, number,
         op, preprocessor, tag, attribute, variable, regex, error, heading, emphasis,
         added, removed
}

struct TokenStyle {
    var color: NSColor
    var bold = false
    var italic = false
}

struct Theme {
    let kind: ThemeKind
    let background: NSColor
    let foreground: NSColor
    let caret: NSColor
    let caretLine: NSColor
    let selection: NSColor
    let lineNumber: NSColor
    let gutter: NSColor
    let whitespace: NSColor
    let braceMatch: NSColor
    let smartHighlight: NSColor
    let findHighlight: NSColor
    let chrome: NSColor        // tab bar / status bar overlay
    let chromeText: NSColor
    let separator: NSColor
    let tokens: [Token: TokenStyle]

    func style(_ t: Token) -> TokenStyle { tokens[t] ?? TokenStyle(color: foreground) }

    static func named(_ kind: ThemeKind) -> Theme { kind == .dark ? .dark : .light }

    static let dark = Theme(
        kind: .dark,
        background: hex("#1E1E1E"),
        foreground: hex("#D4D4D4"),
        caret: hex("#AEAFAD"),
        caretLine: NSColor.white.withAlphaComponent(0.06),
        selection: hex("#264F78").withAlphaComponent(0.85),
        lineNumber: hex("#858585"),
        gutter: NSColor.white.withAlphaComponent(0.03),
        whitespace: hex("#404040"),
        braceMatch: hex("#FFD700"),
        smartHighlight: hex("#3A6EA5"),
        findHighlight: hex("#E2A03F"),
        chrome: NSColor.black.withAlphaComponent(0.25),
        chromeText: hex("#CCCCCC"),
        separator: NSColor.white.withAlphaComponent(0.08),
        tokens: [
            .comment: TokenStyle(color: hex("#6A9955"), italic: true),
            .docComment: TokenStyle(color: hex("#608B4E"), italic: true),
            .keyword: TokenStyle(color: hex("#569CD6"), bold: true),
            .keyword2: TokenStyle(color: hex("#C586C0")),
            .type: TokenStyle(color: hex("#4EC9B0")),
            .function: TokenStyle(color: hex("#DCDCAA")),
            .string: TokenStyle(color: hex("#CE9178")),
            .number: TokenStyle(color: hex("#B5CEA8")),
            .op: TokenStyle(color: hex("#D4D4D4")),
            .preprocessor: TokenStyle(color: hex("#C586C0")),
            .tag: TokenStyle(color: hex("#569CD6")),
            .attribute: TokenStyle(color: hex("#9CDCFE")),
            .variable: TokenStyle(color: hex("#9CDCFE")),
            .regex: TokenStyle(color: hex("#D16969")),
            .error: TokenStyle(color: hex("#F44747")),
            .heading: TokenStyle(color: hex("#569CD6"), bold: true),
            .emphasis: TokenStyle(color: hex("#D7BA7D"), italic: true),
            .added: TokenStyle(color: hex("#6A9955")),
            .removed: TokenStyle(color: hex("#F44747")),
        ])

    // Close to Notepad++'s default colours.
    static let light = Theme(
        kind: .light,
        background: hex("#FFFFFF"),
        foreground: hex("#000000"),
        caret: hex("#000000"),
        caretLine: hex("#E8E8FF").withAlphaComponent(0.8),
        selection: hex("#C0C0C0").withAlphaComponent(0.9),
        lineNumber: hex("#808080"),
        gutter: NSColor.black.withAlphaComponent(0.04),
        whitespace: hex("#C0C0C0"),
        braceMatch: hex("#FF0000"),
        smartHighlight: hex("#00FF00"),
        findHighlight: hex("#FF8000"),
        chrome: NSColor.white.withAlphaComponent(0.35),
        chromeText: hex("#333333"),
        separator: NSColor.black.withAlphaComponent(0.1),
        tokens: [
            .comment: TokenStyle(color: hex("#008000")),
            .docComment: TokenStyle(color: hex("#008080")),
            .keyword: TokenStyle(color: hex("#0000FF"), bold: true),
            .keyword2: TokenStyle(color: hex("#8000FF")),
            .type: TokenStyle(color: hex("#8000FF")),
            .function: TokenStyle(color: hex("#795E26")),
            .string: TokenStyle(color: hex("#808080")),
            .number: TokenStyle(color: hex("#FF8000")),
            .op: TokenStyle(color: hex("#000080"), bold: true),
            .preprocessor: TokenStyle(color: hex("#804000")),
            .tag: TokenStyle(color: hex("#0000FF")),
            .attribute: TokenStyle(color: hex("#FF0000")),
            .variable: TokenStyle(color: hex("#001080")),
            .regex: TokenStyle(color: hex("#8000FF")),
            .error: TokenStyle(color: hex("#FF0000")),
            .heading: TokenStyle(color: hex("#0000FF"), bold: true),
            .emphasis: TokenStyle(color: hex("#804000"), italic: true),
            .added: TokenStyle(color: hex("#008000")),
            .removed: TokenStyle(color: hex("#FF0000")),
        ])
}

private func hex(_ s: String) -> NSColor { NSColor(hex: s)! }
