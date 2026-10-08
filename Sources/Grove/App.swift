import AppKit
import SwiftUI
import GroveCore

@main
struct GroveApp {
    @MainActor static func main() {
        let lease: WorkspaceLease
        do { lease = try WorkspaceLease() }
        catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1)
        }
        withExtendedLifetime(lease) { run() }
    }
    @MainActor private static func run() {
        if CommandLine.arguments.contains("--import-setup-stdin") { SetupCommand.run() }
        if CommandLine.arguments.contains("--profile-summary") { ProfileSummaryCommand.run() }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    var window: NSWindow!
    var status: StatusController!
    var background: BackgroundRefresh!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Grove"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1040, height: 700)
        window.setFrameAutosaveName("GroveLibrary")
        window.titlebarSeparatorStyle = .none
        window.contentView = NSHostingView(rootView: LibraryView(store: store))
        window.center()
        window.makeKeyAndOrderFront(nil)
        status = StatusController(store: store) { [weak self] in self?.showWindow() }
        installMenu()
        background = BackgroundRefresh(store: store); background.start()
        store.updates = AppUpdates(store: store)
        installUpdateMenu()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func showLibrary(_ sender: Any?) { showWindow() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if store.terminating { return .terminateLater }
        store.terminating = true
        store.assistantTask?.cancel()
        store.workspace.stopEnrichment()
        if !store.mutationInFlight { store.operationTask?.cancel() }
        Task {
            await store.workspace.enrichmentTask?.value
            await store.operationTask?.value
            while store.busy || store.operationInFlight || store.mutationInFlight || store.preparing || store.workspace.loadingResources || store.workspace.renaming || store.workspace.preparingRename || store.workspace.discovering || !store.workspace.syncing.isEmpty {
                try? await Task.sleep(for: .milliseconds(50))
            }
            await store.workspace.flush()
            if store.workspace.persistenceBlocked {
                store.terminating = false
                store.installingUpdate = false
                store.message = "Grove could not save your workspace. Resolve the save error before quitting or updating."
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            background.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    private func installUpdateMenu() {
        guard let menu = NSApp.mainMenu?.items.first?.submenu, let updates = store.updates else { return }
        let item = NSMenuItem(title: "Check for Updates…", action: #selector(AppUpdates.checkForUpdates(_:)), keyEquivalent: "")
        item.target = updates
        menu.insertItem(item, at: 1)
    }
    func applicationWillTerminate(_ notification: Notification) {
        store.assistantTask?.cancel(); store.operationTask?.cancel(); store.queryTask?.cancel(); status.stop(); background.stop()
    }
    private func installMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Grove", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Grove", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); editItem.title = "Edit"; let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem)
        let windowItem = NSMenuItem(); windowItem.title = "Window"; let windows = NSMenu(title: "Window")
        windows.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windows.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windows.addItem(.separator())
        let library = NSMenuItem(title: "Grove Library", action: #selector(showLibrary(_:)), keyEquivalent: "0")
        library.target = self
        windows.addItem(library)
        let quickAccess = NSMenuItem(title: "Quick Access", action: #selector(StatusController.toggle), keyEquivalent: "p")
        quickAccess.keyEquivalentModifierMask = [.command, .shift]
        quickAccess.target = status
        windows.addItem(quickAccess)
        windowItem.submenu = windows; main.addItem(windowItem); NSApp.windowsMenu = windows
        NSApp.mainMenu = main
    }
}
