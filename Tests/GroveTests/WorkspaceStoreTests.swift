import Testing
import Foundation
import GroveCore
@testable import Grove

private final class TestVault: CredentialVault, @unchecked Sendable {
    private let lock = NSLock()
    private var data: [String: Data] = [:]
    func read(_ id: String) -> Data? { lock.withLock { data[id] } }
    func write(_ value: Data, id: String) { lock.withLock { data[id] = value } }
    func delete(_ id: String) { lock.withLock { data[id] = nil } }
}
private actor DelayedProvider: ProviderTransport {
    var started = false
    var continuation: CheckedContinuation<ProviderResponse, Never>?
    func send(_ request: ProviderRequest) async -> ProviderResponse {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish(resources: Bool = false) {
        let json = resources ? #"[{"id":"original","name":"Old Account Result"}]"# : #"{"id":"original","name":"Old Account Result"}"#
        continuation?.resume(returning: ProviderResponse(status: 200, data: Data(json.utf8)))
        continuation = nil
    }
}
@MainActor @Test func editedConnectionDiscardsAnInFlightResult() async throws {
    let vault = TestVault(), transport = DelayedProvider()
    let workspace = WorkspaceStore(load: false, provider: ProviderService(transport: transport), vault: vault)
    let account = ProviderAccount(provider: .oneSignal, name: "Test")
    #expect(await workspace.saveAccount(account, credential: "synthetic"))
    var connection = ServiceConnection(provider: .oneSignal, name: "Original", resourceID: "original", accountID: account.id)
    workspace.saveConnection(connection)
    let task = Task { await workspace.sync(connection.id) }
    for _ in 0..<1000 { if await transport.started { break }; await Task.yield() }
    #expect(await transport.started)
    connection.resourceID = "replacement"; workspace.saveConnection(connection)
    await transport.finish(); await task.value
    #expect(workspace.connections.first?.resourceID == "replacement")
    #expect(workspace.connections.first?.snapshot == nil)
}
@MainActor @Test func replacedCredentialDiscardsAnInFlightResult() async throws {
    let vault = TestVault(), transport = DelayedProvider()
    let workspace = WorkspaceStore(load: false, provider: ProviderService(transport: transport), vault: vault)
    let account = ProviderAccount(provider: .oneSignal, name: "Test")
    #expect(await workspace.saveAccount(account, credential: "synthetic"))
    let connection = ServiceConnection(provider: .oneSignal, name: "Original", resourceID: "original", accountID: account.id)
    workspace.saveConnection(connection)
    let task = Task { await workspace.sync(connection.id) }
    for _ in 0..<1000 { if await transport.started { break }; await Task.yield() }
    #expect(await transport.started)
    #expect(await workspace.saveAccount(account, credential: "replacement"))
    await transport.finish(); await task.value
    #expect(workspace.connections.first?.snapshot == nil)
}
@MainActor @Test func removingCredentialRetainsSavedConnectionAndProjectRelations() async throws {
    let workspace = WorkspaceStore(load: false, vault: TestVault())
    let account = ProviderAccount(provider: .oneSignal, name: "Test")
    #expect(await workspace.saveAccount(account, credential: "synthetic"))
    let project = GroveProject(name: "Shared", repositoryIDs: [42]); workspace.saveProject(project)
    let connection = ServiceConnection(provider: .oneSignal, name: "Saved", resourceID: "resource", dashboardURL: "https://example.com", accountID: account.id, projectIDs: [project.id])
    workspace.saveConnection(connection)
    await workspace.removeAccount(account.id)
    #expect(workspace.accounts.isEmpty)
    #expect(workspace.connections(for: 42).first?.id == connection.id)
    #expect(workspace.connections.first?.accountID == nil)
    #expect(workspace.connections.first?.status() == .savedLink)
}
@MainActor @Test func failedArchiveLoadBlocksOverwritingPreservedFile() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("workspace.enc"), original = Data("damaged".utf8)
    try original.write(to: file)
    let vault = TestVault(), persistence = WorkspacePersistence(url: file, vault: vault)
    let workspace = WorkspaceStore(load: false, vault: vault, persistence: persistence)
    await workspace.reload()
    #expect(workspace.persistenceBlocked)
    workspace.saveProject(GroveProject(name: "Must Not Overwrite"))
    #expect(workspace.projects.isEmpty)
    #expect(try Data(contentsOf: file) == original)
}

@MainActor @Test func projectAssistantOpensOnlyThatProjectsSavedLinks() throws {
    let store = Store(loadCache: false)
    let first = GroveProject(name: "First"), second = GroveProject(name: "Second")
    store.workspace.saveProject(first); store.workspace.saveProject(second)
    let firstService = ServiceConnection(provider: .cloudflare, name: "First Worker", dashboardURL: "https://example.com/first", projectIDs: [first.id])
    let otherService = ServiceConnection(provider: .cloudflare, name: "Other Worker", dashboardURL: "https://example.com/other", projectIDs: [second.id])
    store.workspace.saveConnection(firstService); store.workspace.saveConnection(otherService)
    store.requestProjectAssistant("Open Cloudflare", project: first)
    #expect(store.assistantSubject == "First")
    #expect(store.assistantServices.map(\.id) == [firstService.id])
    #expect(store.assistantOpenServices.map(\.id) == [firstService.id])
    #expect(store.assistantTask == nil)
    #expect(store.preview == nil)
}

@MainActor @Test func accountProviderChangeCannotReuseOrReplaceACredential() async throws {
    let vault = TestVault(), transport = DelayedProvider()
    let workspace = WorkspaceStore(load: false, provider: ProviderService(transport: transport), vault: vault)
    let account = ProviderAccount(provider: .oneSignal, name: "Original")
    #expect(await workspace.saveAccount(account, credential: "original-token"))
    var draft = account; draft.provider = .vercel
    #expect(await !workspace.saveAccount(draft, credential: ""))
    #expect(await !workspace.saveAccount(draft, credential: "replacement-token"))
    #expect(vault.read(account.id.uuidString) == Data("original-token".utf8))
    #expect(workspace.accounts == [account])
    await workspace.loadResources(draft)
    #expect(await !transport.started)
    #expect(workspace.resources.isEmpty)
}

@MainActor @Test func clearingResourcesInvalidatesAnInFlightPicker() async throws {
    let vault = TestVault(), transport = DelayedProvider()
    let workspace = WorkspaceStore(load: false, provider: ProviderService(transport: transport), vault: vault)
    let account = ProviderAccount(provider: .oneSignal, name: "Test")
    #expect(await workspace.saveAccount(account, credential: "synthetic"))
    let task = Task { await workspace.loadResources(account) }
    for _ in 0..<1000 { if await transport.started { break }; await Task.yield() }
    #expect(await transport.started)
    workspace.clearResources()
    await transport.finish(resources: true); await task.value
    #expect(workspace.resources.isEmpty)
    #expect(workspace.resourceAccountID == nil)
    #expect(!workspace.loadingResources)
}

private actor VercelStoreTransport: ProviderTransport {
    var name = "original"
    func send(_ request: ProviderRequest) throws -> ProviderResponse {
        if request.method == "PATCH" { name = "renamed" }
        let value: [String: Any]
        if request.url.path.hasSuffix("/user") { value = ["user": ["username": "studio"]] }
        else if request.url.path.hasSuffix("/deployments") { value = ["deployments": []] }
        else { value = ["id": "prj_stable", "name": name] }
        return ProviderResponse(status: 200, data: try JSONSerialization.data(withJSONObject: value))
    }
}

@MainActor @Test func confirmedRenamePersistsCanonicalIdentityAndNewDashboard() async throws {
    let workspace = WorkspaceStore(load: false, provider: ProviderService(transport: VercelStoreTransport()), vault: TestVault())
    let account = ProviderAccount(provider: .vercel, name: "Test")
    #expect(await workspace.saveAccount(account, credential: "synthetic"))
    let connection = ServiceConnection(provider: .vercel, name: "Saved", resourceID: "original", dashboardURL: "https://vercel.com/studio/original", accountID: account.id)
    workspace.saveConnection(connection)
    await workspace.prepareRename(connection, name: "renamed")
    #expect(workspace.renameReview != nil)
    await workspace.confirmRename()
    let saved = try #require(workspace.connections.first)
    #expect(saved.resourceID == "prj_stable")
    #expect(saved.dashboardURL == "https://vercel.com/studio/renamed")
    #expect(saved.lastAttemptAt != nil)
    #expect(workspace.renameReview == nil)
    await workspace.sync(connection.id)
    #expect(workspace.connections.first?.lastError == nil)
}

@MainActor @Test func exactDashboardOverrideSurvivesProviderRefresh() async throws {
    let workspace = WorkspaceStore(load: false, provider: ProviderService(transport: VercelStoreTransport()), vault: TestVault())
    let account = ProviderAccount(provider: .vercel, name: "Test")
    #expect(await workspace.saveAccount(account, credential: "synthetic"))
    var connection = ServiceConnection(provider: .vercel, name: "Saved", resourceID: "prj_stable", accountID: account.id)
    workspace.saveConnection(connection)
    connection = try #require(workspace.connections.first)
    connection.dashboardURL = "https://vercel.com/studio/original/settings"
    workspace.saveConnection(connection)
    await workspace.sync(connection.id)
    #expect(workspace.connections.first?.dashboardURL == connection.dashboardURL)
    #expect(workspace.connections.first?.snapshot?.dashboardURL == "https://vercel.com/studio/original")
}
