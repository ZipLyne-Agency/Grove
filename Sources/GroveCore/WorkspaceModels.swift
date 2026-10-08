import Foundation

public enum WorkspaceDestination: String, Codable, CaseIterable, Sendable {
    case library = "Repositories", projects = "Projects", connections = "Connections", settings = "Settings"
}
public enum ProjectTab: String, Codable, CaseIterable, Sendable {
    case overview = "Overview", services = "Services", activity = "Activity", settings = "Settings"
}

public struct GroveProject: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var notes: String
    public var repositoryIDs: Set<Int>
    public var pinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public init(id: UUID = UUID(), name: String, notes: String = "", repositoryIDs: Set<Int> = [], pinned: Bool = false) {
        self.id = id; self.name = name; self.notes = notes; self.repositoryIDs = repositoryIDs
        self.pinned = pinned; createdAt = Date(); updatedAt = createdAt
    }
}

public enum ServiceProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case expo, oneSignal, searchConsole, cloudflare, vercel, revenueCat, sentry, analytics, appStore, googlePlay, custom
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .expo: "Expo"
        case .oneSignal: "OneSignal"
        case .searchConsole: "Search Console"
        case .cloudflare: "Cloudflare"
        case .vercel: "Vercel"
        case .revenueCat: "RevenueCat"
        case .sentry: "Sentry"
        case .analytics: "Google Analytics"
        case .appStore: "App Store Connect"
        case .googlePlay: "Google Play"
        case .custom: "Custom Link"
        }
    }
    public var symbol: String {
        switch self {
        case .expo: "triangle"
        case .oneSignal: "bell.badge"
        case .searchConsole: "magnifyingglass.circle"
        case .cloudflare: "cloud"
        case .vercel: "triangle.fill"
        case .revenueCat: "chart.bar"
        case .sentry: "waveform.path.ecg"
        case .analytics: "chart.xyaxis.line"
        case .appStore: "app.badge"
        case .googlePlay: "play.rectangle"
        case .custom: "link"
        }
    }
    public var supportsAPI: Bool { self != .custom }
    public var supportsRename: Bool { [.oneSignal, .sentry, .vercel].contains(self) }
    public var credentialHelp: String {
        switch self {
        case .oneSignal: "Organization API Key. Grove reads app metadata; it never sends notifications."
        case .expo: "Expo access token with access to this EAS project."
        case .searchConsole, .analytics: "Google OAuth credentials JSON (client_id, client_secret, refresh_token), or a service account JSON. Choose an account with access to the property."
        case .cloudflare: "Scoped API token with account Workers/Pages read access. Set the account ID below."
        case .vercel: "Vercel access token. Set the team ID if this project belongs to a team."
        case .revenueCat: "RevenueCat V2 secret API key with project read access."
        case .sentry: "Sentry token with project read access. Set the organization slug below."
        case .appStore: "App Store Connect API credentials JSON: issuer_id, key_id, private_key (.p8 PEM)."
        case .googlePlay: "Google OAuth credentials JSON or a service account JSON with Play Console access."
        case .custom: "Custom links do not require credentials."
        }
    }
    public var scopeLabel: String {
        switch self {
        case .cloudflare: "Account ID"
        case .vercel: "Team ID (Optional)"
        case .sentry: "Organization Slug"
        case .expo: "Account Name (Optional)"
        default: "Account Scope (Optional)"
        }
    }
    public var resourceLabel: String {
        switch self {
        case .expo, .revenueCat, .vercel: "Project ID"
        case .oneSignal, .appStore: "App ID"
        case .searchConsole: "Property URL or sc-domain:example.com"
        case .cloudflare: "Worker Name or pages:Project Name"
        case .sentry: "Project Slug"
        case .analytics: "Property ID"
        case .googlePlay: "Android Package Name"
        case .custom: "Reference (Optional)"
        }
    }
}

public struct ProviderAccount: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var provider: ServiceProvider
    public var name: String
    public var scope: String
    /// Optional Google Workspace identity for domain-wide delegation. Never inferred from a service account.
    public var googleSubject: String?
    public init(id: UUID = UUID(), provider: ServiceProvider, name: String, scope: String = "", googleSubject: String? = nil) {
        self.id = id; self.provider = provider; self.name = name; self.scope = scope; self.googleSubject = googleSubject
    }
}

public enum ConnectionOrigin: String, Codable, Sendable { case manual, repository, provider }
public enum ConnectionStatus: String, Sendable {
    case savedLink = "Saved Link", suggested = "Suggested", unverified = "Not Checked", verified = "Verified"
    case needsAuthorization = "Needs Authorization", failed = "Couldn’t Sync", stale = "Out of Date"
}
public struct ServiceMetric: Identifiable, Codable, Equatable, Sendable {
    public var id: String { label }
    public let label: String
    public let value: String
    public init(_ label: String, _ value: String) { self.label = label; self.value = value }
}
public struct ServiceActivity: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let date: Date?
    public let url: String?
    public init(id: String, title: String, detail: String = "", date: Date? = nil, url: String? = nil) {
        self.id = id; self.title = title; self.detail = detail; self.date = date; self.url = url
    }
}
public struct ServiceSnapshot: Codable, Equatable, Sendable {
    public let resourceID: String
    public let name: String
    public let checkedAt: Date
    public var metrics: [ServiceMetric]
    public var activity: [ServiceActivity]
    public var details: [ServiceMetric]
    public var notice: String?
    public var dashboardURL: String?
    public init(resourceID: String, name: String, metrics: [ServiceMetric] = [], activity: [ServiceActivity] = [], details: [ServiceMetric] = [], notice: String? = nil, dashboardURL: String? = nil, checkedAt: Date = Date()) {
        self.resourceID = resourceID; self.name = name; self.metrics = metrics; self.activity = activity
        self.details = details; self.notice = notice; self.dashboardURL = dashboardURL; self.checkedAt = checkedAt
    }
}
public struct ServiceConnection: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var provider: ServiceProvider
    public var name: String
    public var resourceID: String
    public var dashboardURL: String
    public var dashboardOverride: Bool?
    public var accountID: UUID?
    public var projectIDs: Set<UUID>
    public var repositoryIDs: Set<Int>
    public var environment: String
    public var notes: String
    public var pinned: Bool
    public var origin: ConnectionOrigin
    public var source: String?
    public var snapshot: ServiceSnapshot?
    public var lastError: String?
    public var authorizationFailed: Bool
    public var lastAttemptAt: Date?
    public init(id: UUID = UUID(), provider: ServiceProvider, name: String, resourceID: String = "", dashboardURL: String = "", accountID: UUID? = nil, projectIDs: Set<UUID> = [], repositoryIDs: Set<Int> = [], environment: String = "", notes: String = "", pinned: Bool = false, origin: ConnectionOrigin = .manual, source: String? = nil) {
        self.id = id; self.provider = provider; self.name = name; self.resourceID = resourceID; self.dashboardURL = dashboardURL
        self.accountID = accountID; self.projectIDs = projectIDs; self.repositoryIDs = repositoryIDs
        self.environment = environment; self.notes = notes; self.pinned = pinned; self.origin = origin; self.source = source
        authorizationFailed = false
    }
    public func status(now: Date = Date()) -> ConnectionStatus {
        if authorizationFailed { return .needsAuthorization }
        if lastError != nil { return .failed }
        if let snapshot { return now.timeIntervalSince(snapshot.checkedAt) > 900 ? .stale : .verified }
        if origin == .repository { return .suggested }
        if accountID == nil || provider == .custom { return .savedLink }
        return .unverified
    }
}

public struct WorkspaceArchive: Codable, Equatable, Sendable {
    public var version = 1
    public var projects: [GroveProject] = []
    public var connections: [ServiceConnection] = []
    public var accounts: [ProviderAccount] = []
    public init() {}
    public func projects(for repositoryID: Int) -> [GroveProject] { projects.filter { $0.repositoryIDs.contains(repositoryID) } }
    public func connections(for repositoryID: Int) -> [ServiceConnection] {
        let memberships = Set(projects(for: repositoryID).map(\.id))
        return connections.filter { $0.repositoryIDs.contains(repositoryID) || !$0.projectIDs.isDisjoint(with: memberships) }
    }
    public mutating func removeProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        for index in connections.indices { connections[index].projectIDs.remove(id) }
    }
}

public enum WorkspaceError: Error, LocalizedError, Equatable {
    case invalidInput(String), missingCredential, authorization, forbidden, notFound, rateLimited
    case invalidResponse, unsupported, network, keychain, archiveVersion, corruptArchive, staleReview, outcomeUnknown, workspaceBusy
    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message): message
        case .missingCredential: "Add credentials to this connection’s account to verify it."
        case .authorization: "The account needs authorization. Update its credentials and try again."
        case .forbidden: "This account does not have permission to access the resource."
        case .notFound: "The resource could not be found. Check its ID and account."
        case .rateLimited: "The service is limiting requests. Grove will try again later."
        case .invalidResponse: "The service returned an unexpected response."
        case .unsupported: "Manage this setting in the service dashboard."
        case .network: "The service could not be reached. Your saved information is still available."
        case .keychain: "Grove could not access macOS Keychain. Check your Keychain permissions."
        case .workspaceBusy: "Another Grove process is using this workspace. Quit it before importing setup or opening another instance."
        case .archiveVersion: "This workspace was saved by a newer version of Grove. Update Grove to open it."
        case .corruptArchive: "The saved workspace could not be opened. It has been preserved for recovery."
        case .staleReview: "This connection changed after the review opened. Review the change again."
        case .outcomeUnknown: "The service may have accepted the change. Sync to verify before trying again."
        }
    }
}
