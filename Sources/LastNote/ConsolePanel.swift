import AppKit
import SwiftTerm

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
        terminal.nativeForegroundColor = theme.foreground
        terminal.nativeBackgroundColor = theme.background
        // Default background is drawn clear; the container's tint shows through.
        terminal.backgroundOpacity = 0
        terminal.caretColor = theme.caret
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
    private var activeIndex = -1
    private var nextNumber = 1
    private let colorButton = ConsolePanel.headerButton("paintpalette", "Console tab colour")
    private let hideButton = ConsolePanel.headerButton("chevron.down", "Hide console (⌃`)")

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
        let buttons = NSStackView(views: [colorButton, hideButton])
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

    func select(_ index: Int, focus: Bool = true) {
        guard sessions.indices.contains(index) else { return }
        active?.container.removeFromSuperview()
        activeIndex = index
        let c = sessions[index].container
        c.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(c)
        NSLayoutConstraint.activate([
            c.topAnchor.constraint(equalTo: body.topAnchor), c.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            c.leadingAnchor.constraint(equalTo: body.leadingAnchor), c.trailingAnchor.constraint(equalTo: body.trailingAnchor),
        ])
        reloadTabs()
        if focus { self.focus() }
        onChange?()
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

    private func removeSession(at index: Int) {
        let wasActive = index == activeIndex
        sessions[index].container.removeFromSuperview()
        sessions.remove(at: index)
        if sessions.isEmpty {
            activeIndex = -1
            nextNumber = 1
            reloadTabs()
            onAllSessionsClosed?()
            return
        }
        if wasActive {
            activeIndex = -1
            select(min(index, sessions.count - 1))
        } else {
            if index < activeIndex { activeIndex -= 1 }
            reloadTabs()
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
        menu.addItem(ClosureMenuItem(title: "New Console Tab") { [weak self] in self?.addSession() })
        menu.addItem(ClosureMenuItem(title: "Duplicate (same colour)") { [weak self] in self?.addSession(tint: s.tint) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Close") { [weak self] in
            if let i = self?.sessions.firstIndex(where: { $0 === s }) { self?.closeSession(at: i) }
        })
        return menu
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
        tabBar.reload(items: sessions.map {
            .init(title: $0.name, dirty: false, tooltip: $0.shellTitle.isEmpty ? nil : $0.shellTitle, tint: $0.tint)
        }, selected: activeIndex, theme: theme)
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
        for b in [colorButton, hideButton] { b.contentTintColor = theme.chromeText }
        reloadTabs()
    }
}

extension ConsolePanel {
    /// Rename the active console tab inline.
    func renameActiveTab() { tabBar.beginRename(at: sessions.firstIndex { $0 === active } ?? -1) }
}
