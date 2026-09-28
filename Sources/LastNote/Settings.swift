import AppKit
import Combine

enum ThemeKind: String, CaseIterable, Identifiable {
    case dark, light
    var id: String { rawValue }
    var title: String { self == .dark ? "Dark" : "Light" }
}

/// User preferences, persisted in UserDefaults. Every change posts `AppSettings.didChange`
/// so windows can re-apply appearance live.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let didChange = Notification.Name("AppSettingsDidChange")

    private let defaults = UserDefaults.standard

    /// When off the window is a normal solid window. When on, `opacity`, `blurEnabled`
    /// and `tintColor` control what shows behind the text.
    @Published var transparencyEnabled: Bool { didSet { save("transparencyEnabled", transparencyEnabled) } }
    /// 0.1 (almost see-through) ... 1.0 (solid tint).
    @Published var opacity: Double { didSet { save("opacity", opacity) } }
    /// Frosted-glass blur of whatever is behind the window.
    @Published var blurEnabled: Bool { didSet { save("blurEnabled", blurEnabled) } }
    @Published var tintColor: NSColor { didSet { save("tintColor", tintColor.hexString) } }

    @Published var theme: ThemeKind { didSet { save("theme", theme.rawValue) } }
    @Published var fontName: String { didSet { save("fontName", fontName) } }
    @Published var fontSize: Double { didSet { save("fontSize", fontSize) } }
    @Published var consoleFontSize: Double { didSet { save("consoleFontSize", consoleFontSize) } }
    /// Console font family; "" = same as the editor font.
    @Published var consoleFontName: String { didSet { save("consoleFontName", consoleFontName) } }
    /// Console text colour; nil = the theme's text colour.
    @Published var consoleTextColor: NSColor? { didSet { save("consoleTextColor", consoleTextColor?.hexString ?? "") } }
    /// Console background; nil = the window tint. Console-tab colours still override it per tab.
    @Published var consoleBackgroundColor: NSColor? { didSet { save("consoleBackgroundColor", consoleBackgroundColor?.hexString ?? "") } }
    @Published var wordWrap: Bool { didSet { save("wordWrap", wordWrap) } }
    @Published var showWhitespace: Bool { didSet { save("showWhitespace", showWhitespace) } }
    @Published var showLineEndings: Bool { didSet { save("showLineEndings", showLineEndings) } }
    @Published var tabWidth: Int { didSet { save("tabWidth", tabWidth) } }
    /// Glow around the focused area (editor or console) so it's obvious where typing goes.
    @Published var focusGlowEnabled: Bool { didSet { save("focusGlowEnabled", focusGlowEnabled) } }
    /// 0.1 (faint) ... 1.0 (strong).
    @Published var focusGlowOpacity: Double { didSet { save("focusGlowOpacity", focusGlowOpacity) } }
    /// nil = automatic (white on dark text colours, blue on light).
    @Published var focusGlowColor: NSColor? { didSet { save("focusGlowColor", focusGlowColor?.hexString ?? "") } }
    @Published var useSpaces: Bool { didSet { save("useSpaces", useSpaces) } }

    private init() {
        defaults.register(defaults: [
            "transparencyEnabled": false,
            "opacity": 0.8,
            "blurEnabled": true,
            "tintColor": "#1B1F27",
            "theme": ThemeKind.dark.rawValue,
            "fontName": "Menlo",
            "fontSize": 13.0,
            "consoleFontSize": 12.0,
            "consoleFontName": "",
            "wordWrap": false,
            "showWhitespace": false,
            "showLineEndings": false,
            "tabWidth": 4,
            "useSpaces": true,
            "focusGlowEnabled": true,
            "focusGlowOpacity": 0.4,
        ])
        transparencyEnabled = defaults.bool(forKey: "transparencyEnabled")
        opacity = defaults.double(forKey: "opacity")
        blurEnabled = defaults.bool(forKey: "blurEnabled")
        tintColor = NSColor(hex: defaults.string(forKey: "tintColor") ?? "") ?? NSColor(hex: "#1B1F27")!
        theme = ThemeKind(rawValue: defaults.string(forKey: "theme") ?? "") ?? .dark
        fontName = defaults.string(forKey: "fontName") ?? "Menlo"
        fontSize = defaults.double(forKey: "fontSize")
        consoleFontSize = defaults.double(forKey: "consoleFontSize")
        consoleFontName = defaults.string(forKey: "consoleFontName") ?? ""
        consoleTextColor = NSColor(hex: defaults.string(forKey: "consoleTextColor") ?? "")
        consoleBackgroundColor = NSColor(hex: defaults.string(forKey: "consoleBackgroundColor") ?? "")
        wordWrap = defaults.bool(forKey: "wordWrap")
        showWhitespace = defaults.bool(forKey: "showWhitespace")
        showLineEndings = defaults.bool(forKey: "showLineEndings")
        tabWidth = defaults.integer(forKey: "tabWidth")
        focusGlowEnabled = defaults.bool(forKey: "focusGlowEnabled")
        focusGlowOpacity = defaults.double(forKey: "focusGlowOpacity")
        focusGlowColor = NSColor(hex: defaults.string(forKey: "focusGlowColor") ?? "")
        useSpaces = defaults.bool(forKey: "useSpaces")
    }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        // Post after the @Published value has been stored.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: AppSettings.didChange, object: self)
        }
    }

    /// Per-file tab colours, remembered by path.
    func tabTint(forPath path: String) -> NSColor? {
        (defaults.dictionary(forKey: "tabTints") as? [String: String])?[path].flatMap { NSColor(hex: $0) }
    }

    func setTabTint(_ color: NSColor?, forPath path: String) {
        var map = defaults.dictionary(forKey: "tabTints") as? [String: String] ?? [:]
        map[path] = color?.hexString
        defaults.set(map, forKey: "tabTints")
    }

    /// Per-file custom tab names, remembered by path.
    func tabName(forPath path: String) -> String? {
        (defaults.dictionary(forKey: "tabNames") as? [String: String])?[path]
    }

    func setTabName(_ name: String?, forPath path: String) {
        var map = defaults.dictionary(forKey: "tabNames") as? [String: String] ?? [:]
        map[path] = name
        defaults.set(map, forKey: "tabNames")
    }

    var effectiveFocusGlowColor: NSColor {
        focusGlowColor ?? (theme == .dark ? .white : NSColor(hex: "#1E6FD9")!)
    }

    var editorFont: NSFont {
        Self.font(family: fontName, size: fontSize)
    }

    private static func font(family: String, size: Double) -> NSFont {
        NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
            ?? NSFont(name: family, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    var consoleFont: NSFont {
        Self.font(family: consoleFontName.isEmpty ? fontName : consoleFontName, size: consoleFontSize)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }

    /// Relative luminance, used to tell whether a tint is light or dark.
    var luminance: CGFloat {
        let c = usingColorSpace(.sRGB) ?? self
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }
}
