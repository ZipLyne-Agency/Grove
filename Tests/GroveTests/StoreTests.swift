import Testing
import Foundation
import GroveCore
@testable import Grove

private func sampleRepository() throws -> Repository {
    try JSONDecoder().decode(Repository.self, from: Data(#"{"id":1,"name":"project","full_name":"studio/project","owner":{"login":"studio"},"description":"Example","language":"Swift","pushed_at":"2026-10-06T12:00:00Z","updated_at":"2026-10-06T12:00:00Z","archived":false,"fork":false,"private":true,"stargazers_count":0,"open_issues_count":0,"default_branch":"main","permissions":{"admin":true}}"#.utf8))
}
private func sampleInventory(_ repo: Repository, requiresRefresh: Bool = false) throws -> Inventory {
    let account = try JSONDecoder().decode(Account.self, from: Data(#"{"login":"demo-user"}"#.utf8))
    return Inventory(account: account, organizations: [], repositories: [repo], requiresRefresh: requiresRefresh)
}
private actor NoNetwork: GitHubTransport {
    func send(_ request: APIRequest) throws -> APIResponse { throw GroveError.transportFailure }
}
private actor UncertainWrite: GitHubTransport {
    func send(_ request: APIRequest) throws -> APIResponse {
        if request.path == "user" { return APIResponse(status: 200, data: Data(#"{"login":"demo-user"}"#.utf8)) }
        if request.method != "GET" { throw GroveError.outcomeUnknown }
        return APIResponse(status: 200, data: try JSONEncoder().encode(sampleRepository()))
    }
}
@MainActor @Test func openPreviewCannotBeReplaced() async throws {
    let repo = try sampleRepository()
    let store = Store(service: GitHubService(transport: NoNetwork()), loadCache: false)
    store.inventory = try sampleInventory(repo)
    await store.prepare(repo, action: .rename("first"))
    let id = try #require(store.preview?.id)
    await store.prepare(repo, action: .delete)
    #expect(store.preview?.id == id)
    #expect(store.preview?.action == .rename("first"))
    store.cancelPreview()
}
@MainActor @Test func refreshAndEditorBlockAnotherProposal() async throws {
    let repo = try sampleRepository()
    let store = Store(service: GitHubService(transport: NoNetwork()), loadCache: false)
    store.inventory = try sampleInventory(repo)
    store.requestRefresh()
    await store.prepare(repo, action: .delete)
    #expect(store.preview == nil)
    await store.operationTask?.value
    store.requestEdit(repo, kind: .rename)
    await store.prepare(repo, action: .delete)
    #expect(store.preview == nil)
    #expect(store.editor?.kind == .rename)
}
@MainActor @Test func oldSuccessClearedWhenRefreshFails() async {
    let store = Store(service: GitHubService(transport: NoNetwork()), loadCache: false)
    store.lastAction = "Old success"
    await store.refresh()
    #expect(store.lastAction == nil)
    #expect(store.message != nil)
}
@MainActor @Test func staleSnapshotBlocksFurtherReviews() async throws {
    let repo = try sampleRepository()
    let store = Store(service: GitHubService(transport: NoNetwork()), loadCache: false)
    store.inventory = try sampleInventory(repo, requiresRefresh: true)
    await store.prepare(repo, action: .delete)
    #expect(store.preview == nil)
    #expect(store.needsRefresh)
}
@MainActor @Test func unknownWriteMarksSnapshotAndPersistsRequirement() async throws {
    let repo = try sampleRepository()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = InventoryCache(url: directory.appendingPathComponent("inventory.json"))
    let store = Store(service: GitHubService(transport: UncertainWrite()), cache: cache, loadCache: false)
    store.inventory = try sampleInventory(repo)
    await store.prepare(repo, action: .rename("renamed"))
    let preview = try #require(store.preview)
    await store.execute(preview, typedName: "")
    #expect(store.needsRefresh)
    #expect(store.lastAction == nil)
    let persisted = await cache.load()
    #expect(persisted != nil, Comment(rawValue: store.message ?? "No store error"))
    #expect(persisted?.requiresRefresh == true)
    await store.prepare(repo, action: .delete)
    #expect(store.preview == nil)
}
@MainActor @Test func proposalNeverAutomaticallyOpensReview() throws {
    let repo = try sampleRepository()
    let store = Store(loadCache: false)
    store.suggestion = AssistantSuggestion(repo: repo, action: .delete)
    #expect(store.preview == nil)
}

private actor VerifiedRename: GitHubTransport {
    var changed = false
    func send(_ request: APIRequest) throws -> APIResponse {
        if request.path == "user" { return APIResponse(status: 200, data: Data(#"{"login":"demo-user"}"#.utf8)) }
        if request.method == "PATCH" { changed = true }
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sampleRepository())) as! [String: Any]
        if changed { object["name"] = "renamed"; object["full_name"] = "studio/renamed" }
        return APIResponse(status: 200, data: try JSONSerialization.data(withJSONObject: object))
    }
}
@MainActor @Test func verifiedEditKeepsRepositoryVisible() async throws {
    let repo = try sampleRepository()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = Store(service: GitHubService(transport: VerifiedRename()), cache: InventoryCache(url: directory.appendingPathComponent("inventory.json")), loadCache: false)
    store.inventory = try sampleInventory(repo)
    await store.prepare(repo, action: .rename("renamed"))
    let preview = try #require(store.preview)
    await store.execute(preview, typedName: "")
    #expect(store.inventory?.repositories.count == 1)
    #expect(store.inventory?.repositories.first?.name == "renamed")
    #expect(!store.needsRefresh)
    #expect(store.lastAction?.contains("verified") == true)
}

@MainActor @Test func refreshBlocksAnotherReviewImmediately() async {
    let store = Store(service: GitHubService(transport: NoNetwork()), loadCache: false)
    store.requestRefresh()
    #expect(store.operationInFlight)
    #expect(store.consent == nil)
    store.requestRefresh()
    await store.operationTask?.value
    #expect(!store.operationInFlight)
}

@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["GROVE_AI_SMOKE"] == "1"))
func onDeviceAssistantSmoke() async throws {
    guard Intelligence.available else { throw GroveError.unavailableAI }
    let repo = try sampleRepository()
    let result = try await Intelligence.answer(prompt: "Explain what this project does. Do not propose a change.", repo: repo,
                                             readme: "Project is a native Swift macOS utility that helps organize GitHub repositories. It uses SwiftUI and AppKit.",
                                             inventory: sampleInventory(repo))
    #expect(!result.answer.isEmpty)
    #expect(result.action == nil)
}

@MainActor @Test func hiddenOwnersUpdateImmediatelyAndPersist() async throws {
    let repo = try sampleRepository()
    let suite = "grove-test-\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let store = Store(loadCache: false, preferences: preferences)
    store.inventory = try sampleInventory(repo)
    store.owner = "studio"
    store.requestOwnerVisibility("studio", hidden: true)
    #expect(store.consent == nil)
    await store.queryTask?.value
    #expect(store.visible.isEmpty)
    #expect(store.owner == nil)
    #expect(store.owners.isEmpty)
    #expect(store.allOwners == ["studio"])
    #expect(store.counts.count(.all) == 0)
    #expect(store.counts.count(owner: "studio") == 1)
    let restored = Store(loadCache: false, preferences: preferences)
    #expect(restored.hiddenOwners == ["studio"])
    store.requestOwnerVisibility("studio", hidden: false)
    await store.queryTask?.value
    #expect(store.visible.map(\.id) == [repo.id])
    #expect(store.counts.count(.all) == 1)
}

@MainActor @Test func contextAssistantCapturesClickedRepositoryAndOwner() throws {
    let repo = try sampleRepository()
    let store = Store(loadCache: false)
    store.inventory = try sampleInventory(repo)
    store.selectedID = nil
    store.requestAssistant("Propose a new description", repo: repo)
    #expect(store.selectedID == repo.id)
    #expect(store.assistantSubject == repo.full_name)
    #expect(store.assistantContext?.repositories.count == 1)
    #expect(store.consent == nil)
    store.requestAssistant("Delete", owner: "other")
    #expect(store.assistantSubject == repo.full_name)
    store.assistantTask?.cancel()

}

@MainActor @Test func contextActionsCannotReplaceOpenReview() throws {
    let repo = try sampleRepository()
    let store = Store(loadCache: false)
    store.requestEdit(repo, kind: .rename)
    store.requestOwnerVisibility("studio", hidden: true)
    store.requestCopy("https://github.com/studio/project")
    #expect(store.consent == nil)
    #expect(store.editor?.repo.id == repo.id)
}

@MainActor @Test func assistantPresetUsesClickedLibraryScope() throws {
    let repo = try sampleRepository()
    let store = Store(loadCache: false)
    store.inventory = try sampleInventory(repo)
    store.requestAssistant("Summarize archived repositories", libraryScope: .archived)
    #expect(store.assistantContext?.repositories.isEmpty == true)
    #expect(store.assistantScope == .archived)
    store.assistantTask?.cancel()
}

@MainActor @Test func sortingChoiceSurvivesAStoreRestart() throws {
    let suite = "grove-sorting-test-" + UUID().uuidString
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let store = Store(service: GitHubService(transport: NoNetwork()), loadCache: false, preferences: preferences)
    store.sort = .createdOldest
    let reopened = Store(service: GitHubService(transport: NoNetwork()), loadCache: false, preferences: preferences)
    #expect(reopened.sort == .createdOldest)
}
