import AppKit
import Observation
import Sparkle

/// Sparkle owns update verification and installation. Grove only delays relaunch until work is saved.
@MainActor @Observable
final class AppUpdates: NSObject, SPUUpdaterDelegate {
    private weak var store: Store?
    private var controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?
    private var pendingRelaunch: Task<Void, Never>?
    var canCheck = false
    var automaticChecks = false
    var status: String?
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }

    init(store: Store) {
        self.store = store
        super.init()
        // SwiftPM tests and bare executables must not start network checks or an installer.
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let allowed = change.newValue ?? false
            Task { @MainActor [weak self] in self?.canCheck = allowed }
        }
        controller.startUpdater()
        automaticChecks = controller.updater.automaticallyChecksForUpdates
    }

    @objc func checkForUpdates(_ sender: Any? = nil) {
        guard let controller else { return }
        status = nil
        controller.checkForUpdates(sender)
    }

    func setAutomaticChecks(_ value: Bool) {
        controller?.updater.automaticallyChecksForUpdates = value
        automaticChecks = controller?.updater.automaticallyChecksForUpdates ?? false
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard let store, store.updateBlockingReason == nil, !store.installingUpdate, !store.terminating else {
            throw NSError(domain: "agency.ziplyne.grove.updates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: store?.updateBlockingReason ?? "Finish the current task before checking for updates."])
        }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        postponeInstallation(installHandler)
        return true
    }

    func postponeInstallation(_ installHandler: @escaping () -> Void) {
        guard let store else { return }
        pendingRelaunch?.cancel()
        store.installingUpdate = false
        status = "Waiting for current work to finish before updating…"
        pendingRelaunch = Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            while !Task.isCancelled {
                store.installingUpdate = false
                if store.workspace.persistenceBlocked {
                    // Keep the continuation so recovering the workspace can resume installation.
                    self.status = "Grove could not save your workspace. Resolve the save error before updating."
                    store.installingUpdate = false
                } else if store.updateBlockingReason == nil {
                    store.installingUpdate = true
                    await store.workspace.flush()
                    guard !Task.isCancelled else { return }
                    if store.updateBlockingReason == nil {
                        self.status = "Installing update…"
                        installHandler()
                        return
                    }
                }
                store.installingUpdate = false
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        pendingRelaunch?.cancel(); pendingRelaunch = nil
        store?.installingUpdate = false
        let failure = error as NSError
        if failure.domain == SUSparkleErrorDomain, failure.code == 1001 { status = "You’re up to date."; return }
        if failure.domain == SUSparkleErrorDomain, failure.code == 4007 { status = nil; return }
        status = failure.domain == "agency.ziplyne.grove.updates" ? failure.localizedDescription : "The update could not be completed. Try Check for Updates again."
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        status = "You’re up to date."
    }
}

extension Store {
    /// Shared by manual checks and delayed installation; pending persistence is flushed before exit.
    var updateBlockingReason: String? {
        if workspace.persistenceBlocked { return "Resolve the workspace save error before updating." }
        if loadingCache || workspace.loading { return "Wait for Grove to finish loading." }
        if preparing || operationInFlight || mutationInFlight || workspace.preparingRename || workspace.renaming {
            return "Wait for the current GitHub or service operation to finish."
        }
        if consent != nil || preview != nil || editor != nil || workspace.renameReview != nil ||
            NSApp?.windows.contains(where: { $0.attachedSheet != nil }) == true {
            return "Finish or cancel the current review before updating."
        }
        if busy || workspace.enrichment.running || !workspace.syncing.isEmpty || workspace.discovering || workspace.loadingResources {
            return "Wait for the current sync or repository scan to finish."
        }
        return nil
    }
}
