import Foundation

extension ProviderService {
    func oneSignal(_ connection: ServiceConnection, _ account: ProviderAccount, _ credential: Data) async throws -> ServiceSnapshot {
        let json = try await request("api.onesignal.com", "/apps/\(ServiceCatalog.component(connection.resourceID))", account: account, credential: credential)
        guard try json.requiredString("id") == connection.resourceID else { throw WorkspaceError.invalidResponse }
        var metrics: [ServiceMetric] = [], details: [ServiceMetric] = []
        if let value = json["players"].text { metrics.append(ServiceMetric("Subscriptions", value)) }
        if let value = json["messageable_players"].text { metrics.append(ServiceMetric("Subscribed", value)) }
        for (field, label) in [("apns_bundle_id", "iOS Bundle"), ("apns_env", "APNs Environment"), ("chrome_web_origin", "Web Origin")] {
            if let value = json[field].string, !value.isEmpty { details.append(ServiceMetric(label, String(value.prefix(200)))) }
        }
        return ServiceSnapshot(resourceID: connection.resourceID, name: try json.requiredString("name"), metrics: metrics, details: details)
    }
    func revenueCat(_ connection: ServiceConnection, _ account: ProviderAccount, _ credential: Data) async throws -> ServiceSnapshot {
        let path = "/v2/projects/\(ServiceCatalog.component(connection.resourceID))"
        let apps = try await request("api.revenuecat.com", path + "/apps", account: account, credential: credential, query: [URLQueryItem(name: "limit", value: "100")])
        guard case .array(let items) = apps["items"] else { throw WorkspaceError.invalidResponse }
        var snapshot = ServiceSnapshot(resourceID: connection.resourceID, name: connection.name)
        snapshot.metrics.append(ServiceMetric("Apps", "\(items.count)\(apps["next_page"].string == nil ? "" : "+")"))
        snapshot.details = items.prefix(10).compactMap { app in
            guard let name = app["name"].string, let type = app["type"].string else { return nil }
            return ServiceMetric(name, type)
        }
        do {
            let projects = try await request("api.revenuecat.com", "/v2/projects", account: account, credential: credential, query: [URLQueryItem(name: "limit", value: "100")])
            if let project = projects["items"].array.first(where: { $0["id"].string == connection.resourceID }), let name = project["name"].string {
                snapshot = ServiceSnapshot(resourceID: connection.resourceID, name: name, metrics: snapshot.metrics, details: snapshot.details)
            }
        } catch { snapshot.notice = "App access verified. The display name is your saved connection label." }
        do {
            let overview = try await request("api.revenuecat.com", path + "/metrics/overview", account: account, credential: credential)
            let allowed: Set<String> = ["active_trials", "active_subscriptions", "mrr", "revenue", "new_customers", "active_users"]
            for metric in overview["metrics"].array where allowed.contains(metric["id"].string ?? "") {
                guard let label = metric["name"].string, let value = metric["value"].text else { continue }
                let unit = metric["unit"].string ?? ""
                let suffix = unit == "$" ? " \(overview["currency"].string ?? "Currency Unspecified")" : unit == "%" ? "%" : ""
                let period = metric["period"].string.map { $0 == "P0D" ? "" : " · \($0)" } ?? ""
                snapshot.metrics.append(ServiceMetric(String(label.prefix(80)) + period, value + suffix))
            }
        } catch { snapshot.notice = [snapshot.notice, "Revenue metrics are unavailable for this account."].compactMap { $0 }.joined(separator: " ") }
        return snapshot
    }
    func sentry(_ connection: ServiceConnection, _ account: ProviderAccount, _ credential: Data) async throws -> ServiceSnapshot {
        guard !account.scope.isEmpty else { throw WorkspaceError.invalidInput("Set the Sentry organization slug on this account.") }
        let path = "/api/0/projects/\(ServiceCatalog.component(account.scope))/\(ServiceCatalog.component(connection.resourceID))/"
        let json = try await request("sentry.io", path, account: account, credential: credential)
        guard try json.requiredString("slug") == connection.resourceID else { throw WorkspaceError.invalidResponse }
        var details: [ServiceMetric] = []
        for (key, label) in [("platform", "Platform"), ("status", "Project Status")] {
            if let value = json[key].text { details.append(ServiceMetric(label, value)) }
        }
        var activity: [ServiceActivity] = []
        if let version = json["latestRelease"]["version"].string {
            activity.append(ServiceActivity(id: "release-" + version, title: "Latest Release", detail: String(version.prefix(150)), date: json["latestRelease"]["dateCreated"].date))
        }
        return ServiceSnapshot(resourceID: connection.resourceID, name: try json.requiredString("name"), activity: activity, details: details,
                               notice: "Project metadata verified. Error events and personal data are not imported.")
    }
    func expo(_ connection: ServiceConnection, _ account: ProviderAccount, _ credential: Data) async throws -> ServiceSnapshot {
        struct Query: Encodable { let query: String; let variables: [String: String] }
        let query = "query GroveProject($appId: String!) { app { byId(appId: $appId) { id name slug fullName ownerAccount { name } builds(offset: 0, limit: 5) { id status platform createdAt completedAt } } } }"
        let body = try JSONEncoder().encode(Query(query: query, variables: ["appId": connection.resourceID]))
        let result = try await request("api.expo.dev", "/graphql", account: account, credential: credential, method: "POST", body: body)
        guard result["errors"].array.isEmpty else { throw WorkspaceError.forbidden }
        let json = result["data"]["app"]["byId"]
        guard try json.requiredString("id") == connection.resourceID else { throw WorkspaceError.invalidResponse }
        let builds = json["builds"].array
        let activity = builds.compactMap { build -> ServiceActivity? in
            guard let id = build["id"].string, let status = build["status"].string, let platform = build["platform"].string else { return nil }
            let fullName = json["fullName"].string ?? ""
            let dashboard = fullName.hasPrefix("@") ? "https://expo.dev/accounts/\(ServiceCatalog.component(json["ownerAccount"]["name"].string ?? ""))/projects/\(ServiceCatalog.component(json["slug"].string ?? ""))/builds/\(ServiceCatalog.component(id))" : nil
            return ServiceActivity(id: id, title: "\(platform.uppercased()) Build", detail: status.replacingOccurrences(of: "_", with: " ").capitalized, date: build["createdAt"].date, url: dashboard)
        }
        var details: [ServiceMetric] = []
        if let owner = json["ownerAccount"]["name"].string { details.append(ServiceMetric("Account", owner)) }
        if let slug = json["slug"].string { details.append(ServiceMetric("Project Slug", slug)) }
        let owner = json["ownerAccount"]["name"].string, slug = json["slug"].string
        let dashboard = owner.flatMap { owner in slug.map { "https://expo.dev/accounts/\(ServiceCatalog.component(owner))/projects/\(ServiceCatalog.component($0))" } }
        return ServiceSnapshot(resourceID: connection.resourceID, name: json["name"].string ?? connection.name, activity: activity, details: details, dashboardURL: dashboard)
    }
}
