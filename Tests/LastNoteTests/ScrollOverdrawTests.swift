import AppKit
import XCTest
import SciKit
@testable import LastNote

/// Trackpad scrolling up past the top (rubber-band + responsive-scrolling overdraw) makes macOS ask
/// Scintilla to draw above the first line. Scintilla used to lay out line -1 there and write before
/// a heap buffer, silently corrupting memory — the cause of LastNote's random crashes.
/// The corruption is only detected under Address Sanitizer:
///   swift test --sanitize=address --filter ScrollOverdrawTests
final class ScrollOverdrawTests: XCTestCase {
    /// One trackpad gesture (began, changed…, ended, momentum…) delivered to the view under `point`.
    private func gesture(_ window: NSWindow, at point: NSPoint, dy: Int32) {
        let screen = window.convertPoint(toScreen: point)
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let root = window.contentView!.superview!
        func send(_ delta: Int32, phase: Int64, momentum: Int64) {
            guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else { return }
            cg.location = CGPoint(x: screen.x, y: mainHeight - screen.y)
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setIntegerValueField(CGEventField(rawValue: 99)!, value: phase)
            cg.setIntegerValueField(CGEventField(rawValue: 123)!, value: momentum)
            guard let e = NSEvent(cgEvent: cg), let hit = root.hitTest(point) else { return }
            hit.scrollWheel(with: e)
            window.displayIfNeeded()
        }
        send(0, phase: 1, momentum: 0)
        for _ in 0..<8 { send(dy, phase: 2, momentum: 0) }
        send(0, phase: 4, momentum: 0)
        send(dy, phase: 0, momentum: 1)
        for i in 0..<15 { send(dy > 0 ? max(1, dy - Int32(i) * 3) : min(-1, dy + Int32(i) * 3), phase: 0, momentum: 2) }
        send(0, phase: 0, momentum: 3)
        waitUntil(0.05) { false }
    }

    func testScrollingPastTheTopIsSafe() {
        _ = NSApplication.shared
        resetSettings()
        UserDefaults.standard.set(false, forKey: "consoleVisible")
        let wc = MainWindowController()
        wc.newDocument(nil)
        wc.showWindow(nil)
        wc.window?.orderFrontRegardless()
        waitUntil(0.3) { false }
        let doc = wc.current!
        doc.view.setString("\n\n" + (1...600).map { "line \($0): some text to scroll through" }.joined(separator: "\n"))
        let window = wc.window!
        let r = wc.editorHost.convert(wc.editorHost.bounds, to: nil)
        let point = NSPoint(x: r.midX, y: r.midY)
        for _ in 0..<6 {
            gesture(window, at: point, dy: -60)  // down
            gesture(window, at: point, dy: 80)   // back up, past the top
            gesture(window, at: point, dy: 120)  // keep pulling at the top (rubber band)
        }
        XCTAssertEqual(doc.view.sci(SCI_GETFIRSTVISIBLELINE), 0)
        window.orderOut(nil)
    }
}
