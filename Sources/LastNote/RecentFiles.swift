import AppKit

/// LastNote's own "Open Recent" list: newest first, up to 20 files, persisted in UserDefaults so it
/// survives quitting. (AppKit only fills an Open Recent menu that comes from a nib, and LastNote
/// builds its menus in code, so the system list never showed up.)
final class RecentFiles {
    static let shared = RecentFiles()
    static let didChange = Notification.Name("RecentFilesDidChange")
    static let limit = 20

    private let defaultsKey: String
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, key: String = "recentFiles") {
        self.defaults = defaults
        self.defaultsKey = key
    }

    /// Paths, most recent first.
    var paths: [String] { defaults.stringArray(forKey: defaultsKey) ?? [] }

    /// Record that a file was opened or saved: it moves to the top, and the list is trimmed.
    func note(_ url: URL) {
        let path = url.standardizedFileURL.path
        var list = paths.filter { $0 != path }
        list.insert(path, at: 0)
        if list.count > RecentFiles.limit { list.removeLast(list.count - RecentFiles.limit) }
        defaults.set(list, forKey: defaultsKey)
        NotificationCenter.default.post(name: RecentFiles.didChange, object: self)
        // Also tell macOS, so the file shows in the Dock menu and system Recent Items.
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func clear() {
        defaults.removeObject(forKey: defaultsKey)
        NotificationCenter.default.post(name: RecentFiles.didChange, object: self)
    }

    func remove(_ path: String) {
        defaults.set(paths.filter { $0 != path }, forKey: defaultsKey)
        NotificationCenter.default.post(name: RecentFiles.didChange, object: self)
    }
}

/// Fills the File ▸ Open Recent submenu each time it opens.
final class RecentFilesMenuController: NSObject, NSMenuDelegate {
    static let shared = RecentFilesMenuController()
    let menu = NSMenu(title: "Open Recent")
    var store = RecentFiles.shared

    private override init() {
        super.init()
        menu.delegate = self
        rebuild()
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }

    func rebuild() {
        menu.removeAllItems()
        let paths = store.paths
        if paths.isEmpty {
            let none = NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        // Names that appear more than once get their folder in the title to tell them apart.
        let names = paths.map { ($0 as NSString).lastPathComponent }
        for path in paths {
            let name = (path as NSString).lastPathComponent
            let folder = ((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
            let exists = FileManager.default.fileExists(atPath: path)
            let duplicate = names.filter { $0 == name }.count > 1
            let item = NSMenuItem(title: duplicate ? "\(name) — \(folder)" : name,
                                  action: exists ? #selector(MainWindowController.openRecentFile(_:)) : nil, keyEquivalent: "")
            item.representedObject = path
            item.toolTip = exists ? (path as NSString).abbreviatingWithTildeInPath : "\((path as NSString).abbreviatingWithTildeInPath) (not found)"
            item.isEnabled = exists
            if #available(macOS 14.4, *), !duplicate { item.subtitle = folder }
            let icon = exists ? NSWorkspace.shared.icon(forFile: path) : NSImage(systemSymbolName: "questionmark.square.dashed", accessibilityDescription: "Missing")!
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearMenu(_:)), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !paths.isEmpty
        menu.addItem(clear)
    }

    @objc func clearMenu(_ sender: Any?) {
        store.clear()
        NSDocumentController.shared.clearRecentDocuments(nil)
        rebuild()
    }
}
