import Testing
import Foundation
import GroveCore
@testable import Grove

@MainActor @Test func updaterWaitsForWorkAndFlushesBeforeInstallingOnce() async throws {
    let store = Store(loadCache: false)
    let updates = AppUpdates(store: store)
    store.operationInFlight = true
    var installs = 0
    updates.postponeInstallation { installs += 1 }
    await Task.yield()
    #expect(installs == 0)
    #expect(!store.installingUpdate)
    #expect(!store.canStartReview)
    #expect(!store.workspace.canEdit)
    store.operationInFlight = false
    try await Task.sleep(for: .milliseconds(350))
    #expect(installs == 1)
    #expect(store.installingUpdate)
    #expect(!store.canStartReview)
    #expect(!store.workspace.canEdit)
    try await Task.sleep(for: .milliseconds(250))
    #expect(installs == 1)
}

@MainActor @Test func updaterRetainsInstallationAfterSaveRecovery() async throws {
    let store = Store(loadCache: false)
    let updates = AppUpdates(store: store)
    store.workspace.persistenceBlocked = true
    var installs = 0
    updates.postponeInstallation { installs += 1 }
    await Task.yield()
    #expect(installs == 0)
    #expect(!store.installingUpdate)
    #expect(updates.status?.contains("could not save") == true)
    store.workspace.persistenceBlocked = false
    try await Task.sleep(for: .milliseconds(350))
    #expect(installs == 1)
}

@MainActor @Test func updaterBlocksPendingReviewAndLoading() {
    let store = Store(loadCache: false)
    #expect(store.updateBlockingReason == nil)
    store.workspace.loadingResources = true
    #expect(store.updateBlockingReason != nil)
    store.workspace.loadingResources = false
    store.preparing = true
    #expect(store.updateBlockingReason != nil)
    store.preparing = false
    store.terminating = true
    #expect(!store.canStartReview)
    #expect(!store.workspace.canEdit)
}

private final class SaveGateVault: CredentialVault, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var reads = 0
    let first = DispatchSemaphore(value: 0)
    let second = DispatchSemaphore(value: 0)
    var readCount: Int { lock.withLock { reads } }
    func read(_ id: String) -> Data? {
        let count = lock.withLock { reads += 1; return reads }
        if count == 1 { first.wait() }
        if count == 2 { second.wait() }
        return lock.withLock { values[id] }
    }
    func write(_ value: Data, id: String) { lock.withLock { values[id] = value } }
    func delete(_ id: String) { lock.withLock { values[id] = nil } }
}

@MainActor @Test func workspaceFlushDrainsSavesQueuedWhileWaiting() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let vault = SaveGateVault()
    defer { vault.first.signal(); vault.second.signal() }
    let persistence = WorkspacePersistence(url: folder.appendingPathComponent("workspace.enc"), vault: vault)
    let workspace = WorkspaceStore(load: true, vault: vault, persistence: persistence)
    for _ in 0..<1000 {
        if !workspace.loading && vault.readCount == 1 { break }
        try await Task.sleep(for: .milliseconds(2))
    }
    #expect(!workspace.loading)
    #expect(vault.readCount == 1)
    var flushed = false
    let flush = Task { await workspace.flush(); flushed = true }
    await Task.yield()
    workspace.saveProject(GroveProject(name: "Queued During Flush"))
    vault.first.signal()
    for _ in 0..<1000 {
        if vault.readCount >= 2 { break }
        try await Task.sleep(for: .milliseconds(2))
    }
    #expect(vault.readCount == 2)
    #expect(!flushed)
    vault.second.signal()
    await flush.value
    #expect(flushed)
    #expect(!workspace.persistenceBlocked)
    #expect(try await persistence.load().projects.map(\.name) == ["Queued During Flush"])
}
