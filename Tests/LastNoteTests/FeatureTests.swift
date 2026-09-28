import AppKit
import XCTest
import SciKit
import SwiftTerm
@testable import LastNote

/// Console appearance, macros and sessions, against a real window.
final class FeatureTests: XCTestCase {
    var tmp: TempDir!
    var wc: MainWindowController!

    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        resetSettings()
        let s = AppSettings.shared
        s.consoleFontName = ""
        s.consoleFontSize = 12
        s.consoleTextColor = nil
        s.consoleBackgroundColor = nil
        UserDefaults.standard.removeObject(forKey: "savedMacros")
        UserDefaults.standard.removeObject(forKey: "savedSessions")
        UserDefaults.standard.removeObject(forKey: "activeSession")
        SessionStore.shared.reload()
        UserDefaults.standard.set(false, forKey: "consoleVisible")
        tmp = TempDir()
        wc = MainWindowController()
        wc.newDocument(nil)
        wc.showWindow(nil)
        waitUntil(0.5) { false }
    }

    override func tearDown() {
        if wc.macros.isRecording { wc.toggleMacroRecording(nil) }
        wc.console.sessions.forEach { $0.terminate() }
        wc.window?.orderOut(nil)
        wc = nil
    }

    private var doc: Document { wc.current! }

    private func settle() { waitUntil(0.2) { false } }

    // MARK: Console appearance

    func testConsoleFontAndTextColour() throws {
        wc.setConsoleVisible(true)
        let term = try XCTUnwrap(wc.console.active?.terminal)
        let s = AppSettings.shared
        let family = try XCTUnwrap(monospacedFontFamilies.first { $0 != s.fontName && !$0.hasPrefix(".") })
        s.consoleFontName = family
        s.consoleFontSize = 17
        s.consoleTextColor = NSColor(hex: "#33FF66")
        settle()
        XCTAssertEqual(term.font.pointSize, 17)
        XCTAssertEqual(term.font.familyName, family)
        XCTAssertEqual(term.nativeForegroundColor.hexString, "#33FF66")
        s.consoleFontName = ""  // back to the editor font
        s.consoleTextColor = nil
        settle()
        XCTAssertEqual(term.font.familyName, s.editorFont.familyName)
        XCTAssertEqual(term.nativeForegroundColor.hexString, Theme.dark.foreground.hexString)
    }

    func testConsoleBackgroundColour() throws {
        wc.setConsoleVisible(true)
        let session = try XCTUnwrap(wc.console.active)
        func painted() -> NSColor? { session.container.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) } }
        let s = AppSettings.shared
        s.consoleBackgroundColor = NSColor(hex: "#112233")
        settle()
        XCTAssertEqual(painted()?.hexString, "#112233")  // solid window: exact colour
        XCTAssertEqual(painted()?.alphaComponent, 1)
        s.transparencyEnabled = true
        s.opacity = 0.6
        settle()
        XCTAssertEqual(painted()?.withAlphaComponent(1).hexString, "#112233")
        XCTAssertEqual(painted()?.alphaComponent ?? 0, 0.6, accuracy: 0.01)
        wc.console.setTint(NSColor(hex: "#B3261E"), for: session)  // a tab colour overrides it
        XCTAssertEqual(painted()?.withAlphaComponent(1).hexString, "#B3261E")
        wc.console.setTint(nil, for: session)
        s.consoleBackgroundColor = nil  // back to the window tint
        settle()
        XCTAssertEqual(painted()?.withAlphaComponent(1).hexString, s.tintColor.hexString)
    }

    // MARK: Macros

    /// Type the way the keyboard does (through the text-input system).
    private func type(_ text: String) {
        doc.view.content().insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    func testRecordTypingAndPlayBack() {
        doc.setText("")
        wc.toggleMacroRecording(nil)
        XCTAssertTrue(wc.macros.isRecording)
        type("hello")
        type(" world")
        doc.view.sci(SCI_CHARLEFT)
        doc.view.sci(SCI_DELETEBACK)
        wc.toggleMacroRecording(nil)
        XCTAssertFalse(wc.macros.isRecording)
        XCTAssertEqual(doc.text, "hello word")
        XCTAssertFalse(wc.macros.current.isEmpty)

        wc.newDocument(nil)
        wc.playMacro(nil)
        XCTAssertEqual(doc.text, "hello word")
        doc.view.sci(SCI_UNDO)  // the whole playback is one undo step
        XCTAssertEqual(doc.text, "")
    }

    /// A real Return key press, delivered the way the window does.
    private func pressReturn() {
        let content = doc.view.content()!
        wc.window?.makeFirstResponder(content)
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                 windowNumber: wc.window?.windowNumber ?? 0, context: nil, characters: "\r",
                                 charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        content.keyDown(with: e)
    }

    func testAutoIndentIsNotRecordedButHappensOnPlayback() {
        doc.setText("    a")
        doc.view.sci(SCI_DOCUMENTEND)
        wc.toggleMacroRecording(nil)
        pressReturn()
        type("x")
        wc.toggleMacroRecording(nil)
        XCTAssertEqual(doc.text, "    a\n    x")
        XCTAssertFalse(wc.macros.current.contains { $0.kind == .sci && $0.message == SCI_GOTOPOS },
                       "auto-indent's internal caret move must not be recorded: \(wc.macros.current)")
        wc.newDocument(nil)
        doc.setText("  b")
        doc.view.sci(SCI_DOCUMENTEND)
        wc.playMacro(nil)
        XCTAssertEqual(doc.text, "  b\n  x")
    }

    func testCommandsAreRecordedAsSingleSteps() {
        doc.setLanguage(Language.all.first { $0.name == "Python" }!)
        doc.setText("a = 1")
        wc.toggleMacroRecording(nil)
        wc.toggleComment(nil)
        wc.uppercaseSelection(nil)
        wc.toggleMacroRecording(nil)
        XCTAssertEqual(wc.macros.current.map(\.kind), [.command, .command])
        XCTAssertEqual(doc.text, "# a = 1")

        wc.newDocument(nil)
        doc.setLanguage(Language.all.first { $0.name == "Python" }!)
        doc.setText("b = 2")
        wc.playMacro(nil)
        XCTAssertEqual(doc.text, "# b = 2")
    }

    func testFindReplaceIsRecordedAndReplayed() {
        doc.setText("cat cat dog")
        wc.showReplace(nil)
        wc.toggleMacroRecording(nil)
        wc.findBar.findField.stringValue = "cat"
        wc.findBar.replaceField.stringValue = "cow"
        wc.findBar.replaceAll()
        wc.toggleMacroRecording(nil)
        XCTAssertEqual(doc.text, "cow cow dog")
        XCTAssertEqual(wc.macros.current.count, 1)
        XCTAssertEqual(wc.macros.current.first?.findAction, .replaceAll)

        wc.newDocument(nil)
        doc.setText("my cat")
        wc.findBar.findField.stringValue = "something else"  // playback uses the recorded text
        wc.playMacro(nil)
        XCTAssertEqual(doc.text, "my cow")
    }

    /// Records: go to line start, type "- ", move down (a classic "prefix every line" macro).
    private func recordPrefixMacro() {
        wc.toggleMacroRecording(nil)
        doc.view.sci(SCI_VCHOME)
        type("- ")
        doc.view.sci(SCI_LINEDOWN)
        wc.toggleMacroRecording(nil)
    }

    func testRunMultipleTimes() {
        doc.setText("a\nb\nc\nd")
        doc.view.sci(SCI_GOTOPOS, 0)
        recordPrefixMacro()
        XCTAssertEqual(wc.playMacroSteps(wc.macros.current, times: 2), 2)
        XCTAssertEqual(doc.text, "- a\n- b\n- c\nd")
    }

    func testRunUntilEndOfFile() {
        doc.setText("one\ntwo\nthree\nfour\nfive")
        doc.view.sci(SCI_GOTOPOS, 0)
        recordPrefixMacro()
        let runs = wc.playMacroSteps(wc.macros.current, untilEndOfFile: true)
        XCTAssertEqual(doc.text, "- one\n- two\n- three\n- four\n- five")
        XCTAssertEqual(runs, 4)
    }

    func testSavedMacrosPersistAndAppearInMenu() {
        doc.setText("")
        wc.toggleMacroRecording(nil)
        type("sig")
        wc.toggleMacroRecording(nil)
        wc.macros.save(name: "Signature", steps: wc.macros.current)
        XCTAssertEqual(MacroRecorder().saved.map(\.name), ["Signature"])  // reloaded from disk
        MacroMenuController.shared.rebuild()
        let item = MacroMenuController.shared.menu.items.first { $0.title == "Signature" }
        XCTAssertEqual(item?.keyEquivalent, "1")
        XCTAssertEqual(item?.keyEquivalentModifierMask, [.control, .option])
        wc.newDocument(nil)
        wc.runSavedMacro(item!)
        XCTAssertEqual(doc.text, "sig")
        wc.macros.delete(name: "Signature")
        XCTAssertTrue(MacroRecorder().saved.isEmpty)
    }

    func testMacroStepsSurviveEncoding() throws {
        let steps = [MacroStep(kind: .sci, message: SCI_REPLACESEL, text: "héllo 👋"),
                     MacroStep.command(#selector(MainWindowController.toggleComment(_:))),
                     MacroStep(kind: .find, findAction: .replaceAll, find: "(\\w+)", replace: "<\\1>", regex: true)]
        let data = try JSONEncoder().encode(Macro(name: "x", steps: steps))
        XCTAssertEqual(try JSONDecoder().decode(Macro.self, from: data).steps, steps)
    }

    // MARK: Sessions

    func testSessionRoundTrip() throws {
        let window = try XCTUnwrap(wc.window)
        let a = tmp.file("a.sql", "select 1;\n"), b = tmp.file("b.py", "print(2)\n")
        wc.open(urls: [a, b])
        wc.documents[0].customName = "Prod query"
        wc.documents[0].tint = NSColor(hex: "#B3261E")
        wc.select(0)
        wc.setConsoleVisible(true)
        wc.console.sessions[0].customName = "build"
        wc.console.setTint(NSColor(hex: "#00796B"), for: wc.console.sessions[0])
        wc.newConsoleTab(nil)
        let s = AppSettings.shared
        s.transparencyEnabled = true
        s.opacity = 0.55
        s.tintColor = NSColor(hex: "#123456")!
        s.consoleFontSize = 15
        s.consoleBackgroundColor = NSColor(hex: "#0A0A0A")
        let frame = NSRect(x: 100, y: 100, width: 820, height: 560)
        window.setFrame(frame, display: true)
        settle()
        let saved = wc.captureSession(name: "Work", includeTabs: true)
        SessionStore.shared.save(saved)

        // Change everything.
        wc.closeDocument(at: 1)
        wc.documents[0].tint = nil
        s.transparencyEnabled = false
        s.opacity = 0.9
        s.tintColor = NSColor(hex: "#000000")!
        s.consoleFontSize = 11
        s.consoleBackgroundColor = nil
        wc.console.replaceSessions(with: [("other", nil)])
        wc.setConsoleVisible(false)
        window.setFrame(NSRect(x: 50, y: 50, width: 600, height: 420), display: true)
        settle()

        // Reload from the store, as the menu does.
        SessionStore.shared.reload()
        let loaded = try XCTUnwrap(SessionStore.shared.session(named: "Work"))
        XCTAssertEqual(loaded, saved)
        XCTAssertEqual(wc.applySession(loaded), [])
        settle()

        XCTAssertEqual(window.frame.size, frame.size)
        XCTAssertEqual(wc.documents.map(\.fileName), ["a.sql", "b.py"])
        XCTAssertEqual(wc.documents[0].displayName, "Prod query")
        XCTAssertEqual(wc.documents[0].tint?.hexString, "#B3261E")
        XCTAssertEqual(wc.current?.fileName, "a.sql")
        XCTAssertTrue(wc.isConsoleVisible)
        XCTAssertEqual(wc.console.sessions.map(\.name).first, "build")
        XCTAssertEqual(wc.console.sessions.count, 2)
        XCTAssertEqual(wc.console.sessions[0].tint?.hexString, "#00796B")
        XCTAssertTrue(s.transparencyEnabled)
        XCTAssertEqual(s.opacity, 0.55, accuracy: 0.001)
        XCTAssertEqual(s.tintColor.hexString, "#123456")
        XCTAssertEqual(s.consoleFontSize, 15)
        XCTAssertEqual(s.consoleBackgroundColor?.hexString, "#0A0A0A")
        XCTAssertTrue(waitUntil(2) { window.isOpaque == false })
    }

    func testLayoutOnlySessionKeepsTabs() throws {
        wc.open(urls: [tmp.file("keep.txt", "k")])
        AppSettings.shared.opacity = 0.3
        let layout = wc.captureSession(name: "Look", includeTabs: false)
        XCTAssertNil(layout.files)
        XCTAssertNil(layout.consoleTabs)
        wc.open(urls: [tmp.file("second.txt", "s")])
        AppSettings.shared.opacity = 0.9
        wc.applySession(layout)
        XCTAssertEqual(wc.documents.map(\.fileName), ["keep.txt", "second.txt"], "layout-only sessions don't touch tabs")
        XCTAssertEqual(AppSettings.shared.opacity, 0.3, accuracy: 0.001)
    }

    func testMissingFilesAreSkipped() throws {
        let gone = tmp.file("gone.txt", "x")
        wc.open(urls: [gone, tmp.file("stays.txt", "y")])
        let session = wc.captureSession(name: "S", includeTabs: true)
        try FileManager.default.removeItem(at: gone)
        XCTAssertEqual(wc.applySession(session), [gone.path])
        XCTAssertEqual(wc.documents.map(\.fileName), ["stays.txt"])
    }

    func testSessionsMenuListsAndMarksActive() {
        SessionStore.shared.save(wc.captureSession(name: "Beta", includeTabs: false))
        SessionStore.shared.save(wc.captureSession(name: "Alpha", includeTabs: false))
        let menu = SessionMenuController.shared.makeMenu()
        let names = menu.items.filter { $0.action == #selector(MainWindowController.loadSession(_:)) }.map(\.title)
        XCTAssertEqual(names, ["Alpha", "Beta"])
        XCTAssertEqual(menu.items.first { $0.title == "Alpha" }?.state, .on)  // saved last = active
        SessionStore.shared.delete(name: "Alpha")
        SessionStore.shared.delete(name: "Beta")
        XCTAssertTrue(SessionStore.shared.sessions.isEmpty)
    }
}
