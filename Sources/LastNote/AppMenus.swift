import AppKit

/// The main menu, built in code. Actions go down the responder chain (nil target), so the
/// editor handles Undo/Copy/Paste and MainWindowController handles the rest.
enum AppMenus {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(searchMenu()))
        main.addItem(submenu(viewMenu()))
        let lang = languageMenu()
        lang.title = "Language"
        main.addItem(submenu(lang))
        main.addItem(submenu(runMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        i.target = target
        return i
    }

    private static func fn(_ key: Int) -> String { String(Character(UnicodeScalar(key)!)) }

    private static func appMenu() -> NSMenu {
        let m = NSMenu(title: "LastNote")
        m.addItem(item("About LastNote", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        m.addItem(.separator())
        m.addItem(item("Settings…", #selector(AppDelegate.showSettings(_:)), ","))
        m.addItem(.separator())
        let services = NSMenu(title: "Services")
        m.addItem(submenu(services))
        NSApp.servicesMenu = services
        m.addItem(.separator())
        m.addItem(item("Hide LastNote", #selector(NSApplication.hide(_:)), "h"))
        m.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        m.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        m.addItem(.separator())
        m.addItem(item("Quit LastNote", #selector(NSApplication.terminate(_:)), "q"))
        return m
    }

    private static func fileMenu() -> NSMenu {
        let m = NSMenu(title: "File")
        m.addItem(item("New", #selector(MainWindowController.newDocument(_:)), "n"))
        m.addItem(item("Open…", #selector(MainWindowController.openDocument(_:)), "o"))
        let recent = NSMenu(title: "Open Recent")
        recent.addItem(item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:))))
        m.addItem(submenu(recent))
        m.addItem(item("Reload from Disk", #selector(MainWindowController.reloadFromDisk(_:))))
        m.addItem(.separator())
        m.addItem(item("Save", #selector(MainWindowController.saveDocument(_:)), "s"))
        m.addItem(item("Save As…", #selector(MainWindowController.saveDocumentAs(_:)), "s", [.command, .shift]))
        m.addItem(item("Save All", #selector(MainWindowController.saveAllDocuments(_:)), "s", [.command, .option]))
        m.addItem(.separator())
        m.addItem(item("Reveal in Finder", #selector(MainWindowController.revealInFinder(_:))))
        m.addItem(item("Copy File Path", #selector(MainWindowController.copyFilePath(_:))))
        m.addItem(.separator())
        m.addItem(item("Rename Tab…", #selector(MainWindowController.renameTab(_:)), "r", [.command, .shift]))
        m.addItem(item("Close Tab", #selector(MainWindowController.closeTab(_:)), "w"))
        return m
    }

    private static func editMenu() -> NSMenu {
        let m = NSMenu(title: "Edit")
        m.addItem(item("Undo", Selector(("undo:")), "z"))
        m.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        m.addItem(.separator())
        m.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        m.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        m.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        m.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        m.addItem(.separator())
        m.addItem(item("Toggle Comment", #selector(MainWindowController.toggleComment(_:)), "/"))
        m.addItem(item("Duplicate Line / Selection", #selector(MainWindowController.duplicateLine(_:)), "d"))
        m.addItem(item("Delete Line", #selector(MainWindowController.deleteLine(_:)), "k", [.command, .shift]))
        m.addItem(item("Move Line Up", #selector(MainWindowController.moveLinesUp(_:)), fn(NSUpArrowFunctionKey), [.command, .option]))
        m.addItem(item("Move Line Down", #selector(MainWindowController.moveLinesDown(_:)), fn(NSDownArrowFunctionKey), [.command, .option]))
        m.addItem(item("Join Lines", #selector(MainWindowController.joinLines(_:)), "j", [.command, .control]))
        m.addItem(.separator())
        m.addItem(item("UPPERCASE", #selector(MainWindowController.uppercaseSelection(_:)), "u", [.command, .shift]))
        m.addItem(item("lowercase", #selector(MainWindowController.lowercaseSelection(_:)), "u", [.command, .option]))
        m.addItem(item("Trim Trailing Whitespace", #selector(MainWindowController.trimTrailingWhitespace(_:))))
        m.addItem(item("Sort Lines Ascending", #selector(MainWindowController.sortLinesAscending(_:))))
        m.addItem(item("Sort Lines Descending", #selector(MainWindowController.sortLinesDescending(_:))))
        m.addItem(.separator())
        let eol = eolMenu()
        eol.title = "EOL Conversion"
        m.addItem(submenu(eol))
        return m
    }

    static func eolMenu() -> NSMenu {
        let m = NSMenu(title: "Line Endings")
        for eol in [LineEnding.crlf, .lf, .cr] {
            let i = item(eol.title, #selector(MainWindowController.convertEOL(_:)))
            i.representedObject = eol.rawValue
            m.addItem(i)
        }
        return m
    }

    private static func searchMenu() -> NSMenu {
        let m = NSMenu(title: "Search")
        m.addItem(item("Find…", #selector(MainWindowController.showFind(_:)), "f"))
        m.addItem(item("Replace…", #selector(MainWindowController.showReplace(_:)), "f", [.command, .option]))
        m.addItem(item("Find Next", #selector(MainWindowController.findNextMatch(_:)), "g"))
        m.addItem(item("Find Previous", #selector(MainWindowController.findPreviousMatch(_:)), "g", [.command, .shift]))
        m.addItem(item("Use Selection for Find", #selector(MainWindowController.useSelectionForFind(_:)), "e"))
        m.addItem(.separator())
        m.addItem(item("Go to Line…", #selector(MainWindowController.goToLine(_:)), "l"))
        m.addItem(.separator())
        m.addItem(item("Toggle Bookmark", #selector(MainWindowController.toggleBookmark(_:)), fn(NSF2FunctionKey), .command))
        m.addItem(item("Next Bookmark", #selector(MainWindowController.nextBookmark(_:)), fn(NSF2FunctionKey), []))
        m.addItem(item("Previous Bookmark", #selector(MainWindowController.previousBookmark(_:)), fn(NSF2FunctionKey), .shift))
        m.addItem(item("Clear All Bookmarks", #selector(MainWindowController.clearBookmarks(_:))))
        return m
    }

    private static func viewMenu() -> NSMenu {
        let m = NSMenu(title: "View")
        m.addItem(item("Transparent Window", #selector(MainWindowController.toggleTransparency(_:)), "t", [.command, .option]))
        m.addItem(item("Transparency & Tint…", #selector(MainWindowController.showAppearancePopover(_:)), "t", [.command, .option, .shift]))
        m.addItem(item("Tab Colour…", #selector(MainWindowController.showTabColorMenu(_:)), "k", [.command, .option]))
        m.addItem(item("Dark Text Colours", #selector(MainWindowController.setDarkTheme(_:))))
        m.addItem(item("Light Text Colours", #selector(MainWindowController.setLightTheme(_:))))
        m.addItem(.separator())
        m.addItem(item("Show Console", #selector(MainWindowController.toggleConsole(_:)), "`", .control))
        m.addItem(item("New Console Tab", #selector(MainWindowController.newConsoleTab(_:)), "`", [.control, .shift]))
        m.addItem(item("Close Console Tab", #selector(MainWindowController.closeConsoleTab(_:))))
        m.addItem(item("Focus Editor", #selector(MainWindowController.focusEditor(_:)), "1", .control))
        m.addItem(item("Focus Console", #selector(MainWindowController.focusConsole(_:)), "2", .control))
        m.addItem(item("Console: Go to File's Folder", #selector(MainWindowController.consoleCdToFileFolder(_:))))
        m.addItem(.separator())
        m.addItem(item("Word Wrap", #selector(MainWindowController.toggleWordWrap(_:)), "z", .option))
        m.addItem(item("Show Whitespace", #selector(MainWindowController.toggleWhitespace(_:))))
        m.addItem(item("Show Line Endings", #selector(MainWindowController.toggleLineEndings(_:))))
        m.addItem(item("Show All Characters", #selector(MainWindowController.toggleShowAllCharacters(_:))))
        m.addItem(.separator())
        m.addItem(item("Fold All", #selector(MainWindowController.foldAll(_:)), "0", [.command, .option]))
        m.addItem(item("Unfold All", #selector(MainWindowController.unfoldAll(_:)), "0", [.command, .option, .shift]))
        m.addItem(.separator())
        m.addItem(item("Zoom In", #selector(MainWindowController.zoomIn(_:)), "="))
        m.addItem(item("Zoom Out", #selector(MainWindowController.zoomOut(_:)), "-"))
        m.addItem(item("Actual Size", #selector(MainWindowController.resetZoom(_:)), "0"))
        m.addItem(.separator())
        m.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return m
    }

    static func languageMenu() -> NSMenu {
        let m = NSMenu(title: "Language")
        let plain = item(Language.plainText.name, #selector(MainWindowController.setLanguage(_:)))
        plain.representedObject = Language.plainText.name
        m.addItem(plain)
        m.addItem(.separator())
        for lang in Language.all.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let i = item(lang.name, #selector(MainWindowController.setLanguage(_:)))
            i.representedObject = lang.name
            m.addItem(i)
        }
        return m
    }

    private static func runMenu() -> NSMenu {
        let m = NSMenu(title: "Run")
        m.addItem(item("Run File in Console", #selector(MainWindowController.runInConsole(_:)), "r"))
        return m
    }

    private static func windowMenu() -> NSMenu {
        let m = NSMenu(title: "Window")
        m.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        m.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        m.addItem(.separator())
        m.addItem(item("Next Tab", #selector(MainWindowController.selectNextTab(_:)), "]", [.command, .shift]))
        m.addItem(item("Previous Tab", #selector(MainWindowController.selectPreviousTab(_:)), "[", [.command, .shift]))
        m.addItem(item("Next Tab", #selector(MainWindowController.selectNextTab(_:)), "\t", .control))
        m.addItem(item("Previous Tab", #selector(MainWindowController.selectPreviousTab(_:)), "\t", [.control, .shift]))
        return m
    }
}
