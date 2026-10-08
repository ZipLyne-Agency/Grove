import Foundation
import CryptoKit
import Testing
@testable import GroveCore

private actor AdapterTransport: ProviderTransport {
    let provider: ServiceProvider
    init(_ provider: ServiceProvider) { self.provider = provider }
    func send(_ request: ProviderRequest) throws -> ProviderResponse {
        let path = request.url.path
        var value: [String: Any]
        if request.url.host == "oauth2.googleapis.com" { value = ["access_token":"synthetic-access", "expires_in":3600] }
        else {
            switch provider {
            case .oneSignal: value = ["id":"resource", "name":"Test", "players":7, "basic_auth_key":"DO_NOT_RETAIN"]
            case .revenueCat:
                if path.hasSuffix("/apps") { value = ["items":[["name":"iOS", "type":"app_store", "shared_secret":"DO_NOT_RETAIN"]]] }
                else if path.hasSuffix("/overview") { value = ["currency":"USD", "metrics":[["id":"active_trials", "name":"Active Trials", "value":3, "unit":"#", "period":"P0D"]]] }
                else { value = ["items":[["id":"resource", "name":"Test"]]] }
            case .sentry: value = ["slug":"resource", "name":"Test", "latestRelease":["version":"1.0", "dateCreated":"2026-10-01T12:00:00Z"], "secret":"DO_NOT_RETAIN"]
            case .expo: value = ["data":["app":["byId":["id":"resource", "name":"Test", "slug":"project", "ownerAccount":["name":"studio"], "builds":[["id":"build", "status":"FINISHED", "platform":"IOS"]]]]]]
            case .vercel:
                if path.hasSuffix("/deployments") { value = ["deployments":[["uid":"deployment", "state":"READY", "url":"example.com"]]] }
                else if path.hasSuffix("/user") { value = ["user":["username":"studio"]] }
                else { value = ["id":"resource", "name":"Test", "accountId":"personal", "env":[["value":"DO_NOT_RETAIN"]]] }
            case .cloudflare:
                if path.hasSuffix("/deployments") { value = ["success":true, "result":["deployments":[["id":"deployment"]]]] }
                else { value = ["success":true, "result":["compatibility_date":"2026-10-01", "bindings":[["name":"SECRET", "text":"DO_NOT_RETAIN"]]]] }
            case .searchConsole:
                if path.hasSuffix("/query") { value = ["rows":[["clicks":4, "impressions":20, "ctr":0.2]]] }
                else { value = ["siteUrl":"resource", "permissionLevel":"siteOwner"] }
            case .analytics:
                if path.hasSuffix(":runReport") { value = ["rows":[["metricValues":[["value":"7"], ["value":"9"], ["value":"12"]]]]] }
                else { value = ["name":"properties/123", "displayName":"Test"] }
            case .appStore:
                if path.hasSuffix("/appStoreVersions") { value = ["data":[["id":"version", "attributes":["versionString":"1.0", "appStoreState":"READY_FOR_SALE"]]]] }
                else { value = ["data":["id":"resource", "attributes":["name":"Test", "bundleId":"com.example.test"]]] }
            case .googlePlay: value = ["reviews":[["authorName":"DO_NOT_RETAIN", "comments":[]]]]
            case .custom: throw WorkspaceError.unsupported
            }
        }
        return ProviderResponse(status: 200, data: try JSONSerialization.data(withJSONObject: value))
    }
}
@Test(arguments: ServiceProvider.allCases.filter(\.supportsAPI))
func adaptersProjectRealFieldsWithoutCredentialOrReviewPayloads(_ provider: ServiceProvider) async throws {
    let resource = provider == .analytics ? "123" : provider == .googlePlay ? "com.example.app" : "resource"
    let account = ProviderAccount(provider: provider, name: "Test", scope: "studio")
    let connection = ServiceConnection(provider: provider, name: "Test", resourceID: resource, accountID: account.id)
    let credential: Data
    if [.analytics, .searchConsole, .googlePlay].contains(provider) {
        credential = Data(#"{"client_id":"synthetic-client","client_secret":"synthetic-secret","refresh_token":"synthetic-refresh"}"#.utf8)
    } else if provider == .appStore {
        credential = try JSONEncoder().encode(["issuer_id":"test", "key_id":"test", "private_key":P256.Signing.PrivateKey().pemRepresentation])
    } else { credential = Data("synthetic-token".utf8) }
    let snapshot = try await ProviderService(transport: AdapterTransport(provider)).fetch(connection, account: account, credential: credential)
    #expect(snapshot.resourceID == resource)
    #expect(!snapshot.name.isEmpty)
    let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    #expect(!encoded.contains("DO_NOT_RETAIN"))
    #expect(!encoded.contains("synthetic-secret"))
    if provider == .expo { #expect(snapshot.dashboardURL == "https://expo.dev/accounts/studio/projects/project") }
    if provider == .vercel { #expect(snapshot.dashboardURL == "https://vercel.com/studio/Test") }
}
