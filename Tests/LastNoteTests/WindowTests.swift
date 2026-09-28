import AppKit
import XCTest
import SciKit
import SwiftTerm
@testable import LastNote

/// End-to-end tests against a real main window, real Scintilla views and real shells.
final class WindowTests: XCTestCase {
    var tmp: TempDir!
    var wc: MainWindowController!

    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        resetSettings()
        UserDefaults.standard.set(false, forKey: "consoleVisible")
        tmp = TempDir()
        wc = MainWindowController()
        wc.newDocument(nil)
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        waitUntil(1) { false }  // let deferred layout run
    }

    override func tearDown() {
        wc.console.sessions.forEach { $0.terminate() }
        wc.window?.orderOut(nil)
        wc = nil
    }

    private func terminalText(_ session: ConsoleSession) -> String {
        String(data: session.terminal.getTerminal().getBufferAsData(), encoding: .utf8) ?? ""
    }

    // MARK: Documents & tabs

    func testOpeningReplacesUntouchedNewTab() {
        XCTAssertEqual(wc.documents.count, 1)
        let a = tmp.file("a.py", "print(1)\n"), b = tmp.file("b.sql", "select 1;\n")
        wc.open(urls: [a, b])
        XCTAssertEqual(wc.documents.map(\.displayName), ["a.py", "b.sql"])
        XCTAssertEqual(wc.current?.displayName, "b.sql")
        wc.open(urls: [a])  // already open: just selected
        XCTAssertEqual(wc.documents.count, 2)
        XCTAssertEqual(wc.current?.displayName, "a.py")
    }

    func testTabNavigationAndClosing() {
        wc.open(urls: [tmp.file("1.txt", "1"), tmp.file("2.txt", "2"), tmp.file("3.txt", "3")])
        wc.select(0)
        wc.selectNextTab(nil)
        XCTAssertEqual(wc.current?.displayName, "2.txt")
        wc.selectPreviousTab(nil)
        wc.selectPreviousTab(nil)  // wraps
        XCTAssertEqual(wc.current?.displayName, "3.txt")
        wc.closeDocument(at: 2)
        XCTAssertEqual(wc.documents.count, 2)
        wc.closeDocument(at: 0)
        wc.closeDocument(at: 0)
        // Closing the last tab leaves a fresh empty one, like Notepad++.
        XCTAssertEqual(wc.documents.count, 1)
        XCTAssertNil(wc.current?.url)
    }

    func testInlineRenameCallbackAndReset() {
        wc.open(urls: [tmp.file("q.sql", "select 1;")])
        wc.tabBar.onRename?(0, "Daily report")
        XCTAssertEqual(wc.current?.displayName, "Daily report")
        XCTAssertEqual(wc.window?.title, "Daily report")
        wc.tabBar.onRename?(0, "")
        XCTAssertEqual(wc.current?.displayName, "q.sql")
    }

    func testRenameMenuItemsExist() {
        wc.open(urls: [tmp.file("q.sql", "select 1;")])
        let titles = wc.menu(forDocumentAt: 0)?.items.map(\.title) ?? []
        XCTAssertTrue(titles.contains("Tab Colour"))
        XCTAssertTrue(titles.contains("Rename Tab…"))
        wc.current?.customName = "X"
        XCTAssertTrue(wc.menu(forDocumentAt: 0)?.items.map(\.title).contains("Reset Tab Name") ?? false)
    }

    func testInlineRenameFieldCommitsOnEnter() throws {
        wc.open(urls: [tmp.file("q.sql", "select 1;")])
        wc.tabBar.beginRename(at: 0)
        let field = try XCTUnwrap(wc.window?.firstResponder as? NSTextView, "rename field didn't take focus")
        field.string = "Renamed"
        field.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertTrue(waitUntil(1) { self.wc.current?.displayName == "Renamed" })
    }

    // MARK: Tints & transparency

    func testRegionColours() {
        let s = AppSettings.shared
        let red = NSColor(hex: "#B3261E")!
        s.transparencyEnabled = true
        s.opacity = 0.5
        XCTAssertEqual(wc.regionColor(for: nil).alphaComponent, 0.5, accuracy: 0.01)
        XCTAssertEqual(wc.regionColor(for: nil).withAlphaComponent(1).hexString, s.tintColor.hexString)
        XCTAssertEqual(wc.regionColor(for: red).withAlphaComponent(1).hexString, "#B3261E")
        s.transparencyEnabled = false
        let bg = Theme.dark.background
        XCTAssertEqual(wc.regionColor(for: nil).hexString, bg.hexString)
        XCTAssertEqual(wc.regionColor(for: nil).alphaComponent, 1)
        let wash = wc.regionColor(for: red)
        XCTAssertNotEqual(wash.hexString, bg.hexString)
        XCTAssertNotEqual(wash.hexString, "#B3261E")  // a readable wash, not the raw colour
    }

    func testDocumentTintPaintsEditorArea() {
        wc.open(urls: [tmp.file("t.txt", "x")])
        AppSettings.shared.transparencyEnabled = true
        waitUntil(0.3) { false }
        wc.current?.tint = NSColor(hex: "#2E7D32")
        let painted = wc.editorPanes.hosts.first?.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) }
        XCTAssertEqual(painted?.withAlphaComponent(1).hexString, "#2E7D32")
        XCTAssertEqual(painted?.alphaComponent ?? 0, CGFloat(AppSettings.shared.opacity), accuracy: 0.01)
    }

    func testWindowOpacityFollowsTransparencySetting() {
        let s = AppSettings.shared
        s.transparencyEnabled = true
        XCTAssertTrue(waitUntil(2) { self.wc.window?.isOpaque == false })
        s.transparencyEnabled = false
        XCTAssertTrue(waitUntil(2) { self.wc.window?.isOpaque == true })
    }

    // MARK: Console

    func testConsoleTabsLifecycle() {
        wc.setConsoleVisible(true)
        XCTAssertEqual(wc.console.sessions.count, 1)
        wc.newConsoleTab(nil)
        wc.newConsoleTab(nil)
        XCTAssertEqual(wc.console.sessions.map(\.name).count, 3)
        XCTAssertTrue(wc.console.active === wc.console.sessions[2])
        wc.console.selectNext(1)  // wraps to the first
        XCTAssertTrue(wc.console.active === wc.console.sessions[0])
        wc.console.tabBar.onRename?(0, "build")
        XCTAssertEqual(wc.console.sessions[0].name, "build")
        let teal = NSColor(hex: "#00796B")!
        wc.console.setTint(teal, for: wc.console.sessions[0])
        XCTAssertEqual(wc.console.sessions[0].container.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) }?.withAlphaComponent(1).hexString,
                       wc.regionColor(for: teal).withAlphaComponent(1).hexString)
        wc.console.closeSession(at: 1)
        XCTAssertEqual(wc.console.sessions.count, 2)
        wc.console.closeSession(at: 0)
        wc.console.closeSession(at: 0)
        XCTAssertTrue(wc.console.sessions.isEmpty)
        XCTAssertFalse(wc.isConsoleVisible, "closing the last console tab hides the console")
    }

    func testShellRunsCommands() throws {
        wc.setConsoleVisible(true)
        let session = try XCTUnwrap(wc.console.active)
        session.run("echo LN_$((6*7))")
        XCTAssertTrue(waitUntil(15) { self.terminalText(session).contains("LN_42") }, terminalText(session))
    }

    func testSeparateSessionsAreIndependentShells() throws {
        wc.setConsoleVisible(true)
        let first = try XCTUnwrap(wc.console.active)
        let second = wc.console.addSession()
        first.run("export LN_WHO=first; echo A_$LN_WHO")
        second.run("echo B_${LN_WHO:-unset}")
        XCTAssertTrue(waitUntil(15) { self.terminalText(first).contains("A_first") })
        XCTAssertTrue(waitUntil(15) { self.terminalText(second).contains("B_unset") }, terminalText(second))
    }

    func testRunFileInConsole() throws {
        wc.open(urls: [tmp.file("hello.py", "print('LN' + str(6 * 7))\n")])
        wc.runInConsole(nil)
        let session = try XCTUnwrap(wc.console.active)
        XCTAssertTrue(wc.isConsoleVisible)
        XCTAssertTrue(waitUntil(20) { self.terminalText(session).contains("LN42") }, terminalText(session))
    }

    func testShellExitClosesItsTab() throws {
        wc.setConsoleVisible(true)
        wc.newConsoleTab(nil)
        XCTAssertEqual(wc.console.sessions.count, 2)
        wc.console.active?.run("exit")
        XCTAssertTrue(waitUntil(15) { self.wc.console.sessions.count == 1 })
    }

    func testCloseTabIsContextAware() {
        wc.open(urls: [tmp.file("keep.txt", "k")])
        wc.setConsoleVisible(true)
        wc.newConsoleTab(nil)
        wc.console.focus()
        XCTAssertTrue(wc.console.containsFirstResponder)
        wc.closeTab(nil)  // ⌘W with the console focused closes the console tab
        XCTAssertEqual(wc.console.sessions.count, 1)
        XCTAssertEqual(wc.current?.displayName, "keep.txt")
        wc.focusEditor(nil)
        wc.closeTab(nil)
        XCTAssertNil(wc.current?.url)
    }

    // MARK: Focus glow

    func testFocusGlowFollowsFocus() throws {
        guard wc.window?.isKeyWindow == true else { throw XCTSkip("test runner window isn't key") }
        wc.setConsoleVisible(true)
        wc.focusEditor(nil)
        XCTAssertTrue(waitUntil(2) { self.glowCovers(self.wc.editorHost) })
        wc.console.focus()
        XCTAssertTrue(waitUntil(2) { self.glowCovers(self.wc.console.bodyView) })
        AppSettings.shared.focusGlowEnabled = false
        XCTAssertTrue(waitUntil(2) { self.wc.focusGlow.alphaValue == 0 })
    }

    func testFocusRegionFollowsFirstResponder() throws {
        wc.setConsoleVisible(true)
        wc.focusEditor(nil)
        XCTAssertTrue(wc.focusRegion(for: wc.window?.firstResponder) === wc.editorHost)
        wc.console.focus()
        XCTAssertTrue(wc.focusRegion(for: wc.window?.firstResponder) === wc.console.bodyView)
        wc.showFind(nil)  // the find field has its own focus ring: no glow
        XCTAssertNil(wc.focusRegion(for: wc.window?.firstResponder))
        // The glow view itself goes exactly around a region and ignores the mouse.
        let glow = FocusGlowView()
        glow.show(around: NSRect(x: 10, y: 10, width: 100, height: 50), color: .white, strength: 0.4, animated: false)
        XCTAssertEqual(glow.frame, NSRect(x: 11, y: 11, width: 98, height: 48))
        XCTAssertEqual(glow.alphaValue, 1)
        XCTAssertNil(glow.hitTest(NSPoint(x: 20, y: 20)))
        glow.show(around: nil, color: .white, strength: 0.4, animated: false)
        XCTAssertEqual(glow.alphaValue, 0)
    }

    private func glowCovers(_ region: NSView) -> Bool {
        guard wc.focusGlow.alphaValue > 0.9, let content = wc.window?.contentView else { return false }
        let r = region.convert(region.bounds, to: content).insetBy(dx: 1, dy: 1)
        let g = wc.focusGlow.frame
        return abs(g.minX - r.minX) < 1 && abs(g.minY - r.minY) < 1 && abs(g.width - r.width) < 1 && abs(g.height - r.height) < 1
    }

    // MARK: Icon bar & title bar

    func testIconBarReflectsState() throws {
        let wrap = try XCTUnwrap(wc.iconBar.buttons[#selector(MainWindowController.toggleWordWrap(_:))] as? IconButton)
        XCTAssertFalse(wrap.isOn)
        wc.toggleWordWrap(nil)
        XCTAssertTrue(waitUntil(2) { wrap.isOn })
        wc.toggleWordWrap(nil)
        XCTAssertTrue(waitUntil(2) { !wrap.isOn })
        // Every icon's action is something the window actually implements (or the editor handles).
        let editorActions: Set<String> = ["cut:", "copy:", "paste:", "undo:", "redo:"]
        for group in IconBar.groups {
            for item in group where !editorActions.contains(NSStringFromSelector(item.action)) {
                XCTAssertTrue(wc.responds(to: item.action), "\(item.tip) → \(item.action) not implemented")
            }
        }
    }

    func testDoubleClickOnTitleRowZooms() throws {
        let window = try XCTUnwrap(wc.window)
        guard let screen = window.screen?.visibleFrame else { throw XCTSkip("no screen") }
        window.setFrame(NSRect(x: screen.minX + 20, y: screen.minY + 20, width: 900, height: 600), display: true)
        let bar = wc.iconBar
        // Empty spots of the title row (gaps, the path label) belong to the bar; icons stay buttons.
        let empty = NSPoint(x: bar.bounds.maxX - 40, y: bar.bounds.midY)
        XCTAssertTrue(bar.hitTest(bar.convert(empty, to: bar.superview)) === bar)
        let save = try XCTUnwrap(bar.buttons[#selector(MainWindowController.saveDocument(_:))])
        let onIcon = save.convert(NSPoint(x: save.bounds.midX, y: save.bounds.midY), to: bar.superview)
        XCTAssertTrue(bar.hitTest(onIcon) === save)
        let p = bar.convert(empty, to: nil)
        let e = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 2, pressure: 1)!
        bar.mouseDown(with: e)
        XCTAssertTrue(waitUntil(3) { window.frame.width > 900 + 50 }, "window didn't zoom: \(window.frame)")
    }

    func testWindowCanShrinkToItsMinimumSize() throws {
        let window = try XCTUnwrap(wc.window)
        wc.open(urls: [tmp.file("a.txt", "a"), tmp.file("b.txt", "b")])
        wc.setConsoleVisible(true)
        wc.showReplace(nil)  // the find/replace bar is the widest piece of UI
        for _ in 0..<2 {
            window.setFrame(NSRect(origin: window.frame.origin, size: window.minSize), display: true)
            waitUntil(0.3) { false }
            XCTAssertEqual(window.frame.width, window.minSize.width, accuracy: 1, "something forces a wider window")
            XCTAssertEqual(window.frame.height, window.minSize.height, accuracy: 1)
            wc.hideFindBar()
        }
    }

    // MARK: Menus

    func testEveryMenuActionIsHandled() {
        let menu = AppMenus.build()
        let appHandled: Set<String> = ["orderFrontStandardAboutPanel:", "hide:", "hideOtherApplications:", "unhideAllApplications:",
                                       "terminate:", "clearRecentDocuments:", "performMiniaturize:", "performZoom:", "toggleFullScreen:",
                                       "undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:", "showSettings:"]
        var missing: [String] = []
        func walk(_ m: NSMenu) {
            for item in m.items {
                if let sub = item.submenu { walk(sub) }
                guard let action = item.action else { continue }
                let name = NSStringFromSelector(action)
                if appHandled.contains(name) || item.target != nil { continue }
                if !wc.responds(to: action) { missing.append("\(item.title) (\(name))") }
            }
        }
        walk(menu)
        XCTAssertEqual(missing, [])
    }
}
