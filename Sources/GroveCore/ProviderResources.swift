import Foundation

public struct ProviderResource: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let dashboardURL: String
    public init(id: String, name: String, dashboardURL: String) { self.id = id; self.name = name; self.dashboardURL = dashboardURL }
}
extension ProviderService {
    /// Lists a bounded page for an explicit resource picker. Individual IDs remain usable for larger accounts.
    public func resources(account: ProviderAccount, credential: Data) async throws -> [ProviderResource] {
        try ServiceCatalog.validate(account)
        let json: ServiceJSON
        let items: [ServiceJSON]
        let idKey: String, nameKey: String
        switch account.provider {
        case .oneSignal:
            json = try await request("api.onesignal.com", "/apps", account: account, credential: credential)
            guard case .array = json else { throw WorkspaceError.invalidResponse }
            items = json.array; idKey = "id"; nameKey = "name"
        case .vercel:
            var query = [URLQueryItem(name: "limit", value: "100")]
            if !account.scope.isEmpty { query.append(URLQueryItem(name: "teamId", value: account.scope)) }
            json = try await request("api.vercel.com", "/v10/projects", account: account, credential: credential, query: query)
            items = json["projects"].array; idKey = "id"; nameKey = "name"
        case .cloudflare:
            guard !account.scope.isEmpty else { throw WorkspaceError.invalidInput("Set the Cloudflare account ID first.") }
            json = try await request("api.cloudflare.com", "/client/v4/accounts/\(ServiceCatalog.component(account.scope))/workers/scripts", account: account, credential: credential)
            guard json["success"].bool == true else { throw WorkspaceError.invalidResponse }
            items = json["result"].array; idKey = "id"; nameKey = "id"
        case .revenueCat:
            json = try await request("api.revenuecat.com", "/v2/projects", account: account, credential: credential, query: [URLQueryItem(name: "limit", value: "100")])
            items = json["items"].array; idKey = "id"; nameKey = "name"
        case .sentry:
            guard !account.scope.isEmpty else { throw WorkspaceError.invalidInput("Set the Sentry organization slug first.") }
            json = try await request("sentry.io", "/api/0/organizations/\(ServiceCatalog.component(account.scope))/projects/", account: account, credential: credential)
            guard case .array = json else { throw WorkspaceError.invalidResponse }
            items = json.array; idKey = "slug"; nameKey = "name"
        case .searchConsole:
            json = try await request("www.googleapis.com", "/webmasters/v3/sites", account: account, credential: credential)
            items = json["siteEntry"].array; idKey = "siteUrl"; nameKey = "siteUrl"
        case .analytics:
            json = try await request("analyticsadmin.googleapis.com", "/v1beta/accountSummaries", account: account, credential: credential,
                                     query: [URLQueryItem(name: "pageSize", value: "200")])
            items = json["accountSummaries"].array.flatMap { $0["propertySummaries"].array }; idKey = "property"; nameKey = "displayName"
        case .appStore:
            json = try await request("api.appstoreconnect.apple.com", "/v1/apps", account: account, credential: credential,
                                     query: [URLQueryItem(name: "limit", value: "200")])
            return try json["data"].array.prefix(200).map {
                let id = try $0.requiredString("id"), name = try $0["attributes"].requiredString("name")
                return ProviderResource(id: id, name: name, dashboardURL: ServiceCatalog.dashboard(provider: .appStore, resourceID: id))
            }
        case .expo, .googlePlay, .custom: throw WorkspaceError.invalidInput("Enter the resource ID directly for this service.")
        }
        return try items.prefix(200).map {
            var id = try $0.requiredString(idKey)
            if account.provider == .analytics { id = id.replacingOccurrences(of: "properties/", with: "") }
            return ProviderResource(id: id, name: try $0.requiredString(nameKey), dashboardURL: ServiceCatalog.dashboard(provider: account.provider, resourceID: id, scope: account.scope))
        }
    }
}
