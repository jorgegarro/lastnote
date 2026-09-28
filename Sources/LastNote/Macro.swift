import AppKit
import SciKit

/// One recorded action. Three kinds, like Notepad++:
/// - a Scintilla editing message (typing, cursor movement, delete, case change…)
/// - a LastNote command (toggle comment, sort lines, trim…), replayed by selector
/// - a Find/Replace operation with its search text and options
struct MacroStep: Codable, Equatable {
    enum Kind: String, Codable { case sci, command, find }
    enum FindAction: String, Codable { case next, previous, replace, replaceAll }

    var kind: Kind
    // .sci
    var message: Int32 = 0
    var wParam: Int = 0
    var lParam: Int = 0
    var text: String? = nil
    // .command
    var command: String? = nil
    // .find
    var findAction: FindAction? = nil
    var find: String? = nil
    var replace: String? = nil
    var matchCase = false
    var wholeWord = false
    var regex = false

    /// Messages whose lParam points at text. The pointer is only valid during the notification,
    /// so the text is copied now.
    private static let stringMessages: Set<Int32> = [SCI_REPLACESEL, SCI_INSERTTEXT, SCI_SEARCHNEXT, SCI_SEARCHPREV]
    private static let lengthStringMessages: Set<Int32> = [SCI_ADDTEXT, SCI_APPENDTEXT]

    static func from(notification n: SCNotification) -> MacroStep? {
        let message = Int32(n.message)
        var step = MacroStep(kind: .sci, message: message, wParam: Int(bitPattern: UInt(n.wParam)), lParam: Int(n.lParam))
        if stringMessages.contains(message) {
            guard let p = UnsafePointer<CChar>(bitPattern: Int(n.lParam)) else { return nil }
            step.text = String(cString: p)
            step.lParam = 0
        } else if lengthStringMessages.contains(message) {
            guard let p = UnsafeRawPointer(bitPattern: Int(n.lParam)) else { return nil }
            step.text = String(decoding: UnsafeRawBufferPointer(start: p, count: step.wParam), as: UTF8.self)
            step.lParam = 0
        }
        return step
    }

    static func command(_ selector: Selector) -> MacroStep {
        MacroStep(kind: .command, command: NSStringFromSelector(selector))
    }

    /// Replay a Scintilla step on a view.
    func applySci(to v: ScintillaView) {
        if MacroStep.stringMessages.contains(message) {
            v.sci(message, wParam, string: text ?? "")
        } else if MacroStep.lengthStringMessages.contains(message) {
            let t = text ?? ""
            v.sci(message, t.utf8.count, string: t)
        } else {
            v.sci(message, wParam, lParam)
        }
    }
}

struct Macro: Codable, Equatable {
    var name: String
    var steps: [MacroStep]
}

/// Recording state plus the saved-macro library (persisted in UserDefaults).
final class MacroRecorder {
    static let didChange = Notification.Name("MacroRecorderDidChange")

    private(set) var isRecording = false
    private(set) var isPlaying = false
    /// The most recently recorded macro ("Current recorded macro" in Notepad++).
    private(set) var current: [MacroStep] = []
    private(set) var saved: [Macro] = []
    private let defaultsKey = "savedMacros"

    init() { load() }

    func start() {
        current = []
        isRecording = true
        changed()
    }

    func stop() {
        isRecording = false
        changed()
    }

    func record(_ step: MacroStep) {
        guard isRecording, !isPlaying else { return }
        // Merge consecutive typed characters into one step so saved macros stay small.
        if step.kind == .sci, step.message == SCI_REPLACESEL, let last = current.last,
           last.kind == .sci, last.message == SCI_REPLACESEL, let t = step.text, !t.contains("\n"),
           let lt = last.text, !lt.contains("\n") {
            current[current.count - 1].text = lt + t
            return
        }
        current.append(step)
    }

    /// Run `body` with recording of new steps disabled (used during playback).
    func playing(_ body: () -> Void) {
        isPlaying = true
        defer { isPlaying = false }
        body()
    }

    // MARK: Library

    func save(name: String, steps: [MacroStep]) {
        if let i = saved.firstIndex(where: { $0.name == name }) {
            saved[i].steps = steps
        } else {
            saved.append(Macro(name: name, steps: steps))
        }
        persist()
    }

    func delete(name: String) {
        saved.removeAll { $0.name == name }
        persist()
    }

    private func load() { saved = MacroRecorder.loadSaved() }

    /// The saved-macro library as stored on disk.
    static func loadSaved() -> [Macro] {
        guard let data = UserDefaults.standard.data(forKey: "savedMacros"),
              let macros = try? JSONDecoder().decode([Macro].self, from: data) else { return [] }
        return macros
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: defaultsKey) }
        changed()
    }

    private func changed() {
        NotificationCenter.default.post(name: MacroRecorder.didChange, object: self)
    }
}
