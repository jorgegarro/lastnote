import AppKit
import SciKit
import SwiftUI

/// The single editor window: tabs on top, editor, optional find bar, console at the bottom,
/// status bar, and the background layers that provide transparency / blur / tint.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSSplitViewDelegate, NSMenuItemValidation {
    private(set) var documents: [Document] = []
    let macros = MacroRecorder()
    private(set) var selectedIndex = -1
    private var untitledCounter = 0

    let backdrop = NSVisualEffectView()
    let tintView = TintBackdropView()
    let iconBar = IconBar()
    let tabBar = TabBar()
    let split = ThemedSplitView()
    let editorColumn = NSView()
    let editorHost = NSView()
    /// Side-by-side panes inside the editor area.
    let editorPanes = PaneArea()
    /// Documents shown in the editor panes, left to right (1–3). `current` is always one of them.
    private(set) var visibleDocs: [Document] = []
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
        editorPanes.frame = editorHost.bounds
        editorPanes.autoresizingMask = [.width, .height]
        editorHost.addSubview(editorPanes)
        editorPanes.onActivate = { [weak self] i in
            guard let self, self.visibleDocs.indices.contains(i) else { return }
            self.activate(self.visibleDocs[i], focus: true)
        }
        editorPanes.onRemove = { [weak self] i in
            guard let self, self.visibleDocs.indices.contains(i) else { return }
            self.removeFromSideBySide(self.visibleDocs[i])
        }
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
        findBar.onRecord = { [weak self] in self?.macros.record($0) }
        NotificationCenter.default.addObserver(forName: MacroRecorder.didChange, object: macros, queue: .main) { [weak self] _ in
            self?.refreshStatus()
        }

        tabBar.onSelect = { [weak self] in self?.select($0) }
        tabBar.onClose = { [weak self] in self?.closeDocument(at: $0) }
        tabBar.onNew = { [weak self] in self?.newDocument(nil) }
        tabBar.menuForTab = { [weak self] in self?.menu(forDocumentAt: $0) }
        tabBar.onCommandClick = { [weak self] in self?.toggleSideBySide(at: $0) }
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
        console.regionColor = { [weak self] in self?.consoleRegionColor(for: $0) ?? .clear }
        console.onAllSessionsClosed = { [weak self] in
            guard let self, !self.console.isHidden else { return }
            self.setConsoleVisible(false)
        }
        console.onChange = { [weak self] in self?.updateTintMask() }
        console.splitMenuProvider = { [weak self] in self?.splitMenu(forConsole: true) ?? NSMenu() }

        // Editor and console areas paint their own (per-tab) tint; the window tint covers the rest.
        tintView.holes = [editorHost, console.bodyView]

        // Focus glow floats above everything and follows the first responder.
        focusGlow.frame = .zero
        content.addSubview(focusGlow)
        (window as? MainWindow)?.onFirstResponderChange = { [weak self] in
            self?.followFocusToPane()
            self?.updateFocusGlow(animated: true)
        }
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
        editorHost.layer?.backgroundColor = nil  // each pane paints its own tab's colour…
        layoutEditorPanes()                       // …so repaint them with the new transparency/tint
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

    /// Console background: the console tab's own colour, else the console background setting,
    /// else the window tint. An explicit console background is used as-is when the window is solid.
    func consoleRegionColor(for tint: NSColor?) -> NSColor {
        let s = AppSettings.shared
        if let tint { return regionColor(for: tint) }
        guard let bg = s.consoleBackgroundColor else { return regionColor(for: nil) }
        return s.transparencyEnabled ? bg.withAlphaComponent(CGFloat(s.opacity)) : bg
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
        if view.isDescendant(of: editorHost) {
            // With several panes, glow around the one being typed in.
            if editorPanes.paneCount > 1, let i = editorPanes.pane(containing: view) { return editorPanes.hosts[i] }
            return editorHost
        }
        if view.isDescendant(of: console), !console.isHidden { return console.focusRegion(for: view) }
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

    private func applyDocumentTint() { layoutEditorPanes() }

    /// Put the visible documents into the editor panes.
    private func layoutEditorPanes() {
        let theme = Theme.named(AppSettings.shared.theme)
        editorPanes.show(visibleDocs.map { PaneItem(view: $0.view, title: $0.displayName, tint: $0.tint, background: regionColor(for: $0.tint)) },
                         active: visibleDocs.firstIndex { $0 === current } ?? 0, theme: theme)
    }

    // MARK: Side by side

    /// Make a visible document the active one (after a click in its pane or its header).
    func activate(_ doc: Document, focus: Bool) {
        guard let i = documents.firstIndex(where: { $0 === doc }) else { return }
        if i != selectedIndex {
            selectedIndex = i
            refreshTabs()
            refreshTitle()
            refreshStatus()
            layoutEditorPanes()
            if !findBar.isHidden { findBar.highlightAll() }
        }
        if focus { window?.makeFirstResponder(doc.view.content()) }
    }

    /// ⌘-click on a tab: add it to the side-by-side view, or take it out if it's already shown.
    func toggleSideBySide(at index: Int) {
        guard documents.indices.contains(index) else { return }
        let doc = documents[index]
        if visibleDocs.contains(where: { $0 === doc }) {
            removeFromSideBySide(doc)
        } else {
            guard visibleDocs.count < PaneArea.maxPanes else { NSSound.beep(); return }
            visibleDocs.append(doc)
            layoutEditorPanes()
            activate(doc, focus: true)
            refreshTabs()
        }
    }

    func removeFromSideBySide(_ doc: Document) {
        guard visibleDocs.count > 1, let slot = visibleDocs.firstIndex(where: { $0 === doc }) else { return }
        visibleDocs.remove(at: slot)
        if doc === current { selectedIndex = documents.firstIndex { $0 === visibleDocs[min(slot, visibleDocs.count - 1)] } ?? selectedIndex }
        layoutEditorPanes()
        refreshTabs()
        refreshTitle()
        refreshStatus()
        if let cur = current { window?.makeFirstResponder(cur.view.content()) }
    }

    /// A new untitled note in a pane next to the current ones.
    @objc func newDocumentSideBySide(_ sender: Any?) {
        let previous = visibleDocs
        guard previous.count < PaneArea.maxPanes else { NSSound.beep(); return }
        newDocument(nil)  // shows in the active pane…
        guard let doc = current else { return }
        visibleDocs = previous + [doc]  // …so put the previous panes back and add it as a new one
        layoutEditorPanes()
        refreshTabs()
        window?.makeFirstResponder(doc.view.content())
    }

    /// ⌘\: show the next tab that isn't visible yet next to the others (in the editor or the
    /// console, whichever has focus). With no other tab to show, a new one is created.
    @objc func splitAddNextTab(_ sender: Any?) {
        if console.containsFirstResponder {
            console.addNextSideBySide()
            return
        }
        guard visibleDocs.count < PaneArea.maxPanes else { NSSound.beep(); return }
        let start = selectedIndex
        let order = documents.indices.map { (start + 1 + $0) % documents.count }
        if let i = order.first(where: { i in !visibleDocs.contains { $0 === documents[i] } }) {
            toggleSideBySide(at: i)
        } else {
            newDocumentSideBySide(nil)
        }
    }

    /// Menu listing the tabs of one area with checkmarks for the ones shown side by side.
    func splitMenu(forConsole: Bool) -> NSMenu {
        let menu = NSMenu(title: "Side by Side")
        let header = NSMenuItem(title: forConsole ? "Console tabs side by side (up to 3):" : "Tabs side by side (up to 3):", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if forConsole {
            for (i, s) in console.sessions.enumerated() {
                let item = ClosureMenuItem(title: s.name) { [weak self] in self?.console.toggleSideBySide(at: i) }
                item.state = console.visibleSessions.contains { $0 === s } ? .on : .off
                item.image = s.tint.map { TintMenu.swatch($0) }
                menu.addItem(item)
            }
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(title: "New Console Tab Side by Side") { [weak self] in
                self?.setConsoleVisible(true)
                self?.console.addSessionSideBySide()
            })
            menu.addItem(ClosureMenuItem(title: "Show Only the Active Console Tab") { [weak self] in self?.console.showOnlyActive() })
        } else {
            for (i, d) in documents.enumerated() {
                let item = ClosureMenuItem(title: d.displayName) { [weak self] in self?.toggleSideBySide(at: i) }
                item.state = visibleDocs.contains { $0 === d } ? .on : .off
                item.image = d.tint.map { TintMenu.swatch($0) }
                menu.addItem(item)
            }
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(title: "New Tab Side by Side") { [weak self] in self?.newDocumentSideBySide(nil) })
            menu.addItem(ClosureMenuItem(title: "Show Only the Active Tab") { [weak self] in
                guard let self, let cur = self.current else { return }
                self.visibleDocs = [cur]
                self.layoutEditorPanes()
                self.refreshTabs()
            })
        }
        menu.addItem(.separator())
        let tip = NSMenuItem(title: "Tip: ⌘-click a tab to show it side by side", action: nil, keyEquivalent: "")
        tip.isEnabled = false
        menu.addItem(tip)
        return menu
    }

    /// Icon-bar Split button: the menu for whichever area has focus.
    @objc func showSplitMenu(_ sender: Any?) {
        let menu = splitMenu(forConsole: console.containsFirstResponder)
        if let button = sender as? NSView ?? iconBar.buttons[#selector(showSplitMenu(_:))] {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: button)
        }
    }

    /// Back to one pane showing the active tab.
    @objc func showOnlyActiveTab(_ sender: Any?) {
        if console.containsFirstResponder { console.showOnlyActive(); return }
        guard let cur = current else { return }
        visibleDocs = [cur]
        layoutEditorPanes()
        refreshTabs()
        window?.makeFirstResponder(cur.view.content())
    }

    /// Clicking into a pane makes its tab the active one.
    private func followFocusToPane() {
        guard let responder = window?.firstResponder as? NSView else { return }
        if responder.isDescendant(of: editorHost),
           let doc = visibleDocs.first(where: { responder.isDescendant(of: $0.view) }), doc !== current {
            activate(doc, focus: false)
        } else if responder.isDescendant(of: console) {
            console.followFocus(to: responder)
        }
    }

    // MARK: Documents

    @discardableResult
    func addDocument(_ doc: Document) -> Document {
        doc.onStateChange = { [weak self, weak doc] in
            guard let self, let doc else { return }
            self.refreshTabs()
            if doc === self.current { self.refreshTitle(); self.refreshStatus() }
            if self.visibleDocs.contains(where: { $0 === doc }) { self.layoutEditorPanes() }  // pane name/colour
        }
        doc.onCaretChange = { [weak self, weak doc] in
            if let doc, doc === self?.current { self?.refreshStatus() }
        }
        doc.onMacroRecord = { [weak self, weak doc] step in
            if let doc, doc === self?.current { self?.macros.record(step) }
        }
        if macros.isRecording { doc.view.sci(SCI_STARTRECORD) }
        doc.view.translatesAutoresizingMaskIntoConstraints = true
        doc.view.autoresizingMask = [.width, .height]
        documents.append(doc)
        select(documents.count - 1)
        return doc
    }

    /// Show a document. If it isn't already in a pane it replaces the active pane's document.
    func select(_ index: Int) {
        guard documents.indices.contains(index) else { return }
        let doc = documents[index]
        if !visibleDocs.contains(where: { $0 === doc }) {
            if let cur = current, let slot = visibleDocs.firstIndex(where: { $0 === cur }) {
                visibleDocs[slot] = doc
            } else {
                visibleDocs = [doc]
            }
        }
        selectedIndex = index
        layoutEditorPanes()
        window?.makeFirstResponder(doc.view.content())
        refreshTabs()
        refreshTitle()
        refreshStatus()
        if !findBar.isHidden { findBar.highlightAll() }
    }

    /// Open files; a file that's already open is just selected.
    func open(urls: [URL]) {
        for url in urls {
            if let i = documents.firstIndex(where: { $0.url?.standardizedFileURL == url.standardizedFileURL }) {
                select(i)
                RecentFiles.shared.note(url)  // opening it again moves it to the top of Open Recent
                continue
            }
            do {
                let doc = try Document(url: url)
                // Replace a lone, untouched "new 1" tab like Notepad++ does.
                if documents.count == 1, let only = documents.first, only.url == nil, !only.isDirty,
                   only.view.sci(SCI_GETLENGTH) == 0 {
                    only.view.removeFromSuperview()
                    documents.removeAll()
                    visibleDocs.removeAll()
                    selectedIndex = -1
                }
                addDocument(doc)
                RecentFiles.shared.note(url)
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
        // `current` is looked up by index, so remember the active document before removing one.
        let previous = current
        let wasCurrent = doc === previous
        let slot = visibleDocs.firstIndex { $0 === doc }
        visibleDocs.removeAll { $0 === doc }
        doc.view.removeFromSuperview()
        documents.remove(at: index)
        if documents.isEmpty {
            selectedIndex = -1
            newDocument(nil)
        } else if !visibleDocs.isEmpty {
            // It was one of several side-by-side panes: the neighbouring pane takes over.
            let next = wasCurrent ? visibleDocs[min(slot ?? 0, visibleDocs.count - 1)] : (previous ?? visibleDocs[0])
            selectedIndex = documents.firstIndex { $0 === next } ?? 0
            layoutEditorPanes()
            refreshTabs()
            refreshTitle()
            refreshStatus()
            if wasCurrent { window?.makeFirstResponder(next.view.content()) }
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
            RecentFiles.shared.note(target!)
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
        let multi = visibleDocs.count > 1
        tabBar.reload(items: documents.map { d in
            .init(title: d.displayName, dirty: d.isDirty, tooltip: d.tooltip, tint: d.tint,
                  visible: multi && visibleDocs.contains { $0 === d })
        },
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
        statusBar.recordingLabel.isHidden = !macros.isRecording
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
        if macros.isRecording { on.insert(#selector(toggleMacroRecording(_:))) }
        var disabled: Set<Selector> = []
        if let doc = current {
            if !doc.isDirty && doc.url != nil { disabled.insert(#selector(saveDocument(_:))) }
            if !console.containsFirstResponder {
                if doc.view.sci(SCI_CANUNDO) == 0 { disabled.insert(Selector(("undo:"))) }
                if doc.view.sci(SCI_CANREDO) == 0 { disabled.insert(Selector(("redo:"))) }
            }
        }
        if !documents.contains(where: { $0.isDirty }) { disabled.insert(#selector(saveAllDocuments(_:))) }
        if macros.isRecording || macros.current.isEmpty { disabled.insert(#selector(playMacro(_:))) }
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
        menu.addItem(.separator())
        if visibleDocs.contains(where: { $0 === doc }) {
            if visibleDocs.count > 1 {
                menu.addItem(ClosureMenuItem(title: "Remove from Side by Side") { [weak self, weak doc] in
                    if let doc { self?.removeFromSideBySide(doc) }
                })
            }
        } else {
            let add = ClosureMenuItem(title: "Show Side by Side") { [weak self, weak doc] in
                if let self, let doc, let i = self.documents.firstIndex(where: { $0 === doc }) { self.toggleSideBySide(at: i) }
            }
            add.isEnabled = visibleDocs.count < PaneArea.maxPanes
            add.toolTip = "⌘-click a tab does the same (up to \(PaneArea.maxPanes) side by side)"
            menu.addItem(add)
        }
        if visibleDocs.count > 1 {
            menu.addItem(ClosureMenuItem(title: "Show Only This Tab") { [weak self, weak doc] in
                guard let self, let doc, let i = self.documents.firstIndex(where: { $0 === doc }) else { return }
                self.visibleDocs = [doc]
                self.select(i)
            })
        }
        menu.addItem(.separator())
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
        if ProcessInfo.processInfo.environment["LASTNOTE_SELFTEST_SPLIT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.hideFindBar()
                for i in 1..<min(3, self.documents.count) { self.toggleSideBySide(at: i) }
                if self.console.sessions.count >= 2 { self.console.toggleSideBySide(at: 0) }
                self.focusEditor(nil)
            }
        }
        if ProcessInfo.processInfo.environment["LASTNOTE_SELFTEST_RECORD"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.toggleMacroRecording(nil) }
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
        var layoutSession: SavedSession?
        func tick() {
            guard Date() < end else {
                print("stress: done after \(step) steps, \(documents.count) docs, \(console.sessions.count) shells")
                exit(0)
            }
            step += 1
            let s = AppSettings.shared
            switch Int.random(in: 0..<34, using: &rng) {
            case 30, 31: if !documents.isEmpty { toggleSideBySide(at: Int.random(in: 0..<documents.count, using: &rng)) }
            case 32: if !console.sessions.isEmpty { console.toggleSideBySide(at: Int.random(in: 0..<console.sessions.count, using: &rng)) }
            case 33: if Bool.random() { showOnlyActiveTab(nil) } else { console.showOnlyActive() }
            case 26, 27: stressClick(in: Bool.random() ? tabBar : console.tabBar, closeButton: false, rng: &rng)
            case 28: if documents.count > 1 || console.sessions.count > 1 {
                    stressClick(in: Bool.random() ? tabBar : console.tabBar, closeButton: true, rng: &rng)
                }
            case 29: stressClick(in: Bool.random() ? tabBar : console.tabBar, closeButton: false, rng: &rng, clicks: 2)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    if let tv = self.window?.firstResponder as? NSTextView {
                        tv.string = "t\(step)"
                        tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))
                    }
                }
            case 22: toggleMacroRecording(nil)
            case 23: if !macros.isRecording { playMacroSteps(macros.current, times: Int.random(in: 1...3, using: &rng)) }
            case 24: layoutSession = captureSession(name: "stress", includeTabs: false)
            case 25: if let l = layoutSession { applySession(l) }
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

    /// Development aid (LASTNOTE_STRESS_APPEARANCE=seconds): rapid appearance changes (like dragging
    /// the opacity slider) while typing, scrolling and streaming console output.
    func runAppearanceStress(seconds: Double) {
        var rng = SystemRandomNumberGenerator()
        let end = Date().addingTimeInterval(seconds)
        let tints = ["#1B1F27", "#0B3D91", "#B3261E", "#2E7D32", "#5B2A86"]
        setConsoleVisible(true)
        console.run("for i in $(seq 1 200000); do echo \"line $i the quick brown fox jumps over the lazy dog\"; done")
        if documents.count < 2 { newDocument(nil) }
        if visibleDocs.count < 2 { toggleSideBySide(at: 0) }
        var step = 0
        func tick() {
            guard Date() < end else {
                print("appearance stress: done after \(step) steps")
                exit(0)
            }
            step += 1
            let s = AppSettings.shared
            switch Int.random(in: 0..<12, using: &rng) {
            case 10, 11:
                // Move to another display (Retina 2x <-> external 1x changes the backing scale).
                if let w = window, let target = NSScreen.screens.filter({ $0 != w.screen }).randomElement(using: &rng) {
                    let f = target.visibleFrame
                    w.setFrame(NSRect(x: f.minX + 20, y: f.minY + 20, width: min(1000, f.width - 40), height: min(700, f.height - 40)), display: true)
                }
            case 0, 1, 2: s.opacity = Double.random(in: 0.1...1, using: &rng)   // slider drag
            case 3: s.tintColor = NSColor(hex: tints.randomElement(using: &rng)!)!
            case 4: s.transparencyEnabled.toggle()
            case 5: s.theme = s.theme == .dark ? .light : .dark
            case 6: s.fontSize = Double(Int.random(in: 10...18, using: &rng))
            case 7: current?.view.content().insertText("typing words here ", replacementRange: NSRange(location: NSNotFound, length: 0))
            case 8: current?.view.sci(SCI_LINESCROLL, 0, Int.random(in: -20...20, using: &rng))
            default: s.consoleFontSize = Double(Int.random(in: 10...16, using: &rng))
            }
            // Force a real display pass each step, as the screen would.
            window?.displayIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.008) { tick() }
        }
        current?.view.setString(String(repeating: "def fn(self, x):  # comment\n    return x * 2\n\n", count: 400))
        tick()
    }

    /// Development aid (LASTNOTE_STRESS_EDIT=seconds): editing features (undo storms, multi-cursor,
    /// column selection, regex replace, folding, wrap with long lines, emoji/CJK, zoom, line
    /// operations) plus terminals resized while flooding colour/Unicode output.
    func runEditStress(seconds: Double) {
        var rng = SystemRandomNumberGenerator()
        let end = Date().addingTimeInterval(seconds)
        setConsoleVisible(true)
        let flood = "for i in $(seq 1 100000); do printf '\\033[3%dm%s 日本語 🎉 \\033[1m%05d\\033[0m %s\\n' $((i%8)) ═══ $i $(printf '%*s' $((i%120)) '' | tr ' ' x); done"
        console.run(flood)
        newConsoleTab(nil)
        console.run(flood)
        console.toggleSideBySide(at: 0)
        if documents.count < 3 { newDocument(nil); newDocument(nil) }
        let samples = ["héllo wörld ", "日本語テキスト ", "🎉🚀👨‍👩‍👧 ", "\t\tindent ", "if (x) { y(); }\n", String(repeating: "long", count: 800) + "\n", "\r\n", "  "]
        var step = 0
        func tick() {
            guard Date() < end else {
                print("edit stress: done after \(step) steps")
                exit(0)
            }
            step += 1
            guard let doc = current else { newDocument(nil); return DispatchQueue.main.async { tick() } }
            let v = doc.view
            if v.sci(SCI_GETLENGTH) > 40_000 { v.setString(String(repeating: "shrunk 日本 🎉 line\n", count: 40)) }
            let len = v.sci(SCI_GETLENGTH)
            func pos() -> Int { len == 0 ? 0 : Int.random(in: 0...len, using: &rng) }
            switch Int.random(in: 0..<28, using: &rng) {
            case 0, 1, 2: v.content().insertText(samples.randomElement(using: &rng)!, replacementRange: NSRange(location: NSNotFound, length: 0))
            case 3: v.sci(SCI_UNDO)
            case 4: v.sci(SCI_REDO)
            case 5: for _ in 0..<Int.random(in: 1...20, using: &rng) { v.sci(SCI_UNDO) }
            case 6: v.sci(SCI_SETSEL, pos(), pos())
            case 7: // multiple carets then type
                v.sci(SCI_SETSELECTION, pos(), pos())
                for _ in 0..<3 { let p = pos(); v.sci(SCI_ADDSELECTION, p, p) }
                v.content().insertText("✱", replacementRange: NSRange(location: NSNotFound, length: 0))
            case 8: // rectangular selection then delete
                v.sci(SCI_SETRECTANGULARSELECTIONANCHOR, pos())
                v.sci(SCI_SETRECTANGULARSELECTIONCARET, pos())
                v.sci(SCI_CLEAR)
            case 9: findBar.regex.state = .on
                findBar.findField.stringValue = ["(\\w+)", "[0-9]+", "^\\s+", "o", "(é|日)", ".*"].randomElement(using: &rng)!
                findBar.replaceField.stringValue = ["<\\1>", "", "Ω", "\\1\\1"].randomElement(using: &rng)!
                if Int.random(in: 0..<4, using: &rng) == 0 { findBar.replaceAll() } else { findBar.highlightAll() }
                findBar.regex.state = .off
            case 10: [#selector(foldAll(_:)), #selector(unfoldAll(_:))].randomElement(using: &rng).map { _ = perform($0, with: nil) }
            case 11: AppSettings.shared.wordWrap.toggle()
            case 12: v.sci(SCI_SETZOOM, Int.random(in: -10...20, using: &rng))
            case 13: [#selector(duplicateLine(_:)), #selector(deleteLine(_:)), #selector(moveLinesUp(_:)), #selector(moveLinesDown(_:)),
                      #selector(toggleComment(_:)), #selector(uppercaseSelection(_:)), #selector(joinLines(_:)), #selector(sortLinesAscending(_:)),
                      #selector(trimTrailingWhitespace(_:))].randomElement(using: &rng).map { _ = perform($0, with: nil) }
            case 14: doc.convertLineEndings(to: [LineEnding.lf, .crlf, .cr].randomElement(using: &rng)!)
            case 15: v.sci(SCI_SELECTALL); v.sci(SCI_COPY); v.sci(SCI_GOTOPOS, pos()); v.sci(SCI_PASTE)
            case 16: v.setString(String(repeating: "reset line with words 日本 🎉\n", count: 50))
            case 17: doc.setLanguage(Language.all.randomElement(using: &rng)!)
            case 18: v.sci(SCI_LINESCROLL, Int.random(in: -50...50, using: &rng), Int.random(in: -200...200, using: &rng))
            case 19, 20: // resize the window (terminals re-layout while output floods)
                if let w = window, let scr = w.screen?.visibleFrame {
                    w.setFrame(NSRect(x: scr.minX, y: scr.minY, width: CGFloat.random(in: 520...scr.width, using: &rng),
                                      height: CGFloat.random(in: 360...scr.height, using: &rng)), display: true)
                }
            case 21: if console.sessions.count > 0 { console.toggleSideBySide(at: Int.random(in: 0..<console.sessions.count, using: &rng)) }
            case 22: if documents.count > 0 { toggleSideBySide(at: Int.random(in: 0..<documents.count, using: &rng)) }
            case 23: if !documents.isEmpty { select(Int.random(in: 0..<documents.count, using: &rng)) }
            case 24: AppSettings.shared.tabWidth = Int.random(in: 1...8, using: &rng)
            case 25: doc.toggleBookmark(line: Int.random(in: 0..<max(1, v.sci(SCI_GETLINECOUNT)), using: &rng))
            case 26: v.sci(SCI_SETSEL, pos(), pos()); v.sci(SCI_CUT)
            default: AppSettings.shared.showWhitespace.toggle()
            }
            window?.displayIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { tick() }
        }
        tick()
    }

    /// Development aid (LASTNOTE_STRESS_SCROLL=seconds): real scroll-wheel events (as a trackpad or
    /// mouse sends them) over the editor text, the line-number margin and the console.
    func runScrollStress(seconds: Double) {
        var rng = SystemRandomNumberGenerator()
        let end = Date().addingTimeInterval(seconds)
        let keepText = ProcessInfo.processInfo.environment["LASTNOTE_STRESS_KEEPTEXT"] == "1"
        if !keepText {
            setConsoleVisible(true)
            console.run("for i in $(seq 1 3000); do echo \"scrollback line $i\"; done")
        }
        if !keepText, let doc = current {
            doc.view.setString((1...3000).map { "line \($0): def fn(self, x):  # some text to scroll through" }.joined(separator: "\n"))
            doc.setLanguage(Language.all.first { $0.name == "Python" }!)
        }
        var step = 0
        func tick() {
            guard Date() < end, let window, let content = window.contentView else {
                print("scroll stress: done after \(step) steps")
                exit(0)
            }
            step += 1
            if !keepText, step % 400 == 0 { toggleSideBySide(at: 0) }  // change pane layout now and then
            // Pick a target: editor text, margin (left edge of the editor) or console.
            let targets: [(NSView, CGFloat)] = console.isHidden ? [(editorHost, 0.5), (editorHost, 0.02)]
                : [(editorHost, 0.5), (editorHost, 0.02), (console.bodyView, 0.5)]
            let (view, fx) = targets.randomElement(using: &rng)!
            let r = view.convert(view.bounds, to: nil)
            let pInWindow = NSPoint(x: r.minX + r.width * fx + 3, y: r.minY + r.height * CGFloat.random(in: 0.1...0.9, using: &rng))
            let screenPoint = window.convertPoint(toScreen: pInWindow)
            let mainHeight = NSScreen.screens.first?.frame.height ?? 0
            let dy = Int32.random(in: -40...40, using: &rng)
            if ProcessInfo.processInfo.environment["LASTNOTE_STRESS_GESTURE"] == "1" {
                // A trackpad-style gesture posted to the app's event queue: began, changed…, ended, then
                // momentum began, changed…, ended. AppKit routes it (responsive scrolling path).
                let loc = CGPoint(x: screenPoint.x, y: mainHeight - screenPoint.y)
                func post(_ delta: Int32, phase: Int64, momentum: Int64) {
                    guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else { return }
                    cg.location = loc
                    cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                    cg.setIntegerValueField(CGEventField(rawValue: 99)!, value: phase)      // kCGScrollWheelEventScrollPhase
                    cg.setIntegerValueField(CGEventField(rawValue: 123)!, value: momentum)  // kCGScrollWheelEventMomentumPhase
                    cg.setIntegerValueField(CGEventField(rawValue: 91)!, value: Int64(window.windowNumber))
                    cg.setIntegerValueField(CGEventField(rawValue: 92)!, value: Int64(window.windowNumber))
                    if let e = NSEvent(cgEvent: cg) {
                        let hit = content.superview?.hitTest(pInWindow) ?? content
                        hit.scrollWheel(with: e)
                    }
                }
                let sign: Int32 = Bool.random(using: &rng) ? 1 : -1
                post(0, phase: 1, momentum: 0)                                         // began
                for _ in 0..<Int.random(in: 3...12, using: &rng) { post(sign * Int32.random(in: 5...60, using: &rng), phase: 2, momentum: 0) } // changed
                post(0, phase: 4, momentum: 0)                                         // ended
                post(sign * 40, phase: 0, momentum: 1)                                 // momentum began
                for i in 0..<Int.random(in: 5...25, using: &rng) { post(sign * Int32(max(1, 40 - i * 2)), phase: 0, momentum: 2) }
                post(0, phase: 0, momentum: 3)                                         // momentum ended
            } else if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: Int32.random(in: -3...3, using: &rng), wheel3: 0) {
                cg.location = CGPoint(x: screenPoint.x, y: mainHeight - screenPoint.y)  // CG uses top-left origin
                if let e = NSEvent(cgEvent: cg) {
                    let hit = content.superview?.hitTest(pInWindow) ?? content
                    hit.scrollWheel(with: e)
                }
            }
            // Mouse movement over the same spot (cursor areas update as the content scrolls).
            if let move = NSEvent.mouseEvent(with: .mouseMoved, location: pInWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
                window.sendEvent(move)
            }
            window.displayIfNeeded()
            if step % 200 == 0, let v = current?.view { print("scroll stress: first visible line \(v.sci(SCI_GETFIRSTVISIBLELINE))") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.004) { tick() }
        }
        tick()
    }

    /// Stress aid: a real click (mouse-down/up through the view's own handling) on a random tab or
    /// its × button. Skips tabs with unsaved changes so no save prompt appears.
    private func stressClick(in bar: TabBar, closeButton: Bool, rng: inout SystemRandomNumberGenerator, clicks: Int = 1) {
        guard let window, let stack = bar.subviews.first(where: { $0 is NSStackView }) as? NSStackView,
              let tab = stack.arrangedSubviews.randomElement(using: &rng) else { return }
        if bar === tabBar, let i = stack.arrangedSubviews.firstIndex(of: tab), documents.indices.contains(i), documents[i].isDirty { return }
        let targetView: NSView = closeButton ? (tab.subviews.first { $0 is NSButton } ?? tab) : tab
        window.layoutIfNeeded()
        let p = targetView.convert(NSPoint(x: targetView.bounds.midX, y: targetView.bounds.midY), to: nil)
        guard let root = window.contentView?.superview, let hit = root.hitTest(p) else { return }
        for c in 1...clicks {
            func ev(_ t: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: c, pressure: 1)!
            }
            NSApp.postEvent(ev(.leftMouseUp), atStart: false)
            hit.mouseDown(with: ev(.leftMouseDown))
            if let up = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) { hit.mouseUp(with: up) }
        }
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

    /// File ▸ Open Recent ▸ <file>.
    @objc func openRecentFile(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        guard FileManager.default.fileExists(atPath: path) else {
            NSSound.beep()
            RecentFiles.shared.remove(path)
            return
        }
        open(urls: [URL(fileURLWithPath: path)])
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

    /// Run an editing command; while recording a macro it's recorded as one step (not as the
    /// individual Scintilla messages it sends).
    private func editCommand(_ selector: Selector, _ body: (Document) -> Void) {
        guard let doc = current else { return }
        macros.record(.command(selector))
        doc.quietly { body(doc) }
    }

    @objc func duplicateLine(_ sender: Any?) { editCommand(#selector(duplicateLine(_:))) { $0.view.sci(SCI_SELECTIONDUPLICATE) } }
    @objc func deleteLine(_ sender: Any?) { editCommand(#selector(deleteLine(_:))) { $0.view.sci(SCI_LINEDELETE) } }
    @objc func moveLinesUp(_ sender: Any?) { editCommand(#selector(moveLinesUp(_:))) { $0.view.sci(SCI_MOVESELECTEDLINESUP) } }
    @objc func moveLinesDown(_ sender: Any?) { editCommand(#selector(moveLinesDown(_:))) { $0.view.sci(SCI_MOVESELECTEDLINESDOWN) } }
    @objc func uppercaseSelection(_ sender: Any?) { editCommand(#selector(uppercaseSelection(_:))) { $0.view.sci(SCI_UPPERCASE) } }
    @objc func lowercaseSelection(_ sender: Any?) { editCommand(#selector(lowercaseSelection(_:))) { $0.view.sci(SCI_LOWERCASE) } }
    @objc func toggleComment(_ sender: Any?) { editCommand(#selector(toggleComment(_:))) { $0.toggleLineComment() } }
    @objc func trimTrailingWhitespace(_ sender: Any?) { editCommand(#selector(trimTrailingWhitespace(_:))) { $0.trimTrailingWhitespace() } }
    @objc func sortLinesAscending(_ sender: Any?) { editCommand(#selector(sortLinesAscending(_:))) { $0.sortLines(descending: false) } }
    @objc func sortLinesDescending(_ sender: Any?) { editCommand(#selector(sortLinesDescending(_:))) { $0.sortLines(descending: true) } }
    @objc func joinLines(_ sender: Any?) {
        editCommand(#selector(joinLines(_:))) {
            $0.view.sci(SCI_TARGETFROMSELECTION)
            $0.view.sci(SCI_LINESJOIN)
        }
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

    @objc func toggleBookmark(_ sender: Any?) { editCommand(#selector(toggleBookmark(_:))) { $0.toggleBookmark() } }
    @objc func nextBookmark(_ sender: Any?) { editCommand(#selector(nextBookmark(_:))) { $0.gotoBookmark(forward: true) } }
    @objc func previousBookmark(_ sender: Any?) { editCommand(#selector(previousBookmark(_:))) { $0.gotoBookmark(forward: false) } }

    // MARK: Sessions

    /// Snapshot the current workspace.
    func captureSession(name: String, includeTabs: Bool) -> SavedSession {
        var session = SavedSession(
            name: name, savedAt: Date(),
            windowFrame: NSStringFromRect(window?.frame ?? .zero),
            consoleVisible: !console.isHidden,
            consoleHeight: Double(console.isHidden ? lastConsoleHeight : console.frame.height),
            look: AppSettings.shared.snapshot())
        if includeTabs {
            session.files = documents.compactMap { d in
                d.url.map { SavedSession.File(path: $0.path, name: d.customName, tint: d.tint?.hexString) }
            }
            session.selectedFile = current?.url?.path
            session.consoleTabs = console.sessions.map { .init(name: $0.customName, tint: $0.tint?.hexString) }
            if visibleDocs.count > 1 { session.visibleFiles = visibleDocs.compactMap { $0.url?.path } }
            if console.visibleSessions.count > 1 { session.visibleConsoleTabs = console.visibleIndices }
        }
        return session
    }

    /// Restore a session. Returns the paths of files that no longer exist, or nil if the user
    /// cancelled (e.g. at a save prompt).
    @discardableResult
    func applySession(_ session: SavedSession) -> [String]? {
        var missing: [String] = []
        if let files = session.files {
            guard confirmCloseAll() else { return nil }
            for d in documents { d.view.removeFromSuperview() }
            documents.removeAll()
            visibleDocs.removeAll()
            selectedIndex = -1
            newDocument(nil)  // placeholder; replaced by the first file opened
            let existing = files.filter { FileManager.default.fileExists(atPath: $0.path) }
            open(urls: existing.map { URL(fileURLWithPath: $0.path) })
            for f in existing {
                guard let doc = documents.first(where: { $0.url?.path == f.path }) else { continue }
                doc.customName = f.name
                doc.tint = f.tint.flatMap { NSColor(hex: $0) }
            }
            if let sel = session.selectedFile, let i = documents.firstIndex(where: { $0.url?.path == sel }) { select(i) }
            if let paths = session.visibleFiles {
                let docs = paths.compactMap { p in documents.first { $0.url?.path == p } }.prefix(PaneArea.maxPanes)
                if docs.count > 1 {
                    visibleDocs = Array(docs)
                    if let cur = current, !visibleDocs.contains(where: { $0 === cur }) {
                        selectedIndex = documents.firstIndex { $0 === visibleDocs[0] } ?? selectedIndex
                    }
                    layoutEditorPanes()
                    refreshTabs()
                }
            }
            missing = files.map(\.path).filter { !FileManager.default.fileExists(atPath: $0) }
        }
        AppSettings.shared.apply(session.look)
        if let tabs = session.consoleTabs {
            console.replaceSessions(with: tabs.map { ($0.name, $0.tint.flatMap { NSColor(hex: $0) }) })
            if let visible = session.visibleConsoleTabs { console.setVisible(indices: visible) }
        }
        if let window {
            var frame = NSRectFromString(session.windowFrame)
            if frame.width >= window.minSize.width, frame.height >= window.minSize.height {
                // Keep it on a screen that still exists.
                if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }), let main = NSScreen.main {
                    frame.origin = NSPoint(x: main.visibleFrame.midX - frame.width / 2, y: main.visibleFrame.midY - frame.height / 2)
                }
                window.setFrame(frame, display: true, animate: false)
            }
        }
        lastConsoleHeight = CGFloat(session.consoleHeight)
        setConsoleVisible(session.consoleVisible, focus: false)
        SessionStore.shared.markActive(session.name)
        applyAppearance()
        return missing
    }

    @objc func saveSession(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Save Session"
        alert.informativeText = "Saves the window and console size, transparency, colours and fonts."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Session name"
        field.stringValue = UserDefaults.standard.string(forKey: "activeSession") ?? ""
        let include = NSButton(checkboxWithTitle: "Include open files and console tabs (with their names and colours)", target: nil, action: nil)
        include.state = .on
        let stack = NSStackView(views: [field, include])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 420, height: 56)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { NSSound.beep(); return }
        if SessionStore.shared.session(named: name) != nil {
            let confirm = NSAlert()
            confirm.messageText = "Replace the session “\(name)”?"
            confirm.addButton(withTitle: "Replace")
            confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
        }
        SessionStore.shared.save(captureSession(name: name, includeTabs: include.state == .on))
    }

    @objc func loadSession(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let s = SessionStore.shared.session(named: name) else { return }
        if s.includesTabs, !console.sessions.isEmpty || documents.contains(where: { $0.url != nil }) {
            let alert = NSAlert()
            alert.messageText = "Load the session “\(name)”?"
            alert.informativeText = "Your open tabs and console tabs will be replaced (you'll be asked to save changes). Running console commands will be stopped."
            alert.addButton(withTitle: "Load")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        guard let missing = applySession(s), !missing.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "\(missing.count) file\(missing.count == 1 ? "" : "s") in “\(name)” no longer exist\(missing.count == 1 ? "s" : "")."
        alert.informativeText = missing.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: "\n")
        alert.runModal()
    }

    @objc func deleteSession(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let alert = NSAlert()
        alert.messageText = "Delete the session “\(name)”?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        SessionStore.shared.delete(name: name)
    }

    @objc func showSessionsMenu(_ sender: Any?) {
        let menu = SessionMenuController.shared.makeMenu()
        if let button = sender as? NSView ?? iconBar.buttons[#selector(showSessionsMenu(_:))] {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: button)
        }
    }

    // MARK: Menu actions — Macro

    @objc func toggleMacroRecording(_ sender: Any?) {
        if macros.isRecording {
            macros.stop()
            documents.forEach { $0.view.sci(SCI_STOPRECORD) }
        } else {
            macros.start()
            documents.forEach { $0.view.sci(SCI_STARTRECORD) }
            focusEditor(nil)
        }
    }

    @objc func playMacro(_ sender: Any?) { playMacroSteps(macros.current) }

    @objc func runSavedMacro(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let m = macros.saved.first(where: { $0.name == name }) else { return }
        playMacroSteps(m.steps)
    }

    /// Replay steps on the current document. The whole run is one undo step.
    /// Returns how many times the macro ran.
    @discardableResult
    func playMacroSteps(_ steps: [MacroStep], times: Int = 1, untilEndOfFile: Bool = false) -> Int {
        guard let doc = current, !steps.isEmpty, !macros.isRecording else { NSSound.beep(); return 0 }
        let v = doc.view
        var runs = 0
        macros.playing {
            v.sci(SCI_BEGINUNDOACTION)
            defer { v.sci(SCI_ENDUNDOACTION) }
            while runs < 1_000_000 {
                let beforePos = v.sci(SCI_GETCURRENTPOS)
                let beforeLine = v.sci(SCI_LINEFROMPOSITION, beforePos)
                for step in steps { apply(step, to: doc) }
                runs += 1
                if !untilEndOfFile {
                    if runs >= times { break }
                    continue
                }
                // "Until end of file": stop at the end, when nothing moved, or when a run on the
                // last line didn't move to another line.
                let pos = v.sci(SCI_GETCURRENTPOS)
                let line = v.sci(SCI_LINEFROMPOSITION, pos)
                let lastLine = v.sci(SCI_GETLINECOUNT) - 1
                if pos >= v.sci(SCI_GETLENGTH) && line >= lastLine && beforeLine >= lastLine { break }
                if pos == beforePos { break }
                if line == beforeLine && line >= lastLine { break }
            }
        }
        return runs
    }

    private func apply(_ step: MacroStep, to doc: Document) {
        switch step.kind {
        case .sci:
            step.applySci(to: doc.view)
            // Typed newlines normally trigger auto-indent via the "character added" notification,
            // which replayed text doesn't fire.
            if step.message == SCI_REPLACESEL, let t = step.text, t.hasSuffix("\n") || t.hasSuffix("\r") { doc.autoIndent() }
        case .command:
            if let name = step.command { _ = perform(NSSelectorFromString(name), with: nil) }
        case .find:
            findBar.perform(step)
        }
    }

    @objc func runMacroMultipleTimes(_ sender: Any?) {
        var choices: [(String, [MacroStep])] = []
        if !macros.current.isEmpty { choices.append(("Current recorded macro", macros.current)) }
        choices += macros.saved.map { ($0.name, $0.steps) }
        guard !choices.isEmpty else { NSSound.beep(); return }

        let alert = NSAlert()
        alert.messageText = "Run a Macro Multiple Times"
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: choices.map(\.0))
        let timesRadio = NSButton(radioButtonWithTitle: "Run", target: nil, action: nil)
        let count = NSTextField(string: "2")
        count.widthAnchor.constraint(equalToConstant: 60).isActive = true
        let eofRadio = NSButton(radioButtonWithTitle: "Run until the end of file", target: nil, action: nil)
        timesRadio.state = .on
        let radioGroup = RadioGroup([timesRadio, eofRadio])
        let timesRow = NSStackView(views: [timesRadio, count, NSTextField(labelWithString: "times")])
        let stack = NSStackView(views: [popup, timesRow, eofRadio])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: 90)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = radioGroup
        let steps = choices[popup.indexOfSelectedItem].1
        if eofRadio.state == .on {
            playMacroSteps(steps, untilEndOfFile: true)
        } else {
            playMacroSteps(steps, times: max(1, Int(count.stringValue) ?? 1))
        }
    }

    @objc func saveCurrentMacro(_ sender: Any?) {
        guard !macros.current.isEmpty else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "Save Current Recorded Macro"
        alert.informativeText = "The first nine saved macros get the shortcuts ⌃⌥1 … ⌃⌥9."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Macro name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { NSSound.beep(); return }
        macros.save(name: name, steps: macros.current)
    }

    @objc func deleteSavedMacro(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let alert = NSAlert()
        alert.messageText = "Delete the macro “\(name)”?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        macros.delete(name: name)
    }
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
        case #selector(toggleMacroRecording(_:)):
            item.title = macros.isRecording ? "Stop Recording" : "Start Recording"
        case #selector(playMacro(_:)),
             #selector(saveCurrentMacro(_:)):
            return !macros.isRecording && !macros.current.isEmpty
        case #selector(runSavedMacro(_:)), #selector(runMacroMultipleTimes(_:)):
            return !macros.isRecording
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

/// Makes a set of radio buttons mutually exclusive (they don't share a superview action).
final class RadioGroup: NSObject {
    private let buttons: [NSButton]

    init(_ buttons: [NSButton]) {
        self.buttons = buttons
        super.init()
        for b in buttons { b.target = self; b.action = #selector(picked(_:)) }
    }

    @objc private func picked(_ sender: NSButton) {
        for b in buttons { b.state = b === sender ? .on : .off }
    }
}
