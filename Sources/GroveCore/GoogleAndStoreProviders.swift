import Foundation

extension ProviderService {
    func searchConsole(_ connection: ServiceConnection, _ account: ProviderAccount, _ credential: Data) async throws -> ServiceSnapshot {
        let resource = ServiceCatalog.component(connection.resourceID)
        let json = try await request("www.googleapis.com", "/webmasters/v3/sites/\(resource)", account: account, credential: credential)
        guard try json.requiredString("siteUrl") == connection.resourceID else { throw WorkspaceError.invalidResponse }
        var snapshot = ServiceSnapshot(resourceID: connection.resourceID, name: connection.resourceID,
                                       details: [ServiceMetric("Access", json["permissionLevel"].string ?? "Unknown")])
        struct Query: Encodable { let startDate: String; let endDate: String; let rowLimit = 1 }
        let range = Self.reportDates()
        do {
            let body = try JSONEncoder().encode(Query(startDate: range.start, endDate: range.end))
            let report = try await request("www.googleapis.com", "/webmasters/v3/sites/\(resource)/searchAnalytics/query", account: account, credential: credential, method: "POST", body: body)
            if let row = report["rows"].array.first {
                for (field, label) in [("clicks", "Clicks · 28 Days"), ("impressions", "Impressions · 28 Days"), ("position", "Average Position")] {
                    if let value = row[field].text { snapshot.metrics.append(ServiceMetric(label, value)) }
                }
                if let ctr = row["ctr"].number { snapshot.metrics.append(ServiceMetric("Click-Through Rate", ctr.formatted(.percent.precision(.fractionLength(1))))) }
            } else { snapshot.notice = "No search performance data was returned for the last 28 days." }
            snapshot.details.append(ServiceMetric("Report Period", "\(range.start) – \(range.end)"))
        } catch { snapshot.notice = "Property access verified. Search performance is unavailable for this account." }
        return snapshot
    }
    func analytics(_ connection: ServiceConnection, _ account: ProviderAccount, _ credential: Data) async throws -> ServiceSnapshot {
        guard connection.resourceID.allSatisfy(\.isNumber) else { throw WorkspaceError.invalidInput("Enter the numeric Google Analytics property ID.") }
        let id = ServiceCatalog.component(connection.resourceID)
        let json = try await request("analyticsadmin.googleapis.com", "/v1beta/properties/\(id)", account: account, credential: credential)
        guard try json.requiredString("name") == "properties/" + connection.resourceID else { throw WorkspaceError.invalidResponse }
        var snapshot = ServiceSnapshot(resourceID: connection.resourceID, name: try json.requiredString("displayName"))
        struct Metric: Encodable { let name: String }
        struct Range: Encodable { let startDate = "28daysAgo"; let endDate = "yesterday" }
        struct Report: Encodable { let dateRanges = [Range()]; let metrics = [Metric(name: "activeUsers"), Metric(name: "sessions"), Metric(name: "eventCount")] }
        do {
            let body = try JSONEncoder().encode(Report())
            let report = try await request("analyticsdata.googleapis.com", "/v1beta/properties/\(id):runReport", account: account, credential: credential, method: "POST", body: body)
            if let row = report["rows"].array.first {
                let values = row["metricValues"].array
                for (index, label) in ["Active Users · 28 Days", "Sessions · 28 Days", "Events · 28 Days"].enumerated() {
                    if index < values.count, let value = values[index]["value"].string { snapshot.metrics.append(ServiceMetric(label, value)) }
                }
            } else { snapshot.notice = "No analytics data was returned for the last 28 days." }
        } catch { snapshot.notice = "Property verified. Analytics reporting is unavailable for this account." }
        return snapshot
    }
    func appStore(_ connection: ServiceConnection, _ account: ProviderAccount, _ credential: Data) async throws -> ServiceSnapshot {
        let json = try await request("api.appstoreconnect.apple.com", "/v1/apps/\(ServiceCatalog.component(connection.resourceID))", account: account, credential: credential)
        let app = json["data"]
        guard try app.requiredString("id") == connection.resourceID else { throw WorkspaceError.invalidResponse }
        let attrs = app["attributes"]
        var details: [ServiceMetric] = []
        for (key, label) in [("bundleId", "Bundle ID"), ("primaryLocale", "Primary Locale")] {
            if let value = attrs[key].string { details.append(ServiceMetric(label, value)) }
        }
        var snapshot = ServiceSnapshot(resourceID: connection.resourceID, name: try attrs.requiredString("name"), details: details)
        do {
            let json = try await request("api.appstoreconnect.apple.com", "/v1/apps/\(ServiceCatalog.component(connection.resourceID))/appStoreVersions", account: account, credential: credential, query: [URLQueryItem(name: "limit", value: "5")])
            snapshot.activity = json["data"].array.compactMap { version in
                guard let id = version["id"].string, let number = version["attributes"]["versionString"].string else { return nil }
                let attrs = version["attributes"]
                return ServiceActivity(id: id, title: "Version \(number)", detail: (attrs["appStoreState"].string ?? "Unknown").replacingOccurrences(of: "_", with: " ").capitalized,
                                       date: attrs["createdDate"].date, url: ServiceCatalog.dashboard(provider: .appStore, resourceID: connection.resourceID))
            }
        } catch { snapshot.notice = "App verified. Release details are unavailable for this account." }
        return snapshot
    }
    func googlePlay(_ connection: ServiceConnection, _ account: ProviderAccount, _ credential: Data) async throws -> ServiceSnapshot {
        guard connection.resourceID.contains("."), connection.resourceID.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._")).contains($0) }) else {
            throw WorkspaceError.invalidInput("Enter the app’s Android package name.")
        }
        // Verify access with a read endpoint. Do not create an edit session or retain review text/user information.
        _ = try await request("androidpublisher.googleapis.com", "/androidpublisher/v3/applications/\(ServiceCatalog.component(connection.resourceID))/reviews", account: account, credential: credential, query: [URLQueryItem(name: "maxResults", value: "1")])
        return ServiceSnapshot(resourceID: connection.resourceID, name: connection.name, details: [ServiceMetric("Package", connection.resourceID)],
                               notice: "Package access verified. Release management opens in Play Console; review text is not imported.")
    }
    private static func reportDates() -> (start: String, end: String) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let format = DateFormatter(); format.calendar = calendar; format.timeZone = calendar.timeZone; format.dateFormat = "yyyy-MM-dd"
        let end = calendar.date(byAdding: .day, value: -1, to: Date())!
        let start = calendar.date(byAdding: .day, value: -27, to: end)!
        return (format.string(from: start), format.string(from: end))
    }
}
