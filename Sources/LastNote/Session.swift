import AppKit

/// A named snapshot of the workspace: window and console layout, transparency/colours/fonts,
/// and optionally the open files and console tabs (with their names and colours).
struct SavedSession: Codable, Equatable {
    struct File: Codable, Equatable {
        var path: String
        var name: String?
        var tint: String?
    }

    struct ConsoleTab: Codable, Equatable {
        var name: String?
        var tint: String?
    }

    /// Appearance settings captured with the session.
    struct Look: Codable, Equatable {
        var transparencyEnabled: Bool
        var opacity: Double
        var blurEnabled: Bool
        var tintColor: String
        var theme: String
        var focusGlowEnabled: Bool
        var focusGlowOpacity: Double
        var focusGlowColor: String?
        var fontName: String
        var fontSize: Double
        var wordWrap: Bool
        var consoleFontName: String
        var consoleFontSize: Double
        var consoleTextColor: String?
        var consoleBackgroundColor: String?
    }

    var name: String
    var savedAt: Date
    var windowFrame: String
    var consoleVisible: Bool
    var consoleHeight: Double
    var look: Look
    /// nil when the session was saved without its tabs (layout and colours only).
    var files: [File]?
    var selectedFile: String?
    var consoleTabs: [ConsoleTab]?

    var includesTabs: Bool { files != nil }
}

extension AppSettings {
    func snapshot() -> SavedSession.Look {
        .init(transparencyEnabled: transparencyEnabled, opacity: opacity, blurEnabled: blurEnabled,
              tintColor: tintColor.hexString, theme: theme.rawValue,
              focusGlowEnabled: focusGlowEnabled, focusGlowOpacity: focusGlowOpacity, focusGlowColor: focusGlowColor?.hexString,
              fontName: fontName, fontSize: fontSize, wordWrap: wordWrap,
              consoleFontName: consoleFontName, consoleFontSize: consoleFontSize,
              consoleTextColor: consoleTextColor?.hexString, consoleBackgroundColor: consoleBackgroundColor?.hexString)
    }

    func apply(_ look: SavedSession.Look) {
        transparencyEnabled = look.transparencyEnabled
        opacity = look.opacity
        blurEnabled = look.blurEnabled
        if let c = NSColor(hex: look.tintColor) { tintColor = c }
        theme = ThemeKind(rawValue: look.theme) ?? theme
        focusGlowEnabled = look.focusGlowEnabled
        focusGlowOpacity = look.focusGlowOpacity
        focusGlowColor = look.focusGlowColor.flatMap { NSColor(hex: $0) }
        fontName = look.fontName
        fontSize = look.fontSize
        wordWrap = look.wordWrap
        consoleFontName = look.consoleFontName
        consoleFontSize = look.consoleFontSize
        consoleTextColor = look.consoleTextColor.flatMap { NSColor(hex: $0) }
        consoleBackgroundColor = look.consoleBackgroundColor.flatMap { NSColor(hex: $0) }
    }
}

/// Saved sessions, persisted in UserDefaults.
final class SessionStore {
    static let shared = SessionStore()
    static let didChange = Notification.Name("SessionStoreDidChange")

    private let defaultsKey = "savedSessions"
    private(set) var sessions: [SavedSession] = []
    /// Name of the session loaded or saved last (shown with a checkmark).
    private(set) var activeName: String? {
        get { UserDefaults.standard.string(forKey: "activeSession") }
        set { UserDefaults.standard.set(newValue, forKey: "activeSession") }
    }

    init() { reload() }

    func reload() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let list = try? JSONDecoder().decode([SavedSession].self, from: data) {
            sessions = list
        } else {
            sessions = []
        }
    }

    func session(named name: String) -> SavedSession? { sessions.first { $0.name == name } }

    func save(_ session: SavedSession) {
        if let i = sessions.firstIndex(where: { $0.name == session.name }) {
            sessions[i] = session
        } else {
            sessions.append(session)
        }
        activeName = session.name
        persist()
    }

    func delete(name: String) {
        sessions.removeAll { $0.name == name }
        if activeName == name { activeName = nil }
        persist()
    }

    func markActive(_ name: String) {
        activeName = name
        changed()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sessions) { UserDefaults.standard.set(data, forKey: defaultsKey) }
        changed()
    }

    private func changed() {
        NotificationCenter.default.post(name: SessionStore.didChange, object: self)
    }
}

/// The Sessions menu: save, the saved sessions (checkmark on the active one), delete.
final class SessionMenuController: NSObject {
    static let shared = SessionMenuController()
    let menu = NSMenu(title: "Sessions")
    private var observer: NSObjectProtocol?

    private override init() {
        super.init()
        rebuild()
        observer = NotificationCenter.default.addObserver(forName: SessionStore.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        }
    }

    func rebuild() {
        fill(menu)
    }

    /// A fresh copy of the menu (for popping up from the icon bar).
    func makeMenu() -> NSMenu {
        let m = NSMenu(title: "Sessions")
        fill(m)
        return m
    }

    private func fill(_ m: NSMenu) {
        m.removeAllItems()
        m.addItem(NSMenuItem(title: "Save Session…", action: #selector(MainWindowController.saveSession(_:)), keyEquivalent: ""))
        m.addItem(.separator())
        let store = SessionStore.shared
        if store.sessions.isEmpty {
            let none = NSMenuItem(title: "No saved sessions", action: nil, keyEquivalent: "")
            none.isEnabled = false
            m.addItem(none)
            return
        }
        let header = NSMenuItem(title: "Load Session", action: nil, keyEquivalent: "")
        header.isEnabled = false
        m.addItem(header)
        for s in store.sessions.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let item = NSMenuItem(title: s.name, action: #selector(MainWindowController.loadSession(_:)), keyEquivalent: "")
            item.representedObject = s.name
            item.state = store.activeName == s.name ? .on : .off
            item.indentationLevel = 1
            item.toolTip = s.includesTabs ? "Layout, colours, \(s.files?.count ?? 0) file(s) and \(s.consoleTabs?.count ?? 0) console tab(s)"
                                          : "Layout and colours only"
            m.addItem(item)
        }
        m.addItem(.separator())
        let delete = NSMenuItem(title: "Delete Session", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Delete Session")
        for s in store.sessions {
            let i = NSMenuItem(title: s.name, action: #selector(MainWindowController.deleteSession(_:)), keyEquivalent: "")
            i.representedObject = s.name
            sub.addItem(i)
        }
        delete.submenu = sub
        m.addItem(delete)
    }
}
