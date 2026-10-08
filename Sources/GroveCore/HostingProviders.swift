import Foundation

extension ProviderService {
    func vercel(_ connection: ServiceConnection, _ account: ProviderAccount, _ credential: Data) async throws -> ServiceSnapshot {
        let query = account.scope.isEmpty ? [] : [URLQueryItem(name: "teamId", value: account.scope)]
        let json = try await request("api.vercel.com", "/v9/projects/\(ServiceCatalog.component(connection.resourceID))", account: account, credential: credential, query: query)
        let id = try json.requiredString("id"), name = try json.requiredString("name")
        guard id == connection.resourceID || name == connection.resourceID else { throw WorkspaceError.invalidResponse }
        var snapshot = ServiceSnapshot(resourceID: id, name: name)
        do {
            let owner: ServiceJSON
            let slug: String?
            if let accountID = json["accountId"].string, accountID.hasPrefix("team_") {
                owner = try await request("api.vercel.com", "/v2/teams/\(ServiceCatalog.component(accountID))", account: account, credential: credential)
                slug = owner["slug"].string
            } else {
                owner = try await request("api.vercel.com", "/v2/user", account: account, credential: credential)
                slug = owner["user"]["username"].string
            }
            if let slug { snapshot.dashboardURL = "https://vercel.com/\(ServiceCatalog.component(slug))/\(ServiceCatalog.component(name))" }
        } catch { snapshot.notice = "Set an exact dashboard URL if this account's dashboard cannot be resolved." }
        if let framework = json["framework"].string { snapshot.details.append(ServiceMetric("Framework", framework)) }
        do {
            let deployments = try await request("api.vercel.com", "/v6/deployments", account: account, credential: credential,
                                                query: query + [URLQueryItem(name: "projectId", value: id), URLQueryItem(name: "limit", value: "5")])
            snapshot.activity = deployments["deployments"].array.compactMap { deployment in
                guard let id = deployment["uid"].string, let state = deployment["state"].string else { return nil }
                let hostname = deployment["url"].string
                let url = hostname.flatMap { ServiceCatalog.safeURL("https://" + $0)?.absoluteString }
                return ServiceActivity(id: id, title: deployment["target"].string == "production" ? "Production Deployment" : "Preview Deployment",
                                       detail: state.capitalized, date: deployment["created"].date, url: url)
            }
        } catch { snapshot.notice = "Project verified. Recent deployments are unavailable for this account." }
        return snapshot
    }
    func cloudflare(_ connection: ServiceConnection, _ account: ProviderAccount, _ credential: Data) async throws -> ServiceSnapshot {
        guard !account.scope.isEmpty else { throw WorkspaceError.invalidInput("Set the Cloudflare account ID on this account.") }
        let root = "/client/v4/accounts/\(ServiceCatalog.component(account.scope))"
        if connection.resourceID.hasPrefix("pages:") {
            let project = String(connection.resourceID.dropFirst(6)), path = root + "/pages/projects/\(ServiceCatalog.component(project))"
            let json = try await request("api.cloudflare.com", path, account: account, credential: credential)
            guard json["success"].bool == true else { throw WorkspaceError.invalidResponse }
            let result = json["result"]
            guard try result.requiredString("name") == project else { throw WorkspaceError.invalidResponse }
            var details: [ServiceMetric] = []
            if let branch = result["production_branch"].string { details.append(ServiceMetric("Production Branch", branch)) }
            if let domain = result["subdomain"].string { details.append(ServiceMetric("Domain", domain)) }
            var snapshot = ServiceSnapshot(resourceID: connection.resourceID, name: project, details: details)
            do {
                let response = try await request("api.cloudflare.com", path + "/deployments", account: account, credential: credential,
                                                 query: [URLQueryItem(name: "per_page", value: "5")])
                guard response["success"].bool == true else { throw WorkspaceError.invalidResponse }
                snapshot.activity = response["result"].array.compactMap { item in
                    guard let id = item["id"].string else { return nil }
                    return ServiceActivity(id: id, title: "\((item["environment"].string ?? "Preview").capitalized) Deployment",
                                           detail: (item["latest_stage"]["status"].string ?? "Unknown").capitalized,
                                           date: item["created_on"].date, url: item["url"].string.flatMap { ServiceCatalog.safeURL($0)?.absoluteString })
                }
            } catch { snapshot.notice = "Pages project verified. Recent deployments are unavailable." }
            return snapshot
        }
        let script = ServiceCatalog.component(connection.resourceID)
        let response = try await request("api.cloudflare.com", root + "/workers/scripts/\(script)/settings", account: account, credential: credential)
        guard response["success"].bool == true else { throw WorkspaceError.invalidResponse }
        let settings = response["result"]
        var details: [ServiceMetric] = []
        if let date = settings["compatibility_date"].string { details.append(ServiceMetric("Compatibility Date", date)) }
        if case .array(let bindings) = settings["bindings"] { details.append(ServiceMetric("Bindings", bindings.count.formatted())) }
        var snapshot = ServiceSnapshot(resourceID: connection.resourceID, name: connection.resourceID, details: details)
        do {
            let response = try await request("api.cloudflare.com", root + "/workers/scripts/\(script)/deployments", account: account, credential: credential)
            guard response["success"].bool == true else { throw WorkspaceError.invalidResponse }
            snapshot.activity = response["result"]["deployments"].array.prefix(5).compactMap { item in
                guard let id = item["id"].string else { return nil }
                return ServiceActivity(id: id, title: "Worker Deployment", detail: String(id.prefix(8)), date: item["created_on"].date)
            }
        } catch { snapshot.notice = "Worker verified. Deployment history is unavailable for this account." }
        return snapshot
    }
}
