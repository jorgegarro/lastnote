import AppKit
import XCTest
@testable import LastNote

final class RecentFilesTests: XCTestCase {
    var tmp: TempDir!
    var suite: String!
    var defaults: UserDefaults!

    override func setUp() {
        _ = NSApplication.shared
        tmp = TempDir()
        suite = "lastnote-recent-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        RecentFilesMenuController.shared.store = RecentFiles.shared
    }

    private func store() -> RecentFiles { RecentFiles(defaults: defaults) }

    func testNewestFirstAndReopeningMovesToTop() {
        let r = store()
        let a = tmp.file("a.txt", "a"), b = tmp.file("b.txt", "b"), c = tmp.file("c.txt", "c")
        r.note(a); r.note(b); r.note(c)
        XCTAssertEqual(r.paths.map { ($0 as NSString).lastPathComponent }, ["c.txt", "b.txt", "a.txt"])
        r.note(a)
        XCTAssertEqual(r.paths.map { ($0 as NSString).lastPathComponent }, ["a.txt", "c.txt", "b.txt"], "no duplicates; reopened file on top")
    }

    func testKeepsUpToTwenty() {
        let r = store()
        for i in 1...25 { r.note(tmp.file("f\(i).txt", "\(i)")) }
        XCTAssertEqual(r.paths.count, 20)
        XCTAssertEqual((r.paths.first! as NSString).lastPathComponent, "f25.txt")
        XCTAssertEqual((r.paths.last! as NSString).lastPathComponent, "f6.txt", "oldest five dropped")
    }

    func testSurvivesRestart() {
        store().note(tmp.file("kept.txt", "k"))
        // A brand-new instance reading the same saved settings, as after quitting and relaunching.
        XCTAssertEqual(store().paths.map { ($0 as NSString).lastPathComponent }, ["kept.txt"])
    }

    func testClear() {
        let r = store()
        r.note(tmp.file("x.txt", "x"))
        r.clear()
        XCTAssertTrue(r.paths.isEmpty)
        XCTAssertTrue(store().paths.isEmpty)
    }

    func testMenuListsFilesAndGreysOutMissingOnes() throws {
        let r = store()
        let gone = tmp.file("gone.txt", "g")
        r.note(gone)
        r.note(tmp.file("here.txt", "h"))
        try FileManager.default.removeItem(at: gone)
        let controller = RecentFilesMenuController.shared
        controller.store = r
        controller.rebuild()
        let items = controller.menu.items
        let here = try XCTUnwrap(items.first { $0.title == "here.txt" })
        let missing = try XCTUnwrap(items.first { $0.title == "gone.txt" })
        XCTAssertEqual(items.firstIndex(of: here), 0, "newest first")
        XCTAssertTrue(here.isEnabled)
        XCTAssertEqual(here.action, #selector(MainWindowController.openRecentFile(_:)))
        XCTAssertFalse(missing.isEnabled, "missing files stay listed but greyed out")
        XCTAssertNotNil(here.image)
        let clear = try XCTUnwrap(items.last)
        XCTAssertEqual(clear.title, "Clear Menu")
        XCTAssertTrue(clear.isEnabled)
        controller.clearMenu(nil)
        XCTAssertTrue(r.paths.isEmpty)
        XCTAssertEqual(controller.menu.items.first?.title, "No Recent Files")
    }

    func testSameNameInTwoFoldersShowsTheFolder() {
        let r = store()
        let d1 = tmp.url.appendingPathComponent("one"), d2 = tmp.url.appendingPathComponent("two")
        try? FileManager.default.createDirectory(at: d1, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: d2, withIntermediateDirectories: true)
        let f1 = d1.appendingPathComponent("notes.txt"), f2 = d2.appendingPathComponent("notes.txt")
        try? "1".write(to: f1, atomically: true, encoding: .utf8)
        try? "2".write(to: f2, atomically: true, encoding: .utf8)
        r.note(f1); r.note(f2)
        let controller = RecentFilesMenuController.shared
        controller.store = r
        controller.rebuild()
        let titles = controller.menu.items.map(\.title).filter { $0.hasPrefix("notes.txt") }
        XCTAssertEqual(titles.count, 2)
        XCTAssertTrue(titles.allSatisfy { $0.contains(" — ") }, "\(titles)")
        XCTAssertNotEqual(titles[0], titles[1])
    }

    // MARK: Integration with the window

    func testOpeningAndSavingRecordFiles() throws {
        UserDefaults.standard.set(false, forKey: "consoleVisible")
        RecentFiles.shared.clear()
        let wc = MainWindowController()
        wc.newDocument(nil)
        let a = tmp.file("opened.txt", "a"), b = tmp.file("second.txt", "b")
        wc.open(urls: [a, b])
        XCTAssertEqual(RecentFiles.shared.paths.prefix(2).map { ($0 as NSString).lastPathComponent }, ["second.txt", "opened.txt"])
        // Save As records the new name.
        let saved = tmp.url.appendingPathComponent("saved-as.txt")
        try wc.current!.save(to: saved)
        RecentFiles.shared.note(saved)  // (the Save panel path calls this after doc.save)
        XCTAssertEqual((RecentFiles.shared.paths.first! as NSString).lastPathComponent, "saved-as.txt")
        // Opening from the menu opens the file.
        let item = NSMenuItem(title: "opened.txt", action: nil, keyEquivalent: "")
        item.representedObject = a.standardizedFileURL.path
        wc.closeDocument(at: 0)
        XCTAssertFalse(wc.documents.contains { $0.fileName == "opened.txt" })
        wc.openRecentFile(item)
        XCTAssertTrue(wc.documents.contains { $0.fileName == "opened.txt" })
        RecentFiles.shared.clear()
        wc.window?.orderOut(nil)
    }
}
