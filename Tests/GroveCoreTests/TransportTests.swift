import Foundation
import Testing
@testable import GroveCore

@Test func parsesHeadersAndJSONWithoutRetainingHeaders() throws {
    let output = Data("HTTP/2.0 200 OK\r\nX-OAuth-Scopes: repo\r\nContent-Type: application/json\r\n\r\n{\"login\":\"demo-user\"}".utf8)
    let result = try CLITransport.parse(output, method: "GET", exitCode: 0)
    #expect(result.status == 200)
    #expect(String(data: result.data, encoding: .utf8) == #"{"login":"demo-user"}"#)
}
@Test func parsesEmptyDeleteResponse() throws {
    let result = try CLITransport.parse(Data("HTTP/2.0 204 No Content\nX-Test: value\n\n".utf8), method: "DELETE", exitCode: 0)
    #expect(result.status == 204)
    #expect(result.data.isEmpty)
}
@Test func separatesNetworkFailuresFromLoginFailures() throws {
    #expect(throws: GroveError.transportFailure) { try CLITransport.parse(Data(), method: "GET", exitCode: 1) }
    #expect(throws: GroveError.outcomeUnknown) { try CLITransport.parse(Data(), method: "DELETE", exitCode: 1) }
    #expect(throws: GroveError.outcomeUnknown) { try CLITransport.parse(Data(), method: "PATCH", exitCode: 1) }
}
@Test func parsesHTTPErrorWithoutMisreportingSuccess() throws {
    let result = try CLITransport.parse(Data("HTTP/2.0 403 Forbidden\n\n{\"message\":\"Forbidden\"}".utf8), method: "DELETE", exitCode: 1)
    #expect(result.status == 403)
}
@Test func rejectsMalformedHTTPStatus() throws {
    #expect(throws: GroveError.invalidResponse) { try CLITransport.parse(Data("HTTP/wrong ABC\n\n{}".utf8), method: "GET", exitCode: 0) }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["GROVE_LIVE_READ_SMOKE"] == "1"))
func liveGitHubReadSmoke() async throws {
    let service = GitHubService()
    let snapshot = try await service.inventory()
    #expect(!snapshot.account.login.isEmpty)
    #expect(!snapshot.repositories.isEmpty)
    #expect(Set(snapshot.repositories.map(\.id)).count == snapshot.repositories.count)
    #expect(snapshot.repositories.allSatisfy { $0.safeIdentity })
}
