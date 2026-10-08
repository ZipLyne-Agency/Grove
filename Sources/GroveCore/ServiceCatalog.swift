import Foundation

public enum ServiceCatalog {
    public static func component(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? ""
    }
    public static func dashboard(provider: ServiceProvider, resourceID: String, scope: String = "") -> String {
        let id = component(resourceID), account = component(scope)
        switch provider {
        case .oneSignal: return "https://dashboard.onesignal.com/apps/\(id)"
        case .expo: return scope.isEmpty ? "https://expo.dev/projects/\(id)" : "https://expo.dev/accounts/\(account)/projects/\(id)"
        case .searchConsole: return "https://search.google.com/search-console?resource_id=\(id)"
        case .cloudflare:
            if resourceID.hasPrefix("pages:") {
                return "https://dash.cloudflare.com/\(account)/pages/view/\(component(String(resourceID.dropFirst(6))))"
            }
            return "https://dash.cloudflare.com/\(account)/workers/services/view/\(id)/production"
        case .vercel: return scope.isEmpty ? "https://vercel.com/dashboard" : "https://vercel.com/\(account)/\(id)"
        case .revenueCat: return "https://app.revenuecat.com/projects/\(id)"
        case .sentry: return "https://\(scope.isEmpty ? "sentry" : scope).sentry.io/settings/projects/\(id)/"
        case .analytics: return "https://analytics.google.com/analytics/web/#/p\(id)/reports/intelligenthome"
        case .appStore: return "https://appstoreconnect.apple.com/apps/\(id)/distribution"
        case .googlePlay: return "https://play.google.com/console/"
        case .custom: return ""
        }
    }
    public static func settings(_ connection: ServiceConnection, account: ProviderAccount?) -> String {
        let scope = account?.scope ?? "", id = component(connection.resourceID)
        switch connection.provider {
        case .oneSignal: return "https://dashboard.onesignal.com/apps/\(id)/settings"
        case .expo: return dashboard(provider: .expo, resourceID: connection.resourceID, scope: scope) + "/settings"
        case .sentry: return dashboard(provider: .sentry, resourceID: connection.resourceID, scope: scope)
        default: return connection.dashboardURL
        }
    }
    public static func safeURL(_ text: String) -> URL? {
        guard text.count <= 2048, let components = URLComponents(string: text),
              components.scheme?.lowercased() == "https", components.user == nil, components.password == nil,
              let host = components.host?.lowercased(), !host.isEmpty,
              !["localhost", "0.0.0.0", "127.0.0.1", "::1"].contains(host),
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
              !(components.fragment?.lowercased().contains("token=") ?? false),
              !(components.fragment?.lowercased().contains("secret=") ?? false),
              !(components.queryItems ?? []).contains(where: { item in
                  ["token", "access_token", "api_key", "key", "secret", "password", "authorization"].contains(item.name.lowercased())
              }) else { return nil }
        return components.url
    }
    public static func validate(_ connection: ServiceConnection, accounts: [ProviderAccount]) throws {
        guard !connection.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, connection.name.count <= 128,
              connection.notes.count <= 4000, connection.environment.count <= 40, connection.resourceID.count <= 512 else {
            throw WorkspaceError.invalidInput("Use a name up to 128 characters and a short resource ID and environment label.")
        }
        if !connection.dashboardURL.isEmpty, safeURL(connection.dashboardURL) == nil {
            throw WorkspaceError.invalidInput("Enter an HTTPS dashboard link without credentials or access tokens.")
        }
        if let accountID = connection.accountID {
            guard let account = accounts.first(where: { $0.id == accountID }), account.provider == connection.provider else {
                throw WorkspaceError.invalidInput("Choose an account for the same service.")
            }
            guard !connection.resourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorkspaceError.invalidInput("Enter the resource ID to verify this connection.")
            }
        }
        if connection.provider == .custom && safeURL(connection.dashboardURL) == nil {
            throw WorkspaceError.invalidInput("Enter an HTTPS link for this connection.")
        }
    }
    public static func validate(_ account: ProviderAccount) throws {
        if account.provider == .sentry, !account.scope.isEmpty,
           account.scope.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) == nil {
            throw WorkspaceError.invalidInput("Enter the Sentry organization slug using letters, numbers, hyphens, or underscores.")
        }
        guard !account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, account.name.count <= 100,
              account.scope.count <= 128,
              account.scope.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ .@")).contains($0) }) else {
            throw WorkspaceError.invalidInput("Enter an account name and a valid account ID or organization slug.")
        }
        if let subject = account.googleSubject, !subject.isEmpty,
           !subject.contains("@") || subject.count > 254 || subject.contains(where: { $0.isWhitespace }) {
            throw WorkspaceError.invalidInput("Enter a valid delegated Google account email.")
        }
    }
}

/// Bounded JSON values are decoded at the HTTP boundary, then projected into explicit, non-secret snapshots.
public enum ServiceJSON: Decodable, Sendable, Equatable {
    case object([String: ServiceJSON]), array([ServiceJSON]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode(Double.self) { self = .number(v) }
        else if let v = try? container.decode([String: ServiceJSON].self) { self = .object(v) }
        else { self = .array(try container.decode([ServiceJSON].self)) }
    }
    public subscript(_ key: String) -> ServiceJSON { if case .object(let o) = self { return o[key] ?? .null }; return .null }
    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var number: Double? { if case .number(let n) = self { return n }; return nil }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var array: [ServiceJSON] { if case .array(let a) = self { return a }; return [] }
    public var text: String? {
        switch self { case .string(let s): s; case .number(let n): n.formatted(.number.precision(.fractionLength(0...2))); case .bool(let b): b ? "Yes" : "No"; default: nil }
    }
    public func requiredString(_ key: String) throws -> String {
        guard let string = self[key].string, !string.isEmpty, string.count <= 1024 else { throw WorkspaceError.invalidResponse }
        return string
    }
    public var date: Date? {
        if let number { return Date(timeIntervalSince1970: number > 1e11 ? number / 1000 : number) }
        guard let string else { return nil }
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
