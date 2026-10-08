import Testing
import Foundation
import GroveCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["GROVE_PROVIDER_SMOKE"] == "1"))
func providerLiveReadSmoke() async throws {
    let env = ProcessInfo.processInfo.environment
    let configurations: [(ServiceProvider, String, String, String?)] = [
        (.oneSignal, "ONESIGNAL_ORG_API_KEY", "ONESIGNAL_APP_ID", nil),
        (.revenueCat, "REVENUECAT_V2_SECRET_KEY", "REVENUECAT_PROJECT_ID", nil),
        (.sentry, "SENTRY_AUTH_TOKEN", "SENTRY_PROJECT", "SENTRY_ORG")
    ]
    let service = ProviderService()
    for (provider, tokenName, idName, scopeName) in configurations {
        let token = try #require(env[tokenName], "Missing smoke credential")
        let resource = try #require(env[idName], "Missing smoke resource")
        let account = ProviderAccount(provider: provider, name: "Smoke Account", scope: scopeName.flatMap { env[$0] } ?? "")
        let connection = ServiceConnection(provider: provider, name: "Smoke Resource", resourceID: resource, accountID: account.id)
        let snapshot = try await service.fetch(connection, account: account, credential: Data(token.utf8))
        #expect(snapshot.resourceID == resource)
        #expect(!snapshot.name.isEmpty)
        print("Verified live read: \(provider.title)")
    }
}
