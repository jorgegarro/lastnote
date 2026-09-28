import AppKit
import SciKit
import SwiftUI

/// The single editor window: tabs on top, editor, optional find bar, console at the bottom,
/// status bar, and the background layers that provide transparency / blur / tint.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSSplitViewDelegate, NSMenuItemValidation {
    private(set) var documents: [Document] = []
    private(set) var selectedIndex = -1
    private var untitledCounter = 0

    let backdrop = NSVisualEffectView()
    let tintView = TintBackdropView()
    let iconBar = IconBar()
    let tabBar = TabBar()
    let split = ThemedSplitView()
    let editorColumn = NSView()
    let editorHost = NSView()
    let findBar = FindBar()
    let console = ConsolePanel()
    let statusBar = StatusBar()
    let focusGlow = FocusGlowView()
    private var findBarHeight: NSLayoutConstraint!
    private var lastConsoleHeight: CGFloat = 220
    private var settingsObserver: NSObjectProtocol?
    private lazy var appearancePopover: NSPopover = {
        let p = NSPopover()
        p.behavior = .transient
        let host = NSHostingController(rootView: AppearanceControls().padding(16).frame(width: 440))
        p.contentViewController = host
        return p
    }()

    var current: Document? { documents.indices.contains(selectedIndex) ? documents[selectedIndex] : nil }

    init() {
        let window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden  // the icon bar lives in the title-bar row
        window.minSize = NSSize(width: 520, height: 360)
        window.setFrameAutosaveName("MainWindow")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildLayout()
        settingsObserver = NotificationCenter.default.addObserver(forName: AppSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applyAppearance()
        }
        applyAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private func buildLayout() {
        guard let window, let content = window.contentView else { return }

        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.material = .underWindowBackground
        for v in [backdrop, tintView] {
            v.frame = content.bounds
            v.autoresizingMask = [.width, .height]
            content.addSubview(v)
        }

        split.isVertical = false
        split.dividerStyle = .thin
        split.delegate = self
        editorColumn.addSubview(editorHost)
        editorColumn.addSubview(findBar)
        split.addArrangedSubview(editorColumn)
        split.addArrangedSubview(console)
        split.setHoldingPriority(.defaultLow + 1, forSubviewAt: 0)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        for v in [iconBar, tabBar, split, statusBar, editorHost, findBar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        editorHost.wantsLayer = true
        content.addSubview(iconBar)
        content.addSubview(tabBar)
        content.addSubview(split)
        content.addSubview(statusBar)

        findBarHeight = findBar.heightAnchor.constraint(equalToConstant: 0)
        let belowTitlebar = (window.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? content.topAnchor
        NSLayoutConstraint.activate([
            iconBar.topAnchor.constraint(equalTo: content.topAnchor),
            iconBar.bottomAnchor.constraint(equalTo: belowTitlebar),
            iconBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 80),  // after the window buttons
            iconBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabBar.topAnchor.constraint(equalTo: belowTitlebar),
            tabBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 30),
            split.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),
            editorHost.topAnchor.constraint(equalTo: editorColumn.topAnchor),
            editorHost.leadingAnchor.constraint(equalTo: editorColumn.leadingAnchor),
            editorHost.trailingAnchor.constraint(equalTo: editorColumn.trailingAnchor),
            editorHost.bottomAnchor.constraint(equalTo: findBar.topAnchor),
            findBar.leadingAnchor.constraint(equalTo: editorColumn.leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: editorColumn.trailingAnchor),
            findBar.bottomAnchor.constraint(equalTo: editorColumn.bottomAnchor),
            findBarHeight,
        ])
        findBar.isHidden = true
        findBar.document = { [weak self] in self?.current }
        findBar.onClose = { [weak self] in self?.hideFindBar() }

        tabBar.onSelect = { [weak self] in self?.select($0) }
        tabBar.onClose = { [weak self] in self?.closeDocument(at: $0) }
        tabBar.onNew = { [weak self] in self?.newDocument(nil) }
        tabBar.menuForTab = { [weak self] in self?.menu(forDocumentAt: $0) }
        tabBar.onRename = { [weak self] index, name in
            guard let self, self.documents.indices.contains(index) else { return }
            self.documents[index].customName = name
            self.refreshTitle()
        }

        statusBar.consoleButton.target = self
        statusBar.consoleButton.action = #selector(toggleConsole(_:))
        statusBar.appearanceButton.target = self
        statusBar.appearanceButton.action = #selector(showAppearancePopover(_:))
        statusBar.languageButton.target = self
        statusBar.languageButton.action = #selector(showLanguageMenu(_:))
        statusBar.eolButton.target = self
        statusBar.eolButton.action = #selector(showEOLMenu(_:))

        console.startDirectory = { [weak self] in
            self?.current?.url?.deletingLastPathComponent().path ?? NSHomeDirectory()
        }
        console.regionColor = { [weak self] in self?.regionColor(for: $0) ?? .clear }
        console.onAllSessionsClosed = { [weak self] in
            guard let self, !self.console.isHidden else { return }
            self.setConsoleVisible(false)
        }
        console.onChange = { [weak self] in self?.updateTintMask() }

        // Editor and console areas paint their own (per-tab) tint; the window tint covers the rest.
        tintView.holes = [editorHost, console.bodyView]

        // Focus glow floats above everything and follows the first responder.
        focusGlow.frame = .zero
        content.addSubview(focusGlow)
        (window as? MainWindow)?.onFirstResponderChange = { [weak self] in self?.updateFocusGlow(animated: true) }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.updateFocusGlow(animated: true)
            }
        }
        for v in [editorHost, console.bodyView, console] {
            v.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(regionFrameChanged), name: NSView.frameDidChangeNotification, object: v)
        }
        let consoleWasVisible = UserDefaults.standard.object(forKey: "consoleVisible") as? Bool ?? true
        lastConsoleHeight = UserDefaults.standard.object(forKey: "consoleHeight") as? CGFloat ?? 220
        DispatchQueue.main.async { self.setConsoleVisible(consoleWasVisible, focus: false) }
    }

    // MARK: Appearance

    func applyAppearance() {
        guard let window else { return }
        let s = AppSettings.shared
        let theme = Theme.named(s.theme)
        window.appearance = NSAppearance(named: theme.kind == .dark ? .darkAqua : .aqua)
        if s.transparencyEnabled {
            window.isOpaque = false
            window.backgroundColor = .clear
            backdrop.isHidden = !s.blurEnabled
        } else {
            window.isOpaque = true
            window.backgroundColor = theme.background
            backdrop.isHidden = true
        }
        tintView.layer?.backgroundColor = regionColor(for: nil).cgColor
        editorHost.layer?.backgroundColor = regionColor(for: current?.tint).cgColor
        window.invalidateShadow()
        documents.forEach { $0.applySettings() }
        console.applySettings()
        findBar.applyTheme(theme)
        statusBar.applyTheme(theme)
        iconBar.applyTheme(theme)
        split.color = theme.separator
        split.needsDisplay = true
        refreshTabs()
        refreshStatus()
        updateTintMask()
        updateFocusGlow(animated: false)
    }

    /// Background for a region: its own tint if it has one, else the window tint. With transparency
    /// off, a tab colour becomes a solid wash over the theme background so text stays readable.
    func regionColor(for tint: NSColor?) -> NSColor {
        let s = AppSettings.shared
        let theme = Theme.named(s.theme)
        if s.transparencyEnabled {
            return (tint ?? s.tintColor).withAlphaComponent(CGFloat(s.opacity))
        }
        guard let tint else { return theme.background }
        return theme.background.blended(withFraction: 0.35, of: tint) ?? theme.background
    }

    @objc private func regionFrameChanged(_ n: Notification) { updateTintMask() }

    private func updateTintMask() {
        tintView.updateMask()
        updateFocusGlow(animated: false)
    }

    /// The area that should glow for a given first responder: the editor, the console, or none
    /// (e.g. the find field, which has its own focus ring).
    func focusRegion(for responder: NSResponder?) -> NSView? {
        guard let view = responder as? NSView else { return nil }
        if view.isDescendant(of: editorHost) { return editorHost }
        if view.isDescendant(of: console), !console.isHidden { return console.bodyView }
        return nil
    }

    /// Put the glow around the editor or the console, whichever holds the keyboard focus.
    func updateFocusGlow(animated: Bool) {
        guard let window, let content = window.contentView else { return }
        let s = AppSettings.shared
        let region = s.focusGlowEnabled && window.isKeyWindow ? focusRegion(for: window.firstResponder) : nil
        if focusGlow.superview === content, content.subviews.last !== focusGlow {
            content.addSubview(focusGlow, positioned: .above, relativeTo: nil)  // keep on top
        }
        focusGlow.show(around: region.map { $0.convert($0.bounds, to: content) }, color: s.effectiveFocusGlowColor,
                       strength: CGFloat(s.focusGlowOpacity), animated: animated)
    }

    private func applyDocumentTint() {
        editorHost.layer?.backgroundColor = regionColor(for: current?.tint).cgColor
    }

    // MARK: Documents

    @discardableResult
    func addDocument(_ doc: Document) -> Document {
        doc.onStateChange = { [weak self, weak doc] in
            guard let self, let doc else { return }
            self.refreshTabs()
            if doc === self.current { self.refreshTitle(); self.refreshStatus(); self.applyDocumentTint() }
        }
        doc.onCaretChange = { [weak self, weak doc] in
            if let doc, doc === self?.current { self?.refreshStatus() }
        }
        doc.view.translatesAutoresizingMaskIntoConstraints = true
        doc.view.autoresizingMask = [.width, .height]
        documents.append(doc)
        select(documents.count - 1)
        return doc
    }

    func select(_ index: Int) {
        guard documents.indices.contains(index) else { return }
        current?.view.removeFromSuperview()
        selectedIndex = index
        let doc = documents[index]
        doc.view.frame = editorHost.bounds
        editorHost.addSubview(doc.view)
        window?.makeFirstResponder(doc.view.content())
        refreshTabs()
        refreshTitle()
        refreshStatus()
        applyDocumentTint()
        if !findBar.isHidden { findBar.highlightAll() }
    }

    /// Open files; a file that's already open is just selected.
    func open(urls: [URL]) {
        for url in urls {
            if let i = documents.firstIndex(where: { $0.url?.standardizedFileURL == url.standardizedFileURL }) {
                select(i)
                continue
            }
            do {
                let doc = try Document(url: url)
                // Replace a lone, untouched "new 1" tab like Notepad++ does.
                if documents.count == 1, let only = documents.first, only.url == nil, !only.isDirty,
                   only.view.sci(SCI_GETLENGTH) == 0 {
                    only.view.removeFromSuperview()
                    documents.removeAll()
                    selectedIndex = -1
                }
                addDocument(doc)
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
            } catch {
                presentError(error)
            }
        }
    }

    func closeDocument(at index: Int) {
        guard documents.indices.contains(index) else { return }
        let doc = documents[index]
        if doc.isDirty {
            select(index)
            switch askToSave(doc) {
            case .alertFirstButtonReturn: guard save(doc) else { return }
            case .alertSecondButtonReturn: break
            default: return
            }
        }
        doc.view.removeFromSuperview()
        documents.remove(at: index)
        if documents.isEmpty {
            selectedIndex = -1
            newDocument(nil)
        } else {
            selectedIndex = -1
            select(min(index, documents.count - 1))
        }
    }

    private func askToSave(_ doc: Document) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(doc.displayName)”?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal()
    }

    /// Returns false if the user cancelled or saving failed.
    @discardableResult
    func save(_ doc: Document, as forceAsk: Bool = false) -> Bool {
        var target = doc.url
        if target == nil || forceAsk {
            let panel = NSSavePanel()
            // An untitled tab's custom name becomes the suggested file name.
            let suggested = doc.customName.map { ($0 as NSString).pathExtension.isEmpty ? "\($0).txt" : $0 } ?? "\(doc.fileName).txt"
            panel.nameFieldStringValue = doc.url?.lastPathComponent ?? suggested
            if let dir = doc.url?.deletingLastPathComponent() { panel.directoryURL = dir }
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            target = url
        }
        do {
            try doc.save(to: target!)
            NSDocumentController.shared.noteNewRecentDocumentURL(target!)
            refreshTitle()
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    /// Ask about every unsaved document. Returns false if the user cancelled.
    func confirmCloseAll() -> Bool {
        for (i, doc) in documents.enumerated() where doc.isDirty {
            select(i)
            switch askToSave(doc) {
            case .alertFirstButtonReturn: if !save(doc) { return false }
            case .alertSecondButtonReturn: continue
            default: return false
            }
        }
        return true
    }

    var sessionURLs: [URL] { documents.compactMap(\.url) }

    // MARK: Refresh

    private func refreshTabs() {
        tabBar.reload(items: documents.map { .init(title: $0.displayName, dirty: $0.isDirty, tooltip: $0.tooltip, tint: $0.tint) },
                      selected: selectedIndex, theme: Theme.named(AppSettings.shared.theme))
    }

    private func refreshTitle() {
        guard let window else { return }
        window.title = current.map { ($0.isDirty ? "*" : "") + $0.displayName } ?? "LastNote"
        iconBar.pathLabel.stringValue = current?.url.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? ""
        window.representedURL = current?.url
        window.isDocumentEdited = current?.isDirty ?? false
    }

    private func refreshStatus() {
        guard let doc = current else { return }
        refreshIconBar()
        let theme = Theme.named(AppSettings.shared.theme)
        let info = doc.caretInfo
        statusBar.setButtonTitle(statusBar.languageButton, doc.language.name, theme: theme)
        statusBar.lengthLabel.stringValue = "length \(info.length.formatted())   lines \(info.lineCount.formatted())"
        var pos = "Ln \(info.line), Col \(info.column)"
        if info.selectedChars > 0 { pos += "   Sel \(info.selectedChars) | \(info.selectedLines)" }
        statusBar.positionLabel.stringValue = pos
        statusBar.encodingLabel.stringValue = doc.encodingName
        statusBar.setButtonTitle(statusBar.eolButton, doc.lineEnding.rawValue, theme: theme)
    }

    private func refreshIconBar() {
        let s = AppSettings.shared
        var on: Set<Selector> = []
        if s.wordWrap { on.insert(#selector(toggleWordWrap(_:))) }
        if s.showWhitespace && s.showLineEndings { on.insert(#selector(toggleShowAllCharacters(_:))) }
        if s.transparencyEnabled { on.insert(#selector(toggleTransparency(_:))) }
        if !console.isHidden { on.insert(#selector(toggleConsole(_:))) }
        var disabled: Set<Selector> = []
        if let doc = current {
            if !doc.isDirty && doc.url != nil { disabled.insert(#selector(saveDocument(_:))) }
            if !console.containsFirstResponder {
                if doc.view.sci(SCI_CANUNDO) == 0 { disabled.insert(Selector(("undo:"))) }
                if doc.view.sci(SCI_CANREDO) == 0 { disabled.insert(Selector(("redo:"))) }
            }
        }
        if !documents.contains(where: { $0.isDirty }) { disabled.insert(#selector(saveAllDocuments(_:))) }
        iconBar.update(on: on, disabled: disabled)
    }

    // MARK: Tab colours

    func menu(forDocumentAt index: Int) -> NSMenu? {
        guard documents.indices.contains(index) else { return nil }
        let doc = documents[index]
        let menu = NSMenu()
        let colour = NSMenuItem(title: "Tab Colour", action: nil, keyEquivalent: "")
        colour.submenu = TintMenu.make(current: doc.tint) { [weak doc] in doc?.tint = $0 }
        menu.addItem(colour)
        menu.addItem(ClosureMenuItem(title: "Rename Tab…") { [weak self] in self?.tabBar.beginRename(at: index) })
        if doc.customName != nil {
            menu.addItem(ClosureMenuItem(title: "Reset Tab Name") { [weak doc] in doc?.customName = nil })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Close") { [weak self, weak doc] in
            if let doc, let i = self?.documents.firstIndex(where: { $0 === doc }) { self?.closeDocument(at: i) }
        })
        menu.addItem(ClosureMenuItem(title: "Close Others") { [weak self, weak doc] in
            guard let self, let doc else { return }
            for d in self.documents.reversed() where d !== doc {
                if let i = self.documents.firstIndex(where: { $0 === d }) { self.closeDocument(at: i) }
            }
        })
        if let url = doc.url {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(title: "Copy File Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            })
            menu.addItem(ClosureMenuItem(title: "Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) })
        }
        return menu
    }

    /// Tab colour for whatever has focus: the active console tab if the console is focused,
    /// otherwise the current document.
    @objc func showTabColorMenu(_ sender: Any?) {
        let menu: NSMenu
        if console.containsFirstResponder, let s = console.active {
            menu = TintMenu.make(current: s.tint) { [weak self, weak s] c in if let s { self?.console.setTint(c, for: s) } }
        } else {
            guard let doc = current else { return }
            menu = TintMenu.make(current: doc.tint) { [weak doc] in doc?.tint = $0 }
        }
        if let button = sender as? NSView ?? iconBar.buttons[#selector(showTabColorMenu(_:))] {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: button)
        }
    }

    // MARK: Console

    var isConsoleVisible: Bool { !console.isHidden }

    func setConsoleVisible(_ visible: Bool, focus: Bool = true) {
        if visible {
            console.startShellIfNeeded()
            console.isHidden = false
            split.adjustSubviews()
            let h = max(100, min(lastConsoleHeight, split.bounds.height - 120))
            split.setPosition(split.bounds.height - h, ofDividerAt: 0)
            if focus { console.focus() }
            refreshIconBar()
        } else {
            if !console.isHidden { lastConsoleHeight = console.frame.height }
            console.isHidden = true
            split.adjustSubviews()
            refreshIconBar()
            if let v = current?.view.content() { window?.makeFirstResponder(v) }
        }
        UserDefaults.standard.set(visible, forKey: "consoleVisible")
        UserDefaults.standard.set(lastConsoleHeight, forKey: "consoleHeight")
    }

    @objc func toggleConsole(_ sender: Any?) { setConsoleVisible(console.isHidden) }

    @objc func focusConsole(_ sender: Any?) {
        if console.isHidden { setConsoleVisible(true) } else { console.focus() }
    }

    @objc func focusEditor(_ sender: Any?) {
        if let v = current?.view.content() { window?.makeFirstResponder(v) }
    }

    @objc func newConsoleTab(_ sender: Any?) {
        let hadSessions = !console.sessions.isEmpty
        if console.isHidden { setConsoleVisible(true) }  // starts the first shell if there is none
        if hadSessions { console.addSession() } else { console.focus() }
    }

    @objc func closeConsoleTab(_ sender: Any?) { console.closeActiveSession() }

    /// Rename the focused tab: the console tab if the console has focus, else the document tab.
    @objc func renameTab(_ sender: Any?) {
        if console.containsFirstResponder { console.renameActiveTab() } else { tabBar.beginRename(at: selectedIndex) }
    }

    @objc func consoleCdToFileFolder(_ sender: Any?) {
        guard let dir = current?.url?.deletingLastPathComponent().path else { NSSound.beep(); return }
        setConsoleVisible(true)
        console.cd(to: dir)
    }

    /// Save the current file and run it in the console with the matching interpreter.
    @objc func runInConsole(_ sender: Any?) {
        guard let doc = current else { return }
        if doc.isDirty || doc.url == nil { guard save(doc) else { return } }
        guard let url = doc.url else { return }
        let q = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let file = q(url.path)
        let runners: [String: String] = [
            "Python": "python3 \(file)", "Shell": "bash \(file)", "JavaScript": "node \(file)",
            "TypeScript": "npx --yes tsx \(file)", "Ruby": "ruby \(file)", "Lua": "lua \(file)",
            "Swift": "swift \(file)", "Go": "go run \(file)", "PowerShell": "pwsh -File \(file)",
            "Rust": "rustc \(file) -o /tmp/np_run && /tmp/np_run",
            "C": "cc \(file) -o /tmp/np_run && /tmp/np_run", "C++": "c++ -std=c++20 \(file) -o /tmp/np_run && /tmp/np_run",
            "HTML": "open \(file)", "Markdown": "open \(file)",
        ]
        let command: String
        if let r = runners[doc.language.name] {
            command = r
        } else if FileManager.default.isExecutableFile(atPath: url.path) {
            command = file
        } else {
            let alert = NSAlert()
            alert.messageText = "Don't know how to run \(doc.language.name) files."
            alert.informativeText = "Make the file executable (chmod +x) or run it from the console yourself."
            alert.runModal()
            return
        }
        setConsoleVisible(true)
        console.run("cd \(q(url.deletingLastPathComponent().path)) && \(command)")
    }

    /// Development aid (LASTNOTE_SELFTEST=1): exercise tab colours, console tabs, Run and Find.
    func runSelfTest() {
        if documents.count >= 2 {
            documents[0].tint = NSColor(hex: "#B3261E")
            documents[1].tint = NSColor(hex: "#2E7D32")
        }
        select(0)
        runInConsole(nil)
        console.addSession(focus: false, tint: NSColor(hex: "#00796B"))
        console.addSession(focus: false)
        console.select(1, focus: false)
        console.run("echo second console tab")
        if let v = current?.view, let text = v.string(), let r = text.range(of: "self") {
            let start = text.utf8.distance(from: text.startIndex, to: r.lowerBound)
            v.sci(SCI_SETSEL, start, start + 4)
        }
        showFind(nil)
        if documents.count >= 2 {
            documents[0].customName = "Greeter demo"
            console.sessions.first?.customName = "build"
            console.select(1, focus: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.tabBar.beginRename(at: 1) }
        }
        if ProcessInfo.processInfo.environment["LASTNOTE_SELFTEST_ZOOM"] == "1", let window {
            // Double-click an empty spot of the icon bar row, through the real event path.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let before = window.frame
                let p = self.iconBar.convert(NSPoint(x: self.iconBar.bounds.midX + 250, y: self.iconBar.bounds.midY), to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    for clicks in [1, 2] {
                        if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1) {
                            window.sendEvent(e)
                        }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    print("zoom-test before=\(before) after=\(window.frame) screen=\(window.screen?.visibleFrame ?? .zero)")
                }
            }
        }
        switch ProcessInfo.processInfo.environment["LASTNOTE_SELFTEST_FOCUS"] {
        case "console": DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.hideFindBar(); self.console.focus() }
        case "editor": DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.hideFindBar() }
        default: break
        }
    }

    /// Development aid (LASTNOTE_STRESS=seconds): hammer the UI with random actions to shake out
    /// memory bugs (run under Address Sanitizer).
    func runStress(seconds: Double) {
        var rng = SystemRandomNumberGenerator()
        let end = Date().addingTimeInterval(seconds)
        let colors = ["#B3261E", "#2E7D32", "#1565C0", "#6A1B9A", nil]
        var step = 0
        func tick() {
            guard Date() < end else {
                print("stress: done after \(step) steps, \(documents.count) docs, \(console.sessions.count) shells")
                exit(0)
            }
            step += 1
            let s = AppSettings.shared
            switch Int.random(in: 0..<22, using: &rng) {
            case 0: newDocument(nil)
            case 1: if documents.count > 1, let d = documents.randomElement(), !d.isDirty,
                       let i = documents.firstIndex(where: { $0 === d }) { closeDocument(at: i) }
            case 2: if !documents.isEmpty { select(Int.random(in: 0..<documents.count, using: &rng)) }
            case 3, 4: current?.view.sci(SCI_ADDTEXT, 20, string: "self.value = 42 # x\n")
            case 5: current?.tint = colors.randomElement()!.flatMap { NSColor(hex: $0) }
            case 6: s.transparencyEnabled.toggle()
            case 7: s.theme = s.theme == .dark ? .light : .dark
            case 8: s.wordWrap.toggle()
            case 9: s.showWhitespace.toggle(); s.showLineEndings.toggle()
            case 10: if console.sessions.count < 5 { newConsoleTab(nil) }
            case 11: if console.sessions.count > 1 { console.closeSession(at: Int.random(in: 0..<console.sessions.count, using: &rng)) }
            case 12: console.active?.run("echo stress \(step); ls -la /usr/bin | head -40")
            case 13: if let ss = console.sessions.randomElement() { console.setTint(colors.randomElement()!.flatMap { NSColor(hex: $0) }, for: ss) }
            case 14: showFind(nil); findBar.findField.stringValue = "self"; findBar.highlightAll()
            case 15: hideFindBar()
            case 16: [#selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(foldAll(_:)), #selector(unfoldAll(_:))]
                .randomElement().map { _ = self.perform($0, with: nil) }
            case 17: if let w = window, let scr = w.screen?.visibleFrame {
                    w.setFrame(NSRect(x: scr.minX, y: scr.minY, width: CGFloat.random(in: 600...scr.width, using: &rng),
                                      height: CGFloat.random(in: 400...scr.height, using: &rng)), display: true)
                }
            case 18: setConsoleVisible(console.isHidden)
            case 19: if Bool.random() { focusEditor(nil) } else { console.focus() }
            case 20: s.opacity = Double.random(in: 0.2...1, using: &rng); s.blurEnabled.toggle()
            default: current?.view.sci(SCI_SELECTALL); current?.view.sci(SCI_CLEAR); current?.view.sci(SCI_SETSAVEPOINT)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { tick() }
        }
        tick()
    }

    // MARK: Split view

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        max(proposed, 120)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        min(proposed, splitView.bounds.height - 80)
    }

    func windowDidResize(_ notification: Notification) { updateTintMask() }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        updateTintMask()
        if !console.isHidden, console.frame.height > 0 {
            lastConsoleHeight = console.frame.height
            UserDefaults.standard.set(lastConsoleHeight, forKey: "consoleHeight")
        }
    }

    // MARK: Find bar

    func showFindBar(replace: Bool) {
        findBar.isHidden = false
        findBar.showsReplace = replace
        findBarHeight.constant = replace ? 72 : 40
        findBar.focusFind(prefill: current?.view.selectedString())
    }

    func hideFindBar() {
        findBar.isHidden = true
        findBarHeight.constant = 0
        focusEditor(nil)
    }

    // MARK: Window delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    // MARK: Menu actions — File

    @objc func newDocument(_ sender: Any?) {
        untitledCounter += 1
        addDocument(Document(untitledNumber: untitledCounter))
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if let dir = current?.url?.deletingLastPathComponent() { panel.directoryURL = dir }
        guard panel.runModal() == .OK else { return }
        open(urls: panel.urls)
    }

    @objc func saveDocument(_ sender: Any?) { if let d = current { save(d) } }
    @objc func saveDocumentAs(_ sender: Any?) { if let d = current { save(d, as: true) } }
    @objc func saveAllDocuments(_ sender: Any?) { for d in documents where d.isDirty || d.url == nil && d.view.sci(SCI_GETLENGTH) > 0 { save(d) } }
    /// ⌘W closes the console tab when the console has focus, otherwise the document tab.
    @objc func closeTab(_ sender: Any?) {
        if console.containsFirstResponder && !(sender is NSButton) { console.closeActiveSession() }
        else { closeDocument(at: selectedIndex) }
    }

    @objc func reloadFromDisk(_ sender: Any?) {
        guard let doc = current, let url = doc.url else { return }
        if doc.isDirty {
            let alert = NSAlert()
            alert.messageText = "Reload “\(doc.displayName)” and lose your changes?"
            alert.addButton(withTitle: "Reload")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do { try doc.load(from: url) } catch { presentError(error) }
    }

    @objc func revealInFinder(_ sender: Any?) {
        if let url = current?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    @objc func copyFilePath(_ sender: Any?) {
        guard let path = current?.url?.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    // MARK: Menu actions — Edit

    private func send(_ m: Int32) { current?.view.sci(m) }

    @objc func duplicateLine(_ sender: Any?) { send(SCI_SELECTIONDUPLICATE) }
    @objc func deleteLine(_ sender: Any?) { send(SCI_LINEDELETE) }
    @objc func moveLinesUp(_ sender: Any?) { send(SCI_MOVESELECTEDLINESUP) }
    @objc func moveLinesDown(_ sender: Any?) { send(SCI_MOVESELECTEDLINESDOWN) }
    @objc func uppercaseSelection(_ sender: Any?) { send(SCI_UPPERCASE) }
    @objc func lowercaseSelection(_ sender: Any?) { send(SCI_LOWERCASE) }
    @objc func toggleComment(_ sender: Any?) { current?.toggleLineComment() }
    @objc func trimTrailingWhitespace(_ sender: Any?) { current?.trimTrailingWhitespace() }
    @objc func sortLinesAscending(_ sender: Any?) { current?.sortLines(descending: false) }
    @objc func sortLinesDescending(_ sender: Any?) { current?.sortLines(descending: true) }
    @objc func joinLines(_ sender: Any?) {
        guard let v = current?.view else { return }
        v.sci(SCI_TARGETFROMSELECTION)
        v.sci(SCI_LINESJOIN)
    }

    @objc func convertEOL(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let eol = LineEnding(rawValue: raw) else { return }
        current?.convertLineEndings(to: eol)
    }

    // MARK: Menu actions — Search

    @objc func showFind(_ sender: Any?) { showFindBar(replace: false) }
    @objc func showReplace(_ sender: Any?) { showFindBar(replace: true) }

    @objc func findNextMatch(_ sender: Any?) {
        if findBar.findField.stringValue.isEmpty { showFindBar(replace: false) } else { findBar.findNext() }
    }

    @objc func findPreviousMatch(_ sender: Any?) {
        if findBar.findField.stringValue.isEmpty { showFindBar(replace: false) } else { findBar.findPrevious() }
    }

    @objc func useSelectionForFind(_ sender: Any?) {
        guard let s = current?.view.selectedString(), !s.isEmpty else { return }
        findBar.findField.stringValue = s
        if !findBar.isHidden { findBar.highlightAll() }
    }

    @objc func goToLine(_ sender: Any?) {
        guard let doc = current else { return }
        let alert = NSAlert()
        alert.messageText = "Go to line"
        alert.informativeText = "Line number (1 – \(doc.caretInfo.lineCount)):"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = "\(doc.caretInfo.line)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, let n = Int(field.stringValue.trimmingCharacters(in: .whitespaces)) else { return }
        doc.gotoLine(max(0, n - 1))
        focusEditor(nil)
    }

    @objc func toggleBookmark(_ sender: Any?) { current?.toggleBookmark() }
    @objc func nextBookmark(_ sender: Any?) { current?.gotoBookmark(forward: true) }
    @objc func previousBookmark(_ sender: Any?) { current?.gotoBookmark(forward: false) }
    @objc func clearBookmarks(_ sender: Any?) { current?.view.sci(SCI_MARKERDELETEALL, markerBookmark) }

    // MARK: Menu actions — View

    @objc func toggleTransparency(_ sender: Any?) { AppSettings.shared.transparencyEnabled.toggle() }
    @objc func toggleWordWrap(_ sender: Any?) { AppSettings.shared.wordWrap.toggle() }
    @objc func toggleWhitespace(_ sender: Any?) { AppSettings.shared.showWhitespace.toggle() }
    @objc func toggleLineEndings(_ sender: Any?) { AppSettings.shared.showLineEndings.toggle() }
    /// Notepad++'s ¶ button: whitespace and line endings together.
    @objc func toggleShowAllCharacters(_ sender: Any?) {
        let s = AppSettings.shared
        let on = !(s.showWhitespace && s.showLineEndings)
        s.showWhitespace = on
        s.showLineEndings = on
    }
    @objc func setDarkTheme(_ sender: Any?) { AppSettings.shared.theme = .dark }
    @objc func setLightTheme(_ sender: Any?) { AppSettings.shared.theme = .light }
    @objc func zoomIn(_ sender: Any?) { send(SCI_ZOOMIN) }
    @objc func zoomOut(_ sender: Any?) { send(SCI_ZOOMOUT) }
    @objc func resetZoom(_ sender: Any?) { current?.view.sci(SCI_SETZOOM, 0) }
    @objc func foldAll(_ sender: Any?) { current?.view.sci(SCI_FOLDALL, Int(SC_FOLDACTION_CONTRACT)) }
    @objc func unfoldAll(_ sender: Any?) { current?.view.sci(SCI_FOLDALL, Int(SC_FOLDACTION_EXPAND)) }

    @objc func showAppearancePopover(_ sender: Any?) {
        let anchor = (sender as? NSButton) ?? statusBar.appearanceButton
        if appearancePopover.isShown { appearancePopover.close(); return }
        appearancePopover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: anchor === statusBar.appearanceButton ? .maxY : .minY)
    }

    @objc func selectNextTab(_ sender: Any?) {
        if console.containsFirstResponder { console.selectNext(1); return }
        guard !documents.isEmpty else { return }
        select((selectedIndex + 1) % documents.count)
    }

    @objc func selectPreviousTab(_ sender: Any?) {
        if console.containsFirstResponder { console.selectNext(-1); return }
        guard !documents.isEmpty else { return }
        select((selectedIndex - 1 + documents.count) % documents.count)
    }

    @objc func setLanguage(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        current?.setLanguage(Language.all.first { $0.name == name } ?? .plainText)
    }

    @objc private func showLanguageMenu(_ sender: NSButton) {
        let menu = AppMenus.languageMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func showEOLMenu(_ sender: NSButton) {
        let menu = AppMenus.eolMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    // MARK: Menu validation (checkmarks)

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let s = AppSettings.shared
        switch item.action {
        case #selector(toggleTransparency(_:)): item.state = s.transparencyEnabled ? .on : .off
        case #selector(toggleWordWrap(_:)): item.state = s.wordWrap ? .on : .off
        case #selector(toggleWhitespace(_:)): item.state = s.showWhitespace ? .on : .off
        case #selector(toggleLineEndings(_:)): item.state = s.showLineEndings ? .on : .off
        case #selector(toggleShowAllCharacters(_:)): item.state = s.showWhitespace && s.showLineEndings ? .on : .off
        case #selector(closeConsoleTab(_:)): return !console.sessions.isEmpty
        case #selector(setDarkTheme(_:)): item.state = s.theme == .dark ? .on : .off
        case #selector(setLightTheme(_:)): item.state = s.theme == .light ? .on : .off
        case #selector(toggleConsole(_:)):
            item.title = console.isHidden ? "Show Console" : "Hide Console"
        case #selector(setLanguage(_:)):
            item.state = (item.representedObject as? String) == current?.language.name ? .on : .off
        case #selector(convertEOL(_:)):
            item.state = (item.representedObject as? String) == current?.lineEnding.rawValue ? .on : .off
        case #selector(reloadFromDisk(_:)), #selector(revealInFinder(_:)), #selector(copyFilePath(_:)),
             #selector(consoleCdToFileFolder(_:)):
            return current?.url != nil
        default: break
        }
        return true
    }
}

/// NSSplitView whose divider colour follows the theme.
final class ThemedSplitView: NSSplitView {
    var color: NSColor = .separatorColor
    override var dividerColor: NSColor { color }
}

/// The window-wide tint layer. Regions listed in `holes` are cut out of it because they paint
/// their own (per-tab) tint, so tints don't stack.
final class TintBackdropView: NSView {
    var holes: [NSView] = []
    private let maskLayer = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        maskLayer.fillRule = .evenOdd
        layer?.mask = maskLayer
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        updateMask()
    }

    func updateMask() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = CGMutablePath()
        path.addRect(bounds)
        for h in holes where h.window != nil && !h.isHiddenOrHasHiddenAncestor && h.bounds.width > 0 {
            path.addRect(h.convert(h.bounds, to: self))
        }
        maskLayer.frame = bounds
        maskLayer.path = path
        CATransaction.commit()
    }
}

/// Window that reports first-responder changes (NSWindow has no notification for them).
final class MainWindow: NSWindow {
    var onFirstResponderChange: (() -> Void)?

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let ok = super.makeFirstResponder(responder)
        if ok { DispatchQueue.main.async { self.onFirstResponderChange?() } }
        return ok
    }
}

/// Soft glowing border drawn over the focused area. Ignores the mouse.
final class FocusGlowView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.shadowOffset = .zero
        layer?.shadowRadius = 2.5
        layer?.masksToBounds = false
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `rect` nil hides the glow.
    func show(around rect: NSRect?, color: NSColor, strength: CGFloat, animated: Bool) {
        // Thin, partly transparent line with a faint halo, so it never competes with the text.
        layer?.borderColor = color.withAlphaComponent(strength).cgColor
        layer?.shadowColor = color.cgColor
        layer?.shadowOpacity = Float(strength * 0.6)
        let visible = rect != nil
        if let rect {
            let r = rect.insetBy(dx: 1, dy: 1)  // hug the edge, away from the text
            if animated && alphaValue > 0 {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    animator().frame = r
                }
            } else {
                frame = r
            }
        }
        let target: CGFloat = visible ? 1 : 0
        guard alphaValue != target else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                animator().alphaValue = target
            }
        } else {
            alphaValue = target
        }
    }
}
