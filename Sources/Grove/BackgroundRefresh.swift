import AppKit
import Network

/// One bounded refresh loop for the lifetime of the application, including menu-only use.
@MainActor
final class BackgroundRefresh {
    private let store: Store
    private var loop: Task<Void, Never>?
    private let monitor = NWPathMonitor()
    private var wakeObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private var lastAttempt = Date.distantPast
    private var failures = 0
    private var refreshing = false
    private var sleeping = false
    private var sleepObserver: NSObjectProtocol?
    private var screenWakeObserver: NSObjectProtocol?
    private var online = true
    private var stopped = false
    init(store: Store) { self.store = store }
    func start() {
        stopped = false
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let recovered = !self.online && path.status == .satisfied
                self.online = path.status == .satisfied
                if recovered { await self.catchUp() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "agency.ziplyne.grove.network"))
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.catchUp() }
        }
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.catchUp() }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = true }
        }
        screenWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = false; await self?.catchUp() }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.catchUp()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
    func catchUp() async {
        guard !stopped, online, !sleeping, !refreshing, !ProcessInfo.processInfo.isLowPowerModeEnabled, !store.loadingCache, !store.workspace.loading, store.canStartReview, !store.assistantBusy else { return }
        refreshing = true; defer { refreshing = false }
        let delay = min(1800.0, 300 * pow(2, Double(failures)))
        let fetched = store.inventory?.fetchedAt ?? .distantPast
        if Date().timeIntervalSince(lastAttempt) >= (failures == 0 ? 30 : delay), Date().timeIntervalSince(fetched) >= delay {
            lastAttempt = Date()
            await store.refresh()
            failures = store.message == nil ? 0 : min(failures + 1, 3)
        }
        guard !stopped, !Task.isCancelled, store.canStartReview else { return }
        await store.workspace.syncAll()
    }
    func stop() {
        stopped = true
        loop?.cancel(); loop = nil; monitor.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let screenWakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(screenWakeObserver) }
        store.workspace.stop()
    }
}
