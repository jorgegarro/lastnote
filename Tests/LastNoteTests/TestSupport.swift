import AppKit
import XCTest
import SciKit
@testable import LastNote

/// Temporary files for a test, removed afterwards.
final class TempDir {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("lastnote-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func file(_ name: String, _ text: String) -> URL { file(name, Data(text.utf8)) }

    func file(_ name: String, _ data: Data) -> URL {
        let u = url.appendingPathComponent(name)
        try! data.write(to: u)
        return u
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Spin the main run loop until `condition` holds or the timeout passes.
@discardableResult
func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return condition()
}

/// Reset settings to known values so tests don't depend on each other.
func resetSettings() {
    let s = AppSettings.shared
    s.transparencyEnabled = false
    s.opacity = 0.8
    s.blurEnabled = true
    s.tintColor = NSColor(hex: "#1B1F27")!
    s.theme = .dark
    s.wordWrap = false
    s.showWhitespace = false
    s.showLineEndings = false
    s.tabWidth = 4
    s.useSpaces = true
    s.focusGlowEnabled = true
    s.focusGlowColor = nil
    s.focusGlowOpacity = 0.4
    UserDefaults.standard.removeObject(forKey: "tabNames")
    UserDefaults.standard.removeObject(forKey: "tabTints")
}

extension Document {
    var text: String { view.string() ?? "" }

    func setText(_ s: String) {
        view.setString(s)
    }

    func selectAll() { view.sci(SCI_SELECTALL) }
}
