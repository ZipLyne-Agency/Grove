import Testing
import Foundation
@testable import GroveCore

func fixture(name: String = "project", owner: String = "studio", id: Int = 1, admin: Bool = true, updated: String = "2026-10-06T12:00:00Z", description: String? = "A project", archived: Bool = false) throws -> Repository {
    let json: [String: Any] = ["id": id, "name": name, "full_name": "\(owner)/\(name)", "owner": ["login": owner], "description": description as Any? ?? NSNull(), "language": "Swift", "pushed_at": "2026-10-05T12:00:00Z", "updated_at": updated, "archived": archived, "fork": false, "private": true, "stargazers_count": 0, "open_issues_count": 1, "default_branch": "main", "permissions": ["admin": admin], "topics": ["macos"]]
    return try JSONDecoder().decode(Repository.self, from: JSONSerialization.data(withJSONObject: json))
}
func inventory(_ repo: Repository) throws -> Inventory {
    let account = try JSONDecoder().decode(Account.self, from: Data(#"{"login":"demo-user"}"#.utf8))
    let orgs = try JSONDecoder().decode([Organization].self, from: Data(#"[{"login":"destination"}]"#.utf8))
    return Inventory(account: account, organizations: orgs, repositories: [repo])
}
actor FakeTransport: GitHubTransport {
    var requests: [APIRequest] = []
    var repository: Repository
    var login = "demo-user"
    var targetExists = false
    var failWrites = false
    var failedStatus = 403
    var deleted = false
    init(repository: Repository) { self.repository = repository }
    func setLogin(_ value: String) { login = value }
    func setRepository(_ value: Repository) { repository = value }
    func setTargetExists() { targetExists = true }
    func setFailWrites(status: Int = 403) { failWrites = true; failedStatus = status }
    var writes: [APIRequest] { requests.filter { $0.method != "GET" } }
    func send(_ request: APIRequest) async throws -> APIResponse {
        requests.append(request)
        if request.path == "user" { return APIResponse(status: 200, data: Data("{\"login\":\"\(login)\"}".utf8)) }
        if request.path.hasPrefix("user/orgs") { return APIResponse(status: 200, data: Data(#"[{"login":"destination"}]"#.utf8)) }
        if request.path.hasPrefix("user/repos") { return APIResponse(status: 200, data: try JSONEncoder().encode([repository])) }
        if request.path == "repos/destination/project" { return APIResponse(status: targetExists ? 200 : 404, data: Data()) }
        if request.method == "DELETE" {
            if failWrites { return APIResponse(status: failedStatus, data: Data()) }
            deleted = true; return APIResponse(status: 204, data: Data())
        }
        if request.method == "POST" { return APIResponse(status: 202, data: try JSONEncoder().encode(repository)) }
        if request.method == "PATCH" {
            let body = try JSONSerialization.jsonObject(with: request.body!) as! [String: Any]
            repository = try fixture(name: body["name"] as? String ?? repository.name,
                                     description: body["description"] as? String ?? repository.description,
                                     archived: body["archived"] as? Bool ?? repository.archived)
        }
        return APIResponse(status: deleted ? 404 : 200, data: try JSONEncoder().encode(repository))
    }
}

@Test func preparingAndCancellingNeverWrites() async throws {
    let repo = try fixture(), mock = FakeTransport(repository: try fixture())
    let service = GitHubService(transport: mock)
    let preview = try await service.prepare(repo: repo, action: .delete, inventory: inventory(repo))
    #expect(await mock.requests.isEmpty)
    await service.cancel(preview.id)
    await #expect(throws: GroveError.expiredPreview) { try await service.approve(preview.id, typedName: repo.full_name) }
    #expect(await mock.writes.isEmpty)
}
@Test func deletionRequiresExactNameAndIsSingleUse() async throws {
    let repo = try fixture(), mock = FakeTransport(repository: try fixture())
    let service = GitHubService(transport: mock)
    let preview = try await service.prepare(repo: repo, action: .delete, inventory: inventory(repo))
    await #expect(throws: GroveError.confirmationRequired) { try await service.approve(preview.id, typedName: "project") }
    #expect(await mock.requests.isEmpty)
    let result = try await service.approve(preview.id, typedName: repo.full_name)
    if case .verified = result {} else { Issue.record("Deletion was not verified") }
    await #expect(throws: GroveError.expiredPreview) { try await service.approve(preview.id, typedName: repo.full_name) }
    #expect(await mock.writes.count == 1)
}
@Test func concurrentApprovalCanWriteOnlyOnce() async throws {
    let repo = try fixture(), mock = FakeTransport(repository: try fixture())
    let service = GitHubService(transport: mock)
    let preview = try await service.prepare(repo: repo, action: .archive(true), inventory: inventory(repo))
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<8 { group.addTask { _ = try? await service.approve(preview.id) } }
    }
    #expect(await mock.writes.count == 1)
}
@Test func changingAccountBlocksWrite() async throws {
    let repo = try fixture(), mock = FakeTransport(repository: try fixture())
    let service = GitHubService(transport: mock)
    let preview = try await service.prepare(repo: repo, action: .rename("new-name"), inventory: inventory(repo))
    await mock.setLogin("someone-else")
    await #expect(throws: GroveError.accountChanged) { try await service.approve(preview.id) }
    #expect(await mock.writes.isEmpty)
}
@Test func staleRepositoryBlocksWrite() async throws {
    let repo = try fixture(), mock = FakeTransport(repository: try fixture(updated: "2026-10-06T13:00:00Z"))
    let service = GitHubService(transport: mock)
    let preview = try await service.prepare(repo: repo, action: .describe("New description"), inventory: inventory(repo))
    await #expect(throws: GroveError.stalePreview) { try await service.approve(preview.id) }
    #expect(await mock.writes.isEmpty)
}
@Test func reusedPathWithDifferentIDBlocksWrite() async throws {
    let repo = try fixture(), mock = FakeTransport(repository: try fixture(id: 2))
    let service = GitHubService(transport: mock)
    let preview = try await service.prepare(repo: repo, action: .delete, inventory: inventory(repo))
    await #expect(throws: GroveError.stalePreview) { try await service.approve(preview.id, typedName: repo.full_name) }
    #expect(await mock.writes.isEmpty)
}
@Test func losingAdminBlocksWrite() async throws {
    let repo = try fixture(), mock = FakeTransport(repository: try fixture(admin: false))
    let service = GitHubService(transport: mock)
    let preview = try await service.prepare(repo: repo, action: .rename("renamed"), inventory: inventory(repo))
    await #expect(throws: GroveError.noAdministration) { try await service.approve(preview.id) }
    #expect(await mock.writes.isEmpty)
}
@Test func transferRequiresTypingAndChecksCollision() async throws {
    let repo = try fixture(), mock = FakeTransport(repository: try fixture())
    let service = GitHubService(transport: mock)
    let preview = try await service.prepare(repo: repo, action: .transfer("destination"), inventory: inventory(repo))
    await #expect(throws: GroveError.confirmationRequired) { try await service.approve(preview.id) }
    await mock.setTargetExists()
    await #expect(throws: GroveError.destinationExists) { try await service.approve(preview.id, typedName: repo.full_name) }
    #expect(await mock.writes.isEmpty)
}
@Test func transferIsReportedAsRequested() async throws {
    let repo = try fixture(), mock = FakeTransport(repository: try fixture())
    let service = GitHubService(transport: mock)
    let preview = try await service.prepare(repo: repo, action: .transfer("destination"), inventory: inventory(repo))
    let result = try await service.approve(preview.id, typedName: repo.full_name)
    if case .transferRequested = result {} else { Issue.record("Transfer was reported as complete") }
    #expect(await mock.writes.first?.path == "repos/studio/project/transfer")
}
@Test func invalidNamesCannotCreatePreview() async throws {
    let repo = try fixture(), service = GitHubService(transport: FakeTransport(repository: try fixture()))
    for name in ["../other", "x?delete=true", "a/b", "", ".", "..", "project"] {
        await #expect(throws: GroveError.invalidName) { try await service.prepare(repo: repo, action: .rename(name), inventory: inventory(repo)) }
    }
}
@Test func descriptionPayloadPreservesLiteralText() async throws {
    let repo = try fixture(), mock = FakeTransport(repository: try fixture())
    let service = GitHubService(transport: mock)
    let text = "A `project` with $(literal) and \"quotes\""
    let preview = try await service.prepare(repo: repo, action: .describe(text), inventory: inventory(repo))
    _ = try await service.approve(preview.id)
    let payload = try #require(await mock.writes.first?.body)
    let json = try JSONSerialization.jsonObject(with: payload) as! [String: String]
    #expect(json["description"] == text)
}
@Test func failedWriteIsNeverRetried() async throws {
    let repo = try fixture(), mock = FakeTransport(repository: try fixture())
    await mock.setFailWrites()
    let service = GitHubService(transport: mock)
    let preview = try await service.prepare(repo: repo, action: .delete, inventory: inventory(repo))
    await #expect(throws: GroveError.commandFailed(403)) { try await service.approve(preview.id, typedName: repo.full_name) }
    await #expect(throws: GroveError.expiredPreview) { try await service.approve(preview.id, typedName: repo.full_name) }
    #expect(await mock.writes.count == 1)
}
@Test func filteringFindsDescriptionsOwnersAndTopics() throws {
    let repo = try fixture()
    #expect(RepositoryQuery.filter([repo], scope: .all, owner: "studio", search: "project swift macos", sort: .pushed).count == 1)
    #expect(RepositoryQuery.filter([repo], scope: .all, owner: "other", search: "", sort: .pushed).isEmpty)
    #expect(RepositoryQuery.filter([repo], scope: .missing, owner: nil, search: "", sort: .name).isEmpty)
}

@Test func serverErrorAfterWriteIsAnUnknownOutcome() async throws {
    let repo = try fixture(), mock = FakeTransport(repository: try fixture())
    await mock.setFailWrites(status: 503)
    let service = GitHubService(transport: mock)
    let preview = try await service.prepare(repo: repo, action: .delete, inventory: inventory(repo))
    await #expect(throws: GroveError.outcomeUnknown) { try await service.approve(preview.id, typedName: repo.full_name) }
    #expect(await mock.writes.count == 1)
}
