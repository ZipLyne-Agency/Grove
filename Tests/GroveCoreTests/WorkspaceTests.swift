import Testing
import Foundation
import CryptoKit
@testable import GroveCore

final class MemoryVault: CredentialVault, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(_ id: String) -> Data? { lock.withLock { values[id] } }
    func write(_ value: Data, id: String) { lock.withLock { values[id] = value } }
    func delete(_ id: String) { lock.withLock { values[id] = nil } }
}
@Test func workspaceWriterLeaseExcludesConcurrentProcessesAndReleases() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var first: WorkspaceLease? = try WorkspaceLease(directory: directory)
    #expect(first != nil)
    #expect(throws: WorkspaceError.workspaceBusy) { try WorkspaceLease(directory: directory) }
    first = nil
    let next = try WorkspaceLease(directory: directory)
    withExtendedLifetime(next) {}
}
@Test func encryptedWorkspaceRoundTripAndCorruptionPreserved() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("workspace.enc"), vault = MemoryVault()
    let persistence = WorkspacePersistence(url: url, vault: vault)
    var archive = WorkspaceArchive(); archive.projects = [GroveProject(name: "Private Project", repositoryIDs: [42])]
    try await persistence.save(archive)
    let bytes = try Data(contentsOf: url)
    #expect(!String(decoding: bytes, as: UTF8.self).contains("Private Project"))
    #expect(try await persistence.load() == archive)
    let corrupt = Data("corrupt".utf8); try corrupt.write(to: url)
    await #expect(throws: WorkspaceError.corruptArchive) { try await persistence.load() }
    #expect(try Data(contentsOf: url) == corrupt)
}
@Test func sharedConnectionsSurviveProjectRemoval() {
    var archive = WorkspaceArchive()
    let first = GroveProject(name: "First", repositoryIDs: [1]), second = GroveProject(name: "Second", repositoryIDs: [2])
    archive.projects = [first, second]
    let connection = ServiceConnection(provider: .custom, name: "Shared", dashboardURL: "https://example.com", projectIDs: [first.id, second.id])
    archive.connections = [connection]
    #expect(archive.connections(for: 1).count == 1)
    archive.removeProject(first.id)
    #expect(archive.connections.count == 1)
    #expect(archive.connections(for: 1).isEmpty)
    #expect(archive.connections(for: 2).first?.id == connection.id)
}
@Test func dashboardRejectsCredentialsAndTokenQueries() {
    for text in ["http://example.com", "https://user:secret@example.com", "https://example.com?token=secret", "https://localhost/x", "javascript:alert(1)"] { #expect(ServiceCatalog.safeURL(text) == nil) }
    #expect(ServiceCatalog.safeURL("https://search.google.com/search-console?resource_id=sc-domain%3Aexample.com") != nil)
}
private actor RenameTransport: ProviderTransport {
    var name = "Original"
    var writes = 0
    var rejectWrite = false
    func alterName() { name = "Changed Elsewhere" }
    func send(_ request: ProviderRequest) throws -> ProviderResponse {
        if request.method == "PUT" {
            writes += 1
            if rejectWrite { throw WorkspaceError.network }
            let json = try JSONDecoder().decode([String: String].self, from: request.body!)
            name = json["name"]!
        }
        return ProviderResponse(status: 200, data: try JSONSerialization.data(withJSONObject: ["id":"app-id", "name":name, "players":12, "basic_auth_key":"DO-NOT-RETAIN"]))
    }
}
@Test func providerRenameIsReviewedSingleUseAndProjectsOnlyMetadata() async throws {
    let transport = RenameTransport(), provider = ProviderService(transport: transport)
    let account = ProviderAccount(provider: .oneSignal, name: "Test")
    let connection = ServiceConnection(provider: .oneSignal, name: "Test", resourceID: "app-id", accountID: account.id)
    let credential = Data("synthetic-token".utf8)
    let review = try await provider.prepareRename(connection, account: account, credential: credential, name: "Renamed")
    #expect(await transport.writes == 0)
    let snapshot = try await provider.approveRename(review.id, credential: credential)
    #expect(snapshot.name == "Renamed")
    #expect(!String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self).contains("DO-NOT-RETAIN"))
    await #expect(throws: WorkspaceError.staleReview) { try await provider.approveRename(review.id, credential: credential) }
    #expect(await transport.writes == 1)
}
@Test func providerRenameRejectsChangedResourceOrCredentials() async throws {
    let transport = RenameTransport(), provider = ProviderService(transport: transport)
    let account = ProviderAccount(provider: .oneSignal, name: "Test")
    let connection = ServiceConnection(provider: .oneSignal, name: "Test", resourceID: "app-id", accountID: account.id)
    let credential = Data("synthetic-token".utf8)
    let review = try await provider.prepareRename(connection, account: account, credential: credential, name: "Renamed")
    await transport.alterName()
    await #expect(throws: WorkspaceError.staleReview) { try await provider.approveRename(review.id, credential: credential) }
    #expect(await transport.writes == 0)
    let next = try await provider.prepareRename(connection, account: account, credential: credential, name: "Renamed")
    await #expect(throws: WorkspaceError.staleReview) { try await provider.approveRename(next.id, credential: Data("different".utf8)) }
    #expect(await transport.writes == 0)
}
@Test func invalidServiceEndpointsAndSigningKeysFailClosed() async {
    #expect(throws: WorkspaceError.invalidResponse) { try ProviderAPI.endpoint("attacker.example", "/apps") }
    #expect(JWT.rsaDER(Data([0x30,0x84,0xff,0xff,0xff,0xff])) == nil)
    #expect(throws: (any Error).self) { try JWT.apple(pem: "invalid", issuer: "test", keyID: "test") }
    await #expect(throws: (any Error).self) { try await ProviderHTTP().send(ProviderRequest(url: URL(string:"https://attacker.example")!)) }
}

@Test func serviceOpeningUsesOnlyLinkedContextAndHandlesAmbiguity() {
    let first = ServiceConnection(provider: .cloudflare, name: "API", resourceID: "worker-api", dashboardURL: "https://example.com/api", environment: "Production")
    let second = ServiceConnection(provider: .cloudflare, name: "Site", resourceID: "worker-site", dashboardURL: "https://example.com/site")
    let unrelated = ServiceConnection(provider: .sentry, name: "Errors", dashboardURL: "https://example.com/errors")
    #expect(ServiceResolver.resolve("Open Cloudflare", in: [first, second, unrelated]).count == 2)
    #expect(ServiceResolver.resolve("Open the CF dashboard for API", in: [first, second]).map(\.id) == [first.id])
    #expect(ServiceResolver.resolve("Open Stripe", in: [first, second]).isEmpty)
    #expect(ServiceResolver.resolve("Open CF https://attacker.example", in: [first, second]).isEmpty)
    #expect(ServiceResolver.resolve("Open Sentry", in: [first, second]).isEmpty)
}
