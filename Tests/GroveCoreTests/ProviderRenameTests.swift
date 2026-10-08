import Foundation
import Testing
@testable import GroveCore

private actor ProjectRenameTransport: ProviderTransport {
    let provider: ServiceProvider
    var name = "original"
    var writes: [ProviderRequest] = []
    init(_ provider: ServiceProvider) { self.provider = provider }
    func send(_ request: ProviderRequest) throws -> ProviderResponse {
        if request.method != "GET" {
            writes.append(request)
            let body = try JSONDecoder().decode([String: String].self, from: request.body!)
            name = body["name"]!
        }
        let value: [String: Any]
        if provider == .sentry { value = ["slug": "stable-slug", "name": name] }
        else if request.url.path.hasSuffix("/deployments") { value = ["deployments": []] }
        else if request.url.path.hasSuffix("/user") { value = ["user": ["username": "studio"]] }
        else { value = ["id": "prj_stable", "name": name] }
        return ProviderResponse(status: 200, data: try JSONSerialization.data(withJSONObject: value))
    }
}

@Test(arguments: [ServiceProvider.vercel, .sentry])
func reviewedProjectRenameUsesStableIDMethodAndAccountScope(_ provider: ServiceProvider) async throws {
    let transport = ProjectRenameTransport(provider), service = ProviderService(transport: transport)
    let account = ProviderAccount(provider: provider, name: "Test", scope: "team_test")
    let connection = ServiceConnection(provider: provider, name: "Saved", resourceID: provider == .vercel ? "original" : "stable-slug", accountID: account.id)
    let credential = Data("synthetic".utf8)
    let review = try await service.prepareRename(connection, account: account, credential: credential, name: "renamed")
    #expect(await transport.writes.isEmpty)
    let result = try await service.approveRename(review.id, credential: credential)
    #expect(result.name == "renamed")
    let writes = await transport.writes
    #expect(writes.count == 1)
    let write = try #require(writes.first)
    if provider == .vercel {
        #expect(write.method == "PATCH")
        #expect(write.url.path == "/v9/projects/prj_stable")
        #expect(URLComponents(url: write.url, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "teamId", value: "team_test")])
        #expect(result.resourceID == "prj_stable")
        #expect(result.dashboardURL == "https://vercel.com/studio/renamed")
    } else {
        #expect(write.method == "PUT")
        #expect(write.url.absoluteString == "https://sentry.io/api/0/projects/team_test/stable-slug/")
        #expect(result.resourceID == "stable-slug")
    }
    await #expect(throws: WorkspaceError.staleReview) { try await service.approveRename(review.id, credential: credential) }
}
