import Foundation
import Testing
import GroveCore
@testable import Grove

private actor EmptyRepositoryTransport: GitHubTransport {
    var readIDs: [Int] = []
    func send(_ request: APIRequest) -> APIResponse {
        if request.path.contains("git/trees") { return APIResponse(status: 409, data: Data()) }
        let id = request.path.hasSuffix("first") ? 1 : 2
        readIDs.append(id)
        return APIResponse(status: 200, data: Data("{\"id\":\(id)}".utf8))
    }
}
private func enrichmentRepository(_ id: Int, _ name: String) throws -> Repository {
    try JSONDecoder().decode(Repository.self, from: Data("{\"id\":\(id),\"name\":\"\(name)\",\"full_name\":\"team/\(name)\",\"owner\":{\"login\":\"team\"},\"description\":null,\"language\":null,\"pushed_at\":null,\"updated_at\":\"2026-01-01\",\"archived\":false,\"fork\":false,\"private\":true,\"stargazers_count\":0,\"open_issues_count\":0,\"default_branch\":\"main\"}".utf8))
}

@MainActor @Test func libraryEnrichmentCancellationKeepsCompletedProfilesAndResumesMissingOnly() async throws {
    let first = try enrichmentRepository(1, "first"), second = try enrichmentRepository(2, "second")
    let transport = EmptyRepositoryTransport(), github = GitHubService(transport: transport)
    let workspace = WorkspaceStore(load: false)
    workspace.startEnrichment(repositories: [first, second], using: github) { workspace.stopEnrichment() }
    await workspace.enrichmentTask?.value
    #expect(workspace.profile(for: 1) != nil)
    #expect(workspace.profile(for: 2) == nil)
    #expect(!workspace.enrichment.running)
    workspace.startEnrichment(repositories: [first, second], using: github)
    await workspace.enrichmentTask?.value
    #expect(workspace.enrichment.total == 1)
    #expect(workspace.enrichment.succeeded == 1)
    #expect(workspace.profile(for: 2) != nil)
    #expect(await transport.readIDs == [1, 1, 2, 2])
}

@MainActor @Test func refreshedProfilesPreserveEditedLocalDescriptionsAndGitHubIdentity() async throws {
    let repo = try enrichmentRepository(1, "first"), workspace = WorkspaceStore(load: false)
    workspace.saveProfile(RepositoryProfile(repositoryID: repo.id, fullName: repo.full_name, summary: "Generated", overview: "Generated overview", descriptionSource: "Apple Intelligence", integrations: [], revision: "old", eligibleFiles: 0, scannedFiles: 0, excludedFiles: 0, totalFiles: 0, limitations: []))
    workspace.updateDescription(repositoryID: repo.id, summary: "My description", overview: "My notes")
    workspace.startEnrichment(repositories: [repo], using: GitHubService(transport: EmptyRepositoryTransport()), onlyMissing: false)
    await workspace.enrichmentTask?.value
    #expect(workspace.profile(for: repo.id)?.summary == "My description")
    #expect(workspace.profile(for: repo.id)?.descriptionSource == "Edited in Grove")
    #expect(workspace.profile(for: repo.id)?.revision == "empty")
    #expect(repo.description == nil)
    #expect(RepositoryQuery.filter([repo], scope: .all, owner: nil, search: "description", sort: .name, descriptions: [repo.id: "My description"]) == [repo])
    #expect(RepositoryQuery.filter([repo], scope: .missing, owner: nil, search: "", sort: .name, descriptions: [repo.id: "My description"]).isEmpty)
}

@MainActor @Test func onDeviceRepositoryProfileSmoke() async throws {
    guard ProcessInfo.processInfo.environment["GROVE_PROFILE_AI_SMOKE"] == "1" else { return }
    #expect(Intelligence.available)
    let github = GitHubService()
    let inventory = try await github.inventory()
    let repo = try #require(inventory.repositories.first { $0.full_name == "ZipLyne-Agency/grove" })
    let profile = try await RepositoryAnalyzer.analyze(repo, using: github)
    #expect(profile.scannedFiles > 0)
    #expect(!profile.summary.isEmpty)
    #expect(profile.descriptionSource == "Apple Intelligence")
    #expect(profile.complete)
    print("Profile smoke: \(profile.scannedFiles)/\(profile.eligibleFiles) files; \(profile.integrations.count) integrations; \(profile.summary)")
}

@MainActor @Test func staleWorkspaceErrorDoesNotFailSuccessfulEnrichment() async throws {
    let workspace = WorkspaceStore(load: false)
    workspace.error = "An unrelated earlier error"
    workspace.startEnrichment(repositories: [try enrichmentRepository(1, "first")], using: GitHubService(transport: EmptyRepositoryTransport()))
    await workspace.enrichmentTask?.value
    #expect(workspace.enrichment.succeeded == 1)
    #expect(workspace.enrichment.failed == 0)
}

@MainActor @Test func generatedDescriptionLimitsPreserveReadableBoundaries() {
    let text = "This is a complete first sentence. " + String(repeating: "A supporting detail ", count: 30)
    #expect(RepositoryAnalyzer.clean(text, maximum: 90) == "This is a complete first sentence.")
    let long = RepositoryAnalyzer.clean(String(repeating: "component ", count: 100), maximum: 80)
    #expect(long.count <= 80)
    #expect(long.hasSuffix("…"))
    #expect(!long.hasSuffix("compon…"))
}

@MainActor @Test func hiddenIntegrationsPersistAcrossRefreshAndCanBeRestored() throws {
    let workspace = WorkspaceStore(load: false)
    let integration = RepositoryIntegration(id: "example", name: "Example", category: "Hosting", website: "https://example.com", evidence: [])
    let original = RepositoryProfile(repositoryID: 1, fullName: "team/app", summary: "Summary", overview: "", descriptionSource: "Apple Intelligence", integrations: [integration], revision: "old", eligibleFiles: 0, scannedFiles: 0, excludedFiles: 0, totalFiles: 0, limitations: [])
    workspace.saveProfile(original)
    workspace.setIntegrationHidden(repositoryID: 1, integrationID: "example", hidden: true)
    #expect(workspace.profile(for: 1)?.visibleIntegrations.isEmpty == true)
    let encoded = try JSONEncoder().encode(try #require(workspace.profile(for: 1)))
    let restored = try JSONDecoder().decode(RepositoryProfile.self, from: encoded)
    #expect(restored.hiddenIntegrationIDs == ["example"])
    workspace.saveProfile(original)
    #expect(workspace.profile(for: 1)?.visibleIntegrations.isEmpty == true)
    workspace.setIntegrationHidden(repositoryID: 1, integrationID: "example", hidden: false)
    #expect(workspace.profile(for: 1)?.visibleIntegrations == [integration])
    let legacy = try JSONEncoder().encode(original)
    #expect(try JSONDecoder().decode(RepositoryProfile.self, from: legacy).visibleIntegrations == [integration])
}
