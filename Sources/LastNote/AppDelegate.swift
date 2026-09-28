import AppKit
import SciKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var mainWindow: MainWindowController!
    private var pendingURLs: [URL] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = RecentDocumentsController()  // becomes NSDocumentController.shared
        NSApp.mainMenu = AppMenus.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        mainWindow = MainWindowController()

        // Files passed on the command line (`LastNote file1 file2`) or via Finder.
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        var urls = pendingURLs + args.map { URL(fileURLWithPath: $0) }
        if urls.isEmpty {
            urls = (UserDefaults.standard.stringArray(forKey: "sessionFiles") ?? [])
                .map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        mainWindow.newDocument(nil)
        mainWindow.open(urls: urls)
        if urls.count > 0, let last = UserDefaults.standard.string(forKey: "sessionSelected"),
           let i = mainWindow.documents.firstIndex(where: { $0.url?.path == last }), pendingURLs.isEmpty, args.isEmpty {
            mainWindow.select(i)
        }
        pendingURLs = []
        mainWindow.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.environment["LASTNOTE_SELFTEST"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [mainWindow] in mainWindow?.runSelfTest() }
        }
        if let secs = ProcessInfo.processInfo.environment["LASTNOTE_STRESS_EDIT"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [mainWindow] in mainWindow?.runEditStress(seconds: secs) }
        }
        if let secs = ProcessInfo.processInfo.environment["LASTNOTE_STRESS_APPEARANCE"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [mainWindow] in mainWindow?.runAppearanceStress(seconds: secs) }
        }
        if let secs = ProcessInfo.processInfo.environment["LASTNOTE_STRESS"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [mainWindow] in mainWindow?.runStress(seconds: secs) }
        }
        DebugSnapshot.scheduleIfRequested(mainWindow.window)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let mainWindow { mainWindow.open(urls: urls) } else { pendingURLs += urls }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let mainWindow else { return .terminateNow }
        guard mainWindow.confirmCloseAll() else { return .terminateCancel }
        UserDefaults.standard.set(mainWindow.sessionURLs.map(\.path), forKey: "sessionFiles")
        UserDefaults.standard.set(mainWindow.current?.url?.path, forKey: "sessionSelected")
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    @objc func showSettings(_ sender: Any?) { SettingsWindowController.shared.show() }
}

/// Routes "Open Recent" menu picks to our window instead of NSDocument machinery.
final class RecentDocumentsController: NSDocumentController {
    override func openDocument(withContentsOf url: URL, display displayDocument: Bool,
                               completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void) {
        (NSApp.delegate as? AppDelegate)?.mainWindow?.open(urls: [url])
        completionHandler(nil, false, nil)
    }
}
