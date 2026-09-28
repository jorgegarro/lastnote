import AppKit
import XCTest
import SciKit
@testable import LastNote

final class SettingsTests: XCTestCase {
    override func setUp() { resetSettings() }

    func testHexRoundTrip() {
        for hex in ["#000000", "#FFFFFF", "#1B1F27", "#B3261E"] {
            XCTAssertEqual(NSColor(hex: hex)?.hexString, hex)
        }
        XCTAssertNil(NSColor(hex: "nope"))
        XCTAssertNil(NSColor(hex: "#12345"))
    }

    func testLuminance() {
        XCTAssertGreaterThan(NSColor.white.luminance, 0.9)
        XCTAssertLessThan(NSColor(hex: "#000000")!.luminance, 0.01)
    }

    func testTabNameAndTintPersistence() {
        let s = AppSettings.shared
        s.setTabName("Prod queries", forPath: "/tmp/a.sql")
        s.setTabTint(NSColor(hex: "#B3261E"), forPath: "/tmp/a.sql")
        XCTAssertEqual(s.tabName(forPath: "/tmp/a.sql"), "Prod queries")
        XCTAssertEqual(s.tabTint(forPath: "/tmp/a.sql")?.hexString, "#B3261E")
        s.setTabName(nil, forPath: "/tmp/a.sql")
        s.setTabTint(nil, forPath: "/tmp/a.sql")
        XCTAssertNil(s.tabName(forPath: "/tmp/a.sql"))
        XCTAssertNil(s.tabTint(forPath: "/tmp/a.sql"))
    }

    func testFocusGlowAutoColour() {
        let s = AppSettings.shared
        s.theme = .dark
        XCTAssertEqual(s.effectiveFocusGlowColor.hexString, "#FFFFFF")
        s.theme = .light
        XCTAssertNotEqual(s.effectiveFocusGlowColor.hexString, "#FFFFFF")
        s.focusGlowColor = NSColor(hex: "#00FF00")
        XCTAssertEqual(s.effectiveFocusGlowColor.hexString, "#00FF00")
    }
}

final class LanguageTests: XCTestCase {
    func testEveryLanguageHasAWorkingLexer() {
        for lang in Language.all + [Language.plainText] {
            let view = ScintillaView(frame: .zero)
            XCTAssertTrue(SciBridge.setLexer(lang.lexer, on: view), "no Lexilla lexer named \(lang.lexer) (\(lang.name))")
        }
    }

    func testLanguageNamesAndExtensionsAreUnique() {
        let names = Language.all.map(\.name)
        XCTAssertEqual(names.count, Set(names).count)
        let exts = Language.all.flatMap(\.extensions)
        XCTAssertEqual(exts.count, Set(exts).count, "an extension maps to two languages")
    }

    func testDetection() {
        func name(_ file: String?, _ first: String = "") -> String {
            Language.detect(url: file.map { URL(fileURLWithPath: "/tmp/\($0)") }, firstLine: first).name
        }
        XCTAssertEqual(name("a.py"), "Python")
        XCTAssertEqual(name("A.SQL"), "SQL")
        XCTAssertEqual(name("pkg.pkb"), "SQL")
        XCTAssertEqual(name("index.tsx"), "TypeScript")
        XCTAssertEqual(name("main.swift"), "Swift")
        XCTAssertEqual(name("Makefile"), "Makefile")
        XCTAssertEqual(name(".zshrc"), "Shell")
        XCTAssertEqual(name("config.yml"), "YAML")
        XCTAssertEqual(name("script", "#!/usr/bin/env python3"), "Python")
        XCTAssertEqual(name("run", "#!/bin/bash"), "Shell")
        XCTAssertEqual(name(nil, "<?xml version=\"1.0\"?>"), "XML")
        XCTAssertEqual(name("notes.unknownext"), Language.plainText.name)
        XCTAssertEqual(name(nil), Language.plainText.name)
    }
}

final class DocumentTests: XCTestCase {
    var tmp: TempDir!

    override func setUp() {
        _ = NSApplication.shared
        resetSettings()
        tmp = TempDir()
    }

    func testLoadUTF8() throws {
        let doc = try Document(url: tmp.file("a.py", "print('héllo')\n"))
        XCTAssertEqual(doc.text, "print('héllo')\n")
        XCTAssertEqual(doc.language.name, "Python")
        XCTAssertEqual(doc.lineEnding, .lf)
        XCTAssertEqual(doc.encodingName, "UTF-8")
        XCTAssertFalse(doc.isDirty)
        XCTAssertEqual(doc.displayName, "a.py")
    }

    func testCRLFIsDetectedAndPreservedOnSave() throws {
        let original = "one\r\ntwo\r\n"
        let url = tmp.file("w.txt", original)
        let doc = try Document(url: url)
        XCTAssertEqual(doc.lineEnding, .crlf)
        let out = tmp.url.appendingPathComponent("w2.txt")
        try doc.save(to: out)
        XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), original)
    }

    func testBOMIsPreserved() throws {
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("x\n".utf8)
        let doc = try Document(url: tmp.file("bom.txt", bytes))
        XCTAssertEqual(doc.encodingName, "UTF-8 BOM")
        XCTAssertEqual(doc.text, "x\n")
        let out = tmp.url.appendingPathComponent("bom2.txt")
        try doc.save(to: out)
        XCTAssertEqual(try Data(contentsOf: out), bytes)
    }

    func testNonUTF8FileRoundTrips() throws {
        let bytes = Data([0x63, 0x61, 0x66, 0xE9, 0x0A])  // "café\n" in Latin-1 / Windows-1252
        let doc = try Document(url: tmp.file("latin.txt", bytes))
        XCTAssertEqual(doc.text, "café\n")
        let out = tmp.url.appendingPathComponent("latin2.txt")
        try doc.save(to: out)
        XCTAssertEqual(try Data(contentsOf: out), bytes)
    }

    func testDirtyTrackingAndSave() throws {
        let url = tmp.file("d.txt", "abc")
        let doc = try Document(url: url)
        XCTAssertFalse(doc.isDirty)
        doc.view.sci(SCI_APPENDTEXT, 3, string: "def")
        XCTAssertTrue(doc.isDirty)
        try doc.save(to: url)
        XCTAssertFalse(doc.isDirty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "abcdef")
        doc.view.sci(SCI_UNDO)
        XCTAssertTrue(doc.isDirty)
    }

    func testConvertLineEndings() {
        let doc = Document(untitledNumber: 1)
        doc.setText("a\nb\n")
        doc.convertLineEndings(to: .crlf)
        XCTAssertEqual(doc.text, "a\r\nb\r\n")
        XCTAssertEqual(doc.lineEnding, .crlf)
        doc.convertLineEndings(to: .lf)
        XCTAssertEqual(doc.text, "a\nb\n")
    }

    func testToggleLineCommentRoundTrip() {
        let doc = Document(untitledNumber: 1)
        doc.setLanguage(Language.all.first { $0.name == "Python" }!)
        let original = "x = 1\n    y = 2\n\nz = 3"
        doc.setText(original)
        doc.selectAll()
        doc.toggleLineComment()
        XCTAssertEqual(doc.text, "# x = 1\n#     y = 2\n\n# z = 3")
        doc.selectAll()
        doc.toggleLineComment()
        XCTAssertEqual(doc.text, original)
    }

    func testToggleCommentUsesLanguagePrefix() {
        let doc = Document(untitledNumber: 1)
        doc.setLanguage(Language.all.first { $0.name == "SQL" }!)
        doc.setText("select 1 from dual;")
        doc.toggleLineComment()
        XCTAssertEqual(doc.text, "-- select 1 from dual;")
    }

    func testTrimTrailingWhitespace() {
        let doc = Document(untitledNumber: 1)
        doc.setText("a  \nb\t\n  c")
        doc.trimTrailingWhitespace()
        XCTAssertEqual(doc.text, "a\nb\n  c")
    }

    func testSortLines() {
        let doc = Document(untitledNumber: 1)
        doc.setText("banana\napple\ncherry")
        doc.sortLines(descending: false)
        XCTAssertEqual(doc.text, "apple\nbanana\ncherry")
        doc.sortLines(descending: true)
        XCTAssertEqual(doc.text, "cherry\nbanana\napple")
    }

    func testBookmarksToggleAndNavigate() {
        let doc = Document(untitledNumber: 1)
        doc.setText("0\n1\n2\n3\n4")
        doc.toggleBookmark(line: 1)
        doc.toggleBookmark(line: 3)
        doc.gotoLine(0)
        doc.gotoBookmark(forward: true)
        XCTAssertEqual(doc.caretInfo.line, 2)
        doc.gotoBookmark(forward: true)
        XCTAssertEqual(doc.caretInfo.line, 4)
        doc.gotoBookmark(forward: true)  // wraps
        XCTAssertEqual(doc.caretInfo.line, 2)
        doc.toggleBookmark(line: 1)
        doc.gotoLine(0)
        doc.gotoBookmark(forward: true)
        XCTAssertEqual(doc.caretInfo.line, 4)
    }

    func testCustomNameAndTint() throws {
        let url = tmp.file("n.sql", "select 1;")
        let doc = try Document(url: url)
        doc.customName = "  Prod  "
        XCTAssertEqual(doc.customName, "Prod")
        XCTAssertEqual(doc.displayName, "Prod")
        XCTAssertEqual(doc.fileName, "n.sql")
        XCTAssertTrue(doc.tooltip?.contains(url.path) ?? false)
        doc.tint = NSColor(hex: "#2E7D32")
        // A reopened document gets its name and colour back.
        let again = try Document(url: url)
        XCTAssertEqual(again.displayName, "Prod")
        XCTAssertEqual(again.tint?.hexString, "#2E7D32")
        doc.customName = "   "
        XCTAssertNil(doc.customName)
        XCTAssertEqual(doc.displayName, "n.sql")
        XCTAssertNil(AppSettings.shared.tabName(forPath: url.path))
    }
}

final class FindTests: XCTestCase {
    var doc: Document!
    var bar: FindBar!

    override func setUp() {
        _ = NSApplication.shared
        resetSettings()
        doc = Document(untitledNumber: 1)
        bar = FindBar()
        bar.document = { [unowned self] in self.doc }
    }

    func testHighlightCount() {
        doc.setText("Foo foo FOO food")
        bar.findField.stringValue = "foo"
        bar.highlightAll()
        XCTAssertEqual(bar.countLabel.stringValue, "4 matches")
        bar.matchCase.state = .on
        bar.highlightAll()
        XCTAssertEqual(bar.countLabel.stringValue, "2 matches")
        bar.wholeWord.state = .on
        bar.highlightAll()
        XCTAssertEqual(bar.countLabel.stringValue, "1 match")
        bar.findField.stringValue = "zzz"
        bar.highlightAll()
        XCTAssertEqual(bar.countLabel.stringValue, "No results")
    }

    func testFindNextWrapsAround() {
        doc.setText("ab ab ab")
        bar.findField.stringValue = "ab"
        doc.view.sci(SCI_GOTOPOS, 7)
        XCTAssertTrue(bar.findNext())
        XCTAssertEqual(doc.view.sci(SCI_GETSELECTIONSTART), 0)
        XCTAssertTrue(bar.findNext())
        XCTAssertEqual(doc.view.sci(SCI_GETSELECTIONSTART), 3)
        XCTAssertTrue(bar.findPrevious())
        XCTAssertEqual(doc.view.sci(SCI_GETSELECTIONSTART), 0)
    }

    func testReplaceAllPlain() {
        doc.setText("foo bar foo")
        bar.findField.stringValue = "foo"
        bar.replaceField.stringValue = "baz"
        bar.replaceAll()
        XCTAssertEqual(doc.text, "baz bar baz")
        XCTAssertEqual(bar.countLabel.stringValue, "Replaced 2")
        doc.view.sci(SCI_UNDO)  // one undo step for the whole replace
        XCTAssertEqual(doc.text, "foo bar foo")
    }

    func testReplaceAllRegexWithGroups() {
        doc.setText("user1@a.com, user22@b.org")
        bar.regex.state = .on
        bar.findField.stringValue = "(\\w+)@"
        bar.replaceField.stringValue = "<\\1> at "
        bar.replaceAll()
        XCTAssertEqual(doc.text, "<user1> at a.com, <user22> at b.org")
    }

    func testReplaceOneOnlyReplacesAMatchingSelection() {
        doc.setText("cat dog cat")
        bar.findField.stringValue = "cat"
        bar.replaceField.stringValue = "cow"
        doc.view.sci(SCI_SETSEL, 4, 7)  // "dog" is selected, not a match
        bar.replaceOne()
        XCTAssertEqual(doc.text, "cat dog cat")
        bar.replaceOne()  // now the next "cat" is selected
        XCTAssertEqual(doc.text, "cat dog cow")
    }
}
