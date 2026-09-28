import AppKit
import XCTest
import SciKit
@testable import LastNote

/// Up to three editor or console tabs shown side by side.
final class SideBySideTests: XCTestCase {
    var tmp: TempDir!
    var wc: MainWindowController!

    override func setUp() {
        _ = NSApplication.shared
        resetSettings()
        UserDefaults.standard.set(false, forKey: "consoleVisible")
        tmp = TempDir()
        wc = MainWindowController()
        wc.newDocument(nil)
        wc.showWindow(nil)
        wc.window?.setFrame(NSRect(x: 40, y: 40, width: 1200, height: 800), display: true)
        waitUntil(0.3) { false }
    }

    override func tearDown() {
        wc.console.sessions.forEach { $0.terminate() }
        wc.window?.orderOut(nil)
        wc = nil
    }

    private func openThree() {
        wc.open(urls: [tmp.file("a.txt", "A"), tmp.file("b.txt", "B"), tmp.file("c.txt", "C"), tmp.file("d.txt", "D")])
        wc.select(0)
    }

    private func onScreen(_ d: Document) -> Bool { d.view.window != nil }

    func testCommandClickAddsTabsSideBySideUpToThree() {
        openThree()
        wc.toggleSideBySide(at: 1)
        wc.toggleSideBySide(at: 2)
        XCTAssertEqual(wc.visibleDocs.map(\.fileName), ["a.txt", "b.txt", "c.txt"])
        XCTAssertTrue(wc.visibleDocs.allSatisfy(onScreen))
        XCTAssertEqual(wc.current?.fileName, "c.txt", "the tab just added becomes active")
        wc.toggleSideBySide(at: 3)  // a fourth is refused
        XCTAssertEqual(wc.visibleDocs.count, 3)
        XCTAssertFalse(onScreen(wc.documents[3]))
        // Panes share the width equally.
        waitUntil(0.2) { false }
        let widths = wc.editorPanes.hosts.map(\.frame.width)
        XCTAssertEqual(widths.count, 3)
        XCTAssertLessThan(widths.max()! - widths.min()!, 3, "\(widths)")
        XCTAssertEqual(widths.reduce(0, +), wc.editorHost.bounds.width, accuracy: 4)
    }

    func testCommandClickOnVisibleTabRemovesIt() {
        openThree()
        wc.toggleSideBySide(at: 1)
        wc.toggleSideBySide(at: 1)
        XCTAssertEqual(wc.visibleDocs.map(\.fileName), ["a.txt"])
        XCTAssertFalse(onScreen(wc.documents[1]))
        XCTAssertEqual(wc.current?.fileName, "a.txt")
        wc.toggleSideBySide(at: 0)  // the last visible tab can't be removed
        XCTAssertEqual(wc.visibleDocs.map(\.fileName), ["a.txt"])
    }

    func testClickingAHiddenTabReplacesTheActivePane() {
        openThree()
        wc.toggleSideBySide(at: 1)  // a | b, b active
        wc.select(3)                // d replaces b
        XCTAssertEqual(wc.visibleDocs.map(\.fileName), ["a.txt", "d.txt"])
        XCTAssertFalse(onScreen(wc.documents[1]))
        wc.select(0)                // a is visible: just becomes active
        XCTAssertEqual(wc.visibleDocs.map(\.fileName), ["a.txt", "d.txt"])
        XCTAssertEqual(wc.current?.fileName, "a.txt")
    }

    func testFocusFollowsClicksIntoPanes() {
        openThree()
        wc.toggleSideBySide(at: 1)
        let a = wc.documents[0]
        wc.window?.makeFirstResponder(a.view.content())
        XCTAssertTrue(waitUntil(1) { self.wc.current === a })
        XCTAssertTrue(wc.focusRegion(for: a.view.content()) === wc.editorPanes.hosts[0])
        // Typing goes to the active pane only.
        a.view.sci(SCI_APPENDTEXT, 1, string: "!")
        XCTAssertEqual(a.text, "A!")
        XCTAssertEqual(wc.documents[1].text, "B")
    }

    func testClosingAVisibleTabLetsANeighbourTakeOver() {
        openThree()
        wc.toggleSideBySide(at: 1)
        wc.toggleSideBySide(at: 2)  // a | b | c, c active
        wc.closeDocument(at: 2)
        XCTAssertEqual(wc.visibleDocs.map(\.fileName), ["a.txt", "b.txt"])
        XCTAssertEqual(wc.current?.fileName, "b.txt")
        wc.closeDocument(at: 0)     // close a non-active visible tab to the left of the active one
        XCTAssertEqual(wc.visibleDocs.map(\.fileName), ["b.txt"])
        XCTAssertEqual(wc.current?.fileName, "b.txt")
    }

    func testEachPaneKeepsItsTabColour() {
        openThree()
        wc.documents[0].tint = NSColor(hex: "#B3261E")
        wc.documents[1].tint = NSColor(hex: "#2E7D32")
        wc.toggleSideBySide(at: 1)
        let colours = wc.editorPanes.hosts.map { $0.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) } }
        XCTAssertEqual(colours[0]?.hexString, wc.regionColor(for: NSColor(hex: "#B3261E")).hexString)
        XCTAssertEqual(colours[1]?.hexString, wc.regionColor(for: NSColor(hex: "#2E7D32")).hexString)
    }

    func testShowOnlyActiveTab() {
        openThree()
        wc.toggleSideBySide(at: 1)
        wc.toggleSideBySide(at: 2)
        wc.focusEditor(nil)
        wc.showOnlyActiveTab(nil)
        XCTAssertEqual(wc.visibleDocs.map(\.fileName), ["c.txt"])
        XCTAssertEqual(wc.editorPanes.paneCount, 1)
    }

    func testContextMenuOffersSideBySide() {
        openThree()
        XCTAssertTrue(wc.menu(forDocumentAt: 1)?.items.map(\.title).contains("Show Side by Side") ?? false)
        wc.toggleSideBySide(at: 1)
        let titles = wc.menu(forDocumentAt: 1)?.items.map(\.title) ?? []
        XCTAssertTrue(titles.contains("Remove from Side by Side"))
        XCTAssertTrue(titles.contains("Show Only This Tab"))
    }

    func testSplitCommandWithOnlyOneTabCreatesANewOne() {
        XCTAssertEqual(wc.documents.count, 1)
        wc.focusEditor(nil)
        wc.splitAddNextTab(nil)
        XCTAssertEqual(wc.documents.count, 2)
        XCTAssertEqual(wc.visibleDocs.count, 2)
        XCTAssertTrue(wc.documents.allSatisfy(onScreen))
        wc.splitAddNextTab(nil)
        XCTAssertEqual(wc.visibleDocs.count, 3)
        wc.splitAddNextTab(nil)  // already three: nothing more
        XCTAssertEqual(wc.visibleDocs.count, 3)
        XCTAssertEqual(wc.documents.count, 3)
    }

    func testSplitCommandPrefersExistingHiddenTabs() {
        openThree()
        wc.focusEditor(nil)
        wc.splitAddNextTab(nil)
        XCTAssertEqual(wc.visibleDocs.map(\.fileName), ["a.txt", "b.txt"])
        XCTAssertEqual(wc.documents.count, 4, "no new tab when a hidden one exists")
    }

    func testSplitMenuListsTabsWithCheckmarks() {
        openThree()
        wc.toggleSideBySide(at: 2)
        let menu = wc.splitMenu(forConsole: false)
        let items = menu.items.filter { ["a.txt", "b.txt", "c.txt", "d.txt"].contains($0.title) }
        XCTAssertEqual(items.map(\.state), [.on, .off, .on, .off])
        // Picking an unchecked tab shows it; picking a checked one hides it.
        (items[1] as? ClosureMenuItem).map { _ = $0.target?.perform($0.action) }
        XCTAssertEqual(wc.visibleDocs.map(\.fileName), ["a.txt", "c.txt", "b.txt"])
        (items[0] as? ClosureMenuItem).map { _ = $0.target?.perform($0.action) }
        XCTAssertEqual(wc.visibleDocs.map(\.fileName), ["c.txt", "b.txt"])
    }

    // MARK: Console

    func testConsoleSplitWithOneShellOpensASecondSideBySide() throws {
        wc.setConsoleVisible(true)
        XCTAssertEqual(wc.console.sessions.count, 1)
        wc.console.focus()
        wc.splitAddNextTab(nil)  // ⌘\ with the console focused
        XCTAssertEqual(wc.console.sessions.count, 2)
        XCTAssertEqual(wc.console.visibleSessions.count, 2)
        XCTAssertTrue(wc.console.sessions.allSatisfy { $0.container.window != nil })
        let menu = wc.splitMenu(forConsole: true)
        XCTAssertEqual(menu.items.filter { $0.state == .on }.count, 2)
    }

    private func terminalText(_ s: ConsoleSession) -> String {
        String(data: s.terminal.getTerminal().getBufferAsData(), encoding: .utf8) ?? ""
    }

    func testTwoConsoleTabsSideBySideRunIndependently() throws {
        wc.setConsoleVisible(true)
        wc.newConsoleTab(nil)
        let c = wc.console
        XCTAssertEqual(c.sessions.count, 2)
        c.toggleSideBySide(at: 0)  // zsh 2 is showing; add zsh 1 next to it
        XCTAssertEqual(c.visibleSessions.count, 2)
        XCTAssertTrue(c.sessions.allSatisfy { $0.container.window != nil }, "both terminals on screen")
        waitUntil(0.2) { false }
        let widths = c.panes.hosts.map(\.frame.width)
        XCTAssertLessThan(abs(widths[0] - widths[1]), 3)
        c.sessions[0].run("echo LEFT_$((1+1))")
        c.sessions[1].run("echo RIGHT_$((2+2))")
        XCTAssertTrue(waitUntil(15) { self.terminalText(c.sessions[0]).contains("LEFT_2") })
        XCTAssertTrue(waitUntil(15) { self.terminalText(c.sessions[1]).contains("RIGHT_4") })
        // Focus into the left one makes it active.
        wc.window?.makeFirstResponder(c.sessions[0].terminal)
        XCTAssertTrue(waitUntil(1) { c.active === c.sessions[0] })
    }

    func testConsoleCloseAndShowOnly() {
        wc.setConsoleVisible(true)
        wc.newConsoleTab(nil)
        wc.newConsoleTab(nil)
        let c = wc.console
        c.toggleSideBySide(at: 0)
        c.toggleSideBySide(at: 1)
        XCTAssertEqual(c.visibleSessions.count, 3)
        c.closeSession(at: 2)
        XCTAssertEqual(c.visibleSessions.count, 2)
        XCTAssertEqual(c.panes.paneCount, 2)
        c.showOnlyActive()
        XCTAssertEqual(c.visibleSessions.count, 1)
        XCTAssertEqual(c.panes.paneCount, 1)
    }

    // MARK: Sessions

    func testSessionRemembersSideBySide() throws {
        openThree()
        wc.toggleSideBySide(at: 2)
        wc.setConsoleVisible(true)
        wc.newConsoleTab(nil)
        wc.console.toggleSideBySide(at: 0)
        let saved = wc.captureSession(name: "Split", includeTabs: true)
        XCTAssertEqual(saved.visibleFiles?.map { ($0 as NSString).lastPathComponent }, ["a.txt", "c.txt"])
        XCTAssertEqual(saved.visibleConsoleTabs?.sorted(), [0, 1])
        wc.showOnlyActiveTab(nil)
        wc.console.showOnlyActive()
        XCTAssertEqual(wc.applySession(saved), [])
        XCTAssertEqual(wc.visibleDocs.map(\.fileName), ["a.txt", "c.txt"])
        XCTAssertEqual(wc.console.visibleSessions.count, 2)
        // Old sessions without the new fields still load.
        var old = saved
        old.visibleFiles = nil
        old.visibleConsoleTabs = nil
        let decoded = try JSONDecoder().decode(SavedSession.self, from: JSONEncoder().encode(old))
        XCTAssertNil(decoded.visibleFiles)
    }
}
