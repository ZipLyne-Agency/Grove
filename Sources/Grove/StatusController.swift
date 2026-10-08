import AppKit
import SwiftUI
import GroveCore

/// What Quick Access asks the window to do. Copy and Open finish inside the popover and never become intents.
enum PopoverIntent: Sendable {
    case library, reveal(GroveCore.Repository), ask(GroveCore.Repository?), refresh
    case showAll(query: String, owner: String?)
    /// Closes the popover without showing the window, after opening a link in the browser.
    case dismiss
}

/// Owns the status item and releases popover content on close.
@MainActor final class StatusController: NSObject, NSPopoverDelegate {
    private let item: NSStatusItem
    private let popover = NSPopover()
    private let store: Store
    private let openWindow: () -> Void
    static let panelSize = NSSize(width: 420, height: 580)
    init(store: Store, openWindow: @escaping () -> Void) {
        self.store = store; self.openWindow = openWindow
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = NSImage(systemSymbolName: "leaf", accessibilityDescription: "Grove")
        item.button?.toolTip = "Grove"
        item.button?.setAccessibilityLabel("Grove Quick Access")
        item.button?.target = self; item.button?.action = #selector(toggle)
        popover.behavior = .transient; popover.animates = false; popover.delegate = self
        #if DEBUG
        // Lets native UI checks inspect the panel after their driver restores focus.
        // Release builds always keep normal click-away dismissal.
        if ProcessInfo.processInfo.arguments.contains("--keep-quick-access-open") {
            popover.behavior = .applicationDefined
        }
        #endif
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        popover.contentViewController = NSHostingController(rootView: QuickAccessPanel(store: store) { [weak self] intent in
            self?.handle(intent)
        })
        popover.contentSize = Self.panelSize
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--keep-quick-access-open"),
           let anchor = NSApp.windows.first(where: { $0.title == "Grove" })?.contentView {
            // The driver's background lane does not expose a visible status-bar anchor.
            // Leave focus where the driver put it so automation can inspect the anchored panel.
            popover.show(relativeTo: NSRect(x: anchor.bounds.midX, y: anchor.bounds.maxY - 20, width: 1, height: 1),
                         of: anchor, preferredEdge: .minY)
            return
        }
        #endif
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    private func handle(_ intent: PopoverIntent) {
        popover.performClose(nil)
        if case .dismiss = intent { return }
        openWindow()
        let store = self.store
        // Next turn of the run loop, so any sheet attaches to the now key library window.
        DispatchQueue.main.async {
            switch intent {
            case .library, .dismiss: break
            case .reveal(let repo): Self.reveal(repo, in: store)
            case .ask(let repo):
                store.assistantProjectID = nil
                if let repo {
                    Self.reveal(repo, in: store)
                    store.assistantFocus = .repository; store.assistantOwner = nil
                } else {
                    store.assistantFocus = .library; store.assistantOwner = nil; store.assistantScope = .all
                }
                store.showAssistant = true
            case .refresh: store.requestRefresh()
            case .showAll(let query, let owner):
                store.workspace.destination = .library
                store.scope = .all; store.owner = owner; store.search = query
                store.rebuild()
            }
        }
    }
    private static func reveal(_ repo: GroveCore.Repository, in store: Store) {
        store.workspace.destination = .library
        store.owner = nil; store.scope = .all; store.search = ""
        store.selectedID = repo.id
        store.rebuild()
    }
    func popoverDidClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.popover.isShown else { return }; self.popover.contentViewController = nil
        }
    }
    func stop() { popover.performClose(nil); NSStatusBar.system.removeStatusItem(item) }
}
