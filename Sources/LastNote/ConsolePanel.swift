import AppKit
import SwiftTerm
import SwiftUI

/// One shell running in a pseudo-terminal, shown as a console tab.
final class ConsoleSession: NSObject, LocalProcessTerminalViewDelegate {
    let number: Int
    var customName: String?
    var tint: NSColor?
    /// Title the shell set via escape sequence, if any.
    private(set) var shellTitle = ""
    /// Layer-backed view that paints this session's tint behind the terminal.
    let container = NSView()
    let terminal: LocalProcessTerminalView
    private(set) var running = false

    var onExit: ((ConsoleSession) -> Void)?
    var onTitleChange: (() -> Void)?

    var name: String {
        if let customName, !customName.isEmpty { return customName }
        let shell = ((ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") as NSString).lastPathComponent
        return "\(shell) \(number)"
    }

    init(number: Int) {
        self.number = number
        terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        super.init()
        container.wantsLayer = true
        terminal.translatesAutoresizingMaskIntoConstraints = false
        terminal.processDelegate = self
        container.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
        ])
    }

    func start(in directory: String) {
        guard !running else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("SHELL=\(shell)")
        env.append("TERM_PROGRAM=LastNote")
        if let path = ProcessInfo.processInfo.environment["PATH"] { env.append("PATH=\(path)") }
        // A leading "-" in argv[0] makes it a login shell, so ~/.zprofile etc. are sourced.
        let execName = "-" + (shell as NSString).lastPathComponent
        terminal.startProcess(executable: shell, args: [], environment: env, execName: execName,
                              currentDirectory: directory)
        running = true
    }

    func terminate() {
        if running { terminal.terminate() }
        running = false
    }

    /// Type a command into the shell as if the user had typed it.
    func run(_ command: String) { terminal.send(txt: command + "\r") }

    func applySettings(background: NSColor) {
        let settings = AppSettings.shared
        let theme = Theme.named(settings.theme)
        terminal.font = settings.consoleFont
        terminal.nativeForegroundColor = settings.consoleTextColor ?? theme.foreground
        terminal.nativeBackgroundColor = theme.background
        // Default background is drawn clear; the container's tint shows through.
        terminal.backgroundOpacity = 0
        terminal.caretColor = settings.consoleTextColor ?? theme.caret
        terminal.selectedTextBackgroundColor = theme.selection
        container.layer?.backgroundColor = background.cgColor
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        shellTitle = title
        onTitleChange?()
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async {
            self.running = false
            self.onExit?(self)
        }
    }
}

/// The console at the bottom of the window: tabs of interactive login shells.
final class ConsolePanel: NSView {
    private let header = NSView()
    let tabBar = TabBar(compact: true)
    private let body = NSView()
    private(set) var sessions: [ConsoleSession] = []
    /// Sessions shown side by side, left to right (1–3). The active session is one of them.
    private(set) var visibleSessions: [ConsoleSession] = []
    let panes = PaneArea()
    private var activeIndex = -1
    private var nextNumber = 1
    private let colorButton = ConsolePanel.headerButton("paintpalette", "Console tab colour")
    private let hideButton = ConsolePanel.headerButton("chevron.down", "Hide console (⌃`)")
    private let fontButton = ConsolePanel.headerButton("textformat", "Console font & colours")
    private lazy var fontPopover: NSPopover = {
        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = NSHostingController(rootView: ConsoleSettingsControls().padding(16).frame(width: 380))
        return p
    }()

    /// Called when the last shell exits or is closed.
    var onAllSessionsClosed: (() -> Void)?
    /// Called when the active session or a tint changes (the window repaints its backgrounds).
    var onChange: (() -> Void)?
    /// Folder to start new shells in.
    var startDirectory: () -> String = { NSHomeDirectory() }
    /// Background colour for a region with an optional tint override (provided by the window).
    var regionColor: (NSColor?) -> NSColor = { _ in .clear }

    var active: ConsoleSession? { sessions.indices.contains(activeIndex) ? sessions[activeIndex] : nil }
    /// The area behind the terminals (painted per-session rather than by the window tint).
    var bodyView: NSView { body }

    override init(frame: NSRect) {
        super.init(frame: frame)
        header.wantsLayer = true
        for v in [header, body, tabBar] { v.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(header)
        addSubview(body)
        tabBar.drawsBackground = false
        header.addSubview(tabBar)

        colorButton.target = self
        colorButton.action = #selector(showColorMenu(_:))
        hideButton.target = self
        hideButton.action = #selector(hideConsole)
        fontButton.target = self
        fontButton.action = #selector(showFontPopover(_:))
        let buttons = NSStackView(views: [fontButton, colorButton, hideButton])
        buttons.spacing = 4
        buttons.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(buttons)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 25),
            tabBar.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            tabBar.topAnchor.constraint(equalTo: header.topAnchor),
            tabBar.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            tabBar.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -8),
            buttons.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            buttons.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            body.topAnchor.constraint(equalTo: header.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: leadingAnchor),
            body.trailingAnchor.constraint(equalTo: trailingAnchor),
            body.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        tabBar.onSelect = { [weak self] in self?.select($0) }
        tabBar.onClose = { [weak self] in self?.closeSession(at: $0) }
        tabBar.onNew = { [weak self] in self?.addSession() }
        tabBar.menuForTab = { [weak self] in self?.menu(forSession: $0) }
        tabBar.onCommandClick = { [weak self] in self?.toggleSideBySide(at: $0) }
        panes.frame = body.bounds
        panes.autoresizingMask = [.width, .height]
        body.addSubview(panes)
        panes.onActivate = { [weak self] i in
            guard let self, self.visibleSessions.indices.contains(i),
                  let idx = self.sessions.firstIndex(where: { $0 === self.visibleSessions[i] }) else { return }
            self.select(idx)
        }
        panes.onRemove = { [weak self] i in
            guard let self, self.visibleSessions.indices.contains(i) else { return }
            self.removeFromSideBySide(self.visibleSessions[i])
        }
        tabBar.onRename = { [weak self] index, name in
            guard let self, self.sessions.indices.contains(index) else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            self.sessions[index].customName = trimmed.isEmpty ? nil : trimmed
            self.reloadTabs()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func headerButton(_ symbol: String, _ tip: String) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: nil, action: nil)
        b.isBordered = false
        b.toolTip = tip
        b.imageScaling = .scaleProportionallyDown
        b.widthAnchor.constraint(equalToConstant: 20).isActive = true
        return b
    }

    // MARK: Sessions

    func startShellIfNeeded() {
        if sessions.isEmpty { addSession(focus: false) }
    }

    @discardableResult
    func addSession(focus: Bool = true, tint: NSColor? = nil) -> ConsoleSession {
        let session = ConsoleSession(number: nextNumber)
        nextNumber += 1
        session.tint = tint
        session.onExit = { [weak self] s in
            guard let self, let i = self.sessions.firstIndex(where: { $0 === s }) else { return }
            self.removeSession(at: i)
        }
        session.onTitleChange = { [weak self] in self?.reloadTabs() }
        sessions.append(session)
        session.applySettings(background: regionColor(tint))
        select(sessions.count - 1, focus: focus)
        session.start(in: startDirectory())
        return session
    }

    /// Show a session. If it isn't already in a pane it replaces the active pane's session.
    func select(_ index: Int, focus: Bool = true) {
        guard sessions.indices.contains(index) else { return }
        let s = sessions[index]
        if !visibleSessions.contains(where: { $0 === s }) {
            if let a = active, let slot = visibleSessions.firstIndex(where: { $0 === a }) {
                visibleSessions[slot] = s
            } else {
                visibleSessions = [s]
            }
        }
        activeIndex = index
        layoutPanes()
        reloadTabs()
        if focus { self.focus() }
        onChange?()
    }

    private func layoutPanes() {
        let theme = Theme.named(AppSettings.shared.theme)
        // Session containers paint their own tint, so panes don't paint a background.
        panes.show(visibleSessions.map { PaneItem(view: $0.container, title: $0.name, tint: $0.tint, background: nil) },
                   active: visibleSessions.firstIndex { $0 === active } ?? 0, theme: theme)
    }

    // MARK: Side by side

    /// ⌘-click on a console tab: add it next to the others, or take it out.
    func toggleSideBySide(at index: Int) {
        guard sessions.indices.contains(index) else { return }
        let s = sessions[index]
        if visibleSessions.contains(where: { $0 === s }) {
            removeFromSideBySide(s)
        } else {
            guard visibleSessions.count < PaneArea.maxPanes else { NSSound.beep(); return }
            visibleSessions.append(s)
            select(index)
        }
    }

    func removeFromSideBySide(_ s: ConsoleSession) {
        guard visibleSessions.count > 1, let slot = visibleSessions.firstIndex(where: { $0 === s }) else { return }
        visibleSessions.remove(at: slot)
        if s === active {
            let next = visibleSessions[min(slot, visibleSessions.count - 1)]
            activeIndex = sessions.firstIndex { $0 === next } ?? activeIndex
        }
        layoutPanes()
        reloadTabs()
        focus()
        onChange?()
    }

    func showOnlyActive() {
        guard let a = active else { return }
        visibleSessions = [a]
        layoutPanes()
        reloadTabs()
        focus()
        onChange?()
    }

    /// Show these sessions side by side (used when restoring a saved session).
    func setVisible(indices: [Int]) {
        let chosen = indices.filter { sessions.indices.contains($0) }.prefix(PaneArea.maxPanes).map { sessions[$0] }
        guard !chosen.isEmpty else { return }
        visibleSessions = Array(chosen)
        activeIndex = sessions.firstIndex { $0 === chosen[0] } ?? activeIndex
        layoutPanes()
        reloadTabs()
        onChange?()
    }

    var visibleIndices: [Int] { visibleSessions.compactMap { s in sessions.firstIndex { $0 === s } } }

    /// Clicking into a console pane makes its session active.
    func followFocus(to responder: NSView) {
        guard let s = visibleSessions.first(where: { responder.isDescendant(of: $0.container) }), s !== active,
              let i = sessions.firstIndex(where: { $0 === s }) else { return }
        activeIndex = i
        layoutPanes()
        reloadTabs()
        onChange?()
    }

    /// The area to glow around when `view` has focus: its pane when split, else the whole body.
    func focusRegion(for view: NSView) -> NSView {
        if panes.paneCount > 1, let i = panes.pane(containing: view) { return panes.hosts[i] }
        return body
    }

    func selectNext(_ delta: Int) {
        guard !sessions.isEmpty else { return }
        select((activeIndex + delta + sessions.count) % sessions.count)
    }

    func closeSession(at index: Int) {
        guard sessions.indices.contains(index) else { return }
        sessions[index].onExit = nil
        sessions[index].terminate()
        removeSession(at: index)
    }

    func closeActiveSession() { closeSession(at: activeIndex) }

    /// Stop every shell and start fresh ones with these names/colours (used when loading a session).
    func replaceSessions(with tabs: [(name: String?, tint: NSColor?)]) {
        for s in sessions {
            s.onExit = nil
            s.terminate()
            s.container.removeFromSuperview()
        }
        sessions.removeAll()
        visibleSessions.removeAll()
        activeIndex = -1
        nextNumber = 1
        for tab in tabs {
            let s = addSession(focus: false, tint: tab.tint)
            s.customName = tab.name
        }
        if !sessions.isEmpty { select(0, focus: false) }
        reloadTabs()
    }

    private func removeSession(at index: Int) {
        let removed = sessions[index]
        let wasActive = index == activeIndex
        let slot = visibleSessions.firstIndex { $0 === removed }
        visibleSessions.removeAll { $0 === removed }
        removed.container.removeFromSuperview()
        sessions.remove(at: index)
        if sessions.isEmpty {
            activeIndex = -1
            nextNumber = 1
            layoutPanes()
            reloadTabs()
            onAllSessionsClosed?()
            return
        }
        if !visibleSessions.isEmpty {
            // Another side-by-side pane takes over (or the active one simply stays).
            let keep = wasActive ? visibleSessions[min(slot ?? 0, visibleSessions.count - 1)] : active ?? visibleSessions[0]
            activeIndex = sessions.firstIndex { $0 === keep } ?? 0
            layoutPanes()
            reloadTabs()
            if wasActive { focus() }
            onChange?()
        } else {
            activeIndex = -1
            select(min(index, sessions.count - 1))
        }
    }

    func setTint(_ tint: NSColor?, for session: ConsoleSession) {
        session.tint = tint
        session.container.layer?.backgroundColor = regionColor(tint).cgColor
        reloadTabs()
        onChange?()
    }

    private func menu(forSession index: Int) -> NSMenu? {
        guard sessions.indices.contains(index) else { return nil }
        let s = sessions[index]
        let menu = NSMenu()
        let colour = NSMenuItem(title: "Tab Colour", action: nil, keyEquivalent: "")
        colour.submenu = TintMenu.make(current: s.tint) { [weak self, weak s] c in
            if let s { self?.setTint(c, for: s) }
        }
        menu.addItem(colour)
        menu.addItem(ClosureMenuItem(title: "Rename Tab…") { [weak self] in self?.tabBar.beginRename(at: index) })
        menu.addItem(.separator())
        if visibleSessions.contains(where: { $0 === s }) {
            if visibleSessions.count > 1 {
                menu.addItem(ClosureMenuItem(title: "Remove from Side by Side") { [weak self] in self?.removeFromSideBySide(s) })
                menu.addItem(ClosureMenuItem(title: "Show Only This Tab") { [weak self] in
                    guard let self, let i = self.sessions.firstIndex(where: { $0 === s }) else { return }
                    self.visibleSessions = [s]
                    self.select(i)
                })
            }
        } else {
            let add = ClosureMenuItem(title: "Show Side by Side") { [weak self] in
                if let self, let i = self.sessions.firstIndex(where: { $0 === s }) { self.toggleSideBySide(at: i) }
            }
            add.isEnabled = visibleSessions.count < PaneArea.maxPanes
            menu.addItem(add)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "New Console Tab") { [weak self] in self?.addSession() })
        menu.addItem(ClosureMenuItem(title: "Duplicate (same colour)") { [weak self] in self?.addSession(tint: s.tint) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Close") { [weak self] in
            if let i = self?.sessions.firstIndex(where: { $0 === s }) { self?.closeSession(at: i) }
        })
        return menu
    }

    @objc func showFontPopover(_ sender: Any?) {
        if fontPopover.isShown { fontPopover.close(); return }
        fontPopover.show(relativeTo: fontButton.bounds, of: fontButton, preferredEdge: .maxY)
    }

    @objc func showColorMenu(_ sender: Any?) {
        guard let s = active else { return }
        let menu = TintMenu.make(current: s.tint) { [weak self, weak s] c in
            if let s { self?.setTint(c, for: s) }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: colorButton.bounds.height + 4), in: colorButton)
    }

    private func reloadTabs() {
        let theme = Theme.named(AppSettings.shared.theme)
        let multi = visibleSessions.count > 1
        tabBar.reload(items: sessions.map { s in
            .init(title: s.name, dirty: false, tooltip: s.shellTitle.isEmpty ? nil : s.shellTitle, tint: s.tint,
                  visible: multi && visibleSessions.contains { $0 === s })
        }, selected: activeIndex, theme: theme)
        if multi { layoutPanes() }  // pane headers show names/colours too
    }

    // MARK: Focus & commands

    var containsFirstResponder: Bool {
        guard let r = window?.firstResponder as? NSView else { return false }
        return r.isDescendant(of: self)
    }

    @objc private func hideConsole() {
        NSApp.sendAction(#selector(MainWindowController.toggleConsole(_:)), to: nil, from: self)
    }

    func focus() {
        if let t = active?.terminal { window?.makeFirstResponder(t) }
    }

    /// Type a command into the active shell.
    func run(_ command: String) {
        startShellIfNeeded()
        active?.run(command)
    }

    func cd(to directory: String) {
        let quoted = "'" + directory.replacingOccurrences(of: "'", with: "'\\''") + "'"
        run("cd \(quoted)")
    }

    // MARK: Appearance

    func applySettings() {
        let theme = Theme.named(AppSettings.shared.theme)
        for s in sessions { s.applySettings(background: regionColor(s.tint)) }
        header.layer?.backgroundColor = theme.chrome.cgColor
        for b in [fontButton, colorButton, hideButton] { b.contentTintColor = theme.chromeText }
        reloadTabs()
    }
}

extension ConsolePanel {
    /// Rename the active console tab inline.
    func renameActiveTab() { tabBar.beginRename(at: sessions.firstIndex { $0 === active } ?? -1) }
}
