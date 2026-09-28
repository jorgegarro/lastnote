import AppKit
import XCTest
@testable import LastNote

/// Clicks tab-bar controls with real mouse events, the way a user does. Closing/selecting/renaming a
/// tab rebuilds the tab bar, so this guards against destroying a control inside its own click.
final class TabClickTests: XCTestCase {
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
        waitUntil(0.3) { false }
    }

    override func tearDown() {
        wc.console.sessions.forEach { $0.terminate() }
        wc.window?.orderOut(nil)
        wc = nil
    }

    /// Mouse down + up at the centre of a view, through NSWindow.sendEvent.
    private func click(_ view: NSView, count: Int = 1, modifiers: NSEvent.ModifierFlags = []) {
        guard let window = view.window else { return XCTFail("view not in a window") }
        window.layoutIfNeeded()
        let p = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        func event(_ type: NSEvent.EventType, _ c: Int) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: c, pressure: 1)!
        }
        // The test runner's window can't become key, so NSWindow would swallow the clicks; deliver
        // them to the view under the pointer, as the window would.
        guard let root = window.contentView?.superview,
              let target = root.hitTest(p) else { return XCTFail("nothing under the pointer") }
        for c in 1...count {
            // Controls track the mouse until the matching mouse-up arrives from the event queue,
            // so queue it first, then deliver the mouse-down.
            NSApp.postEvent(event(.leftMouseUp, c), atStart: false)
            target.mouseDown(with: event(.leftMouseDown, c))
            if let up = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
                target.mouseUp(with: up)
            }
            // Real double-clicks have a short gap between clicks in which the run loop turns.
            if c < count { waitUntil(0.08) { false } }
        }
        waitUntil(0.05) { false }
    }

    private func tabViews(_ bar: TabBar) -> [NSView] {
        let stack = bar.subviews.first { $0 is NSStackView } as! NSStackView
        return stack.arrangedSubviews
    }

    private func closeButton(_ tab: NSView) -> NSButton {
        tab.subviews.compactMap { $0 as? NSButton }.first!
    }

    func testClickingCloseButtonsClosesTabs() {
        wc.open(urls: (1...4).map { tmp.file("f\($0).txt", "x") })
        XCTAssertEqual(wc.documents.count, 4)
        for remaining in stride(from: 3, through: 1, by: -1) {
            click(closeButton(tabViews(wc.tabBar)[0]))
            XCTAssertTrue(waitUntil(1) { self.wc.documents.count == remaining })
        }
    }

    func testClickingTabsSelectsThem() {
        wc.open(urls: (1...3).map { tmp.file("s\($0).txt", "x") })
        for i in [0, 2, 1, 0] {
            click(tabViews(wc.tabBar)[i])
            XCTAssertTrue(waitUntil(1) { self.wc.current?.fileName == "s\(i + 1).txt" })
        }
    }

    func testDoubleClickRenameAndCommit() throws {
        wc.open(urls: [tmp.file("r.txt", "x")])
        click(tabViews(wc.tabBar)[0], count: 2)
        let field = try XCTUnwrap(wc.window?.firstResponder as? NSTextView)
        field.string = "Renamed"
        field.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertTrue(waitUntil(1) { self.wc.current?.displayName == "Renamed" })
        // Renaming again and clicking another tab (commits by losing focus) must also be safe.
        wc.open(urls: [tmp.file("r2.txt", "y")])
        click(tabViews(wc.tabBar)[0], count: 2)
        (wc.window?.firstResponder as? NSTextView)?.string = "Again"
        click(tabViews(wc.tabBar)[1])
        XCTAssertTrue(waitUntil(1) { self.wc.documents[0].displayName == "Again" })
    }

    func testConsoleTabCloseButtons() {
        wc.setConsoleVisible(true)
        wc.newConsoleTab(nil)
        wc.newConsoleTab(nil)
        XCTAssertEqual(wc.console.sessions.count, 3)
        click(closeButton(tabViews(wc.console.tabBar)[1]))
        XCTAssertTrue(waitUntil(1) { self.wc.console.sessions.count == 2 })
        click(tabViews(wc.console.tabBar)[0])
        click(closeButton(tabViews(wc.console.tabBar)[0]))
        XCTAssertTrue(waitUntil(1) { self.wc.console.sessions.count == 1 })
    }

    func testTabViewsAreReusedNotRebuilt() {
        wc.open(urls: [tmp.file("x1.txt", "a"), tmp.file("x2.txt", "b")])
        let before = tabViews(wc.tabBar).map(ObjectIdentifier.init)
        click(tabViews(wc.tabBar)[0])
        XCTAssertTrue(waitUntil(1) { self.wc.current?.fileName == "x1.txt" })
        wc.documents[1].tint = NSColor(hex: "#2E7D32")
        wc.documents[1].customName = "Two"
        XCTAssertEqual(tabViews(wc.tabBar).map(ObjectIdentifier.init), before, "selecting/recolouring/renaming must not rebuild tabs")
    }

    func testRenameEditingWidthIsReleased() throws {
        wc.open(urls: [tmp.file("w.txt", "a")])
        let tab = tabViews(wc.tabBar)[0]
        wc.tabBar.layoutSubtreeIfNeeded()
        let width = tab.frame.width
        wc.tabBar.beginRename(at: 0)
        let field = try XCTUnwrap(wc.window?.firstResponder as? NSTextView)
        field.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        waitUntil(0.3) { false }
        wc.tabBar.layoutSubtreeIfNeeded()
        XCTAssertEqual(tab.frame.width, width, accuracy: 1, "tab should shrink back after renaming")
    }

    func testCommandClickShowsTabsSideBySide() {
        wc.open(urls: [tmp.file("p1.txt", "a"), tmp.file("p2.txt", "b"), tmp.file("p3.txt", "c")])
        click(tabViews(wc.tabBar)[0], modifiers: .command)
        XCTAssertTrue(waitUntil(1) { self.wc.visibleDocs.count == 2 }, "⌘-click should add the tab: \(self.wc.visibleDocs.map(\.fileName))")
        wc.setConsoleVisible(true)
        wc.newConsoleTab(nil)
        click(tabViews(wc.console.tabBar)[0], modifiers: .command)
        XCTAssertTrue(waitUntil(1) { self.wc.console.visibleSessions.count == 2 })
    }

    func testRepeatedTabChurn() {
        // Many clicks in a row: select, close, reopen.
        for round in 0..<15 {
            wc.open(urls: [tmp.file("c\(round)a.txt", "a"), tmp.file("c\(round)b.txt", "b")])
            click(tabViews(wc.tabBar)[0])
            click(closeButton(tabViews(wc.tabBar).last!))
            click(closeButton(tabViews(wc.tabBar)[0]))
        }
        XCTAssertGreaterThanOrEqual(wc.documents.count, 1)
    }
}
