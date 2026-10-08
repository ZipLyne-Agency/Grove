import Foundation

public struct Repository: Codable, Identifiable, Hashable, Sendable {
    public struct Owner: Codable, Hashable, Sendable { public let login: String }
    public struct Permissions: Codable, Hashable, Sendable { public let admin: Bool }
    public let id: Int
    public let name: String
    public let full_name: String
    public let owner: Owner
    public let description: String?
    public let language: String?
    public let pushed_at: String?
    public let created_at: String?
    public let updated_at: String
    public let archived: Bool
    public let fork: Bool
    public let `private`: Bool
    public let stargazers_count: Int
    public let open_issues_count: Int
    public let default_branch: String
    public let permissions: Permissions?
    public let topics: [String]?
    public var safeIdentity: Bool { RepositoryAction.validComponent(owner.login) && RepositoryAction.validComponent(name) && full_name == "\(owner.login)/\(name)" }
    public var canAdminister: Bool { permissions?.admin == true }
    public var pushedDate: Date? { pushed_at.flatMap { ISO8601DateFormatter().date(from: $0) } }
    public var createdDate: Date? { created_at.flatMap { ISO8601DateFormatter().date(from: $0) } }
    public var updatedDate: Date? { ISO8601DateFormatter().date(from: updated_at) }
    public var webURL: URL? { URL(string: "https://github.com/\(full_name)") }
    public var hasDescription: Bool { !(description ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var searchText: String { "\(full_name) \(description ?? "") \(language ?? "") \((topics ?? []).joined(separator: " "))" }
}

public struct Account: Codable, Sendable, Equatable { public let login: String }
public struct Organization: Codable, Sendable, Equatable { public let login: String }
public struct Inventory: Codable, Sendable {
    public let account: Account
    public let organizations: [Organization]
    public let repositories: [Repository]
    public let fetchedAt: Date
    public let requiresRefresh: Bool?
    public init(account: Account, organizations: [Organization], repositories: [Repository], fetchedAt: Date = Date(), requiresRefresh: Bool = false) {
        self.account = account; self.organizations = organizations
        self.repositories = repositories; self.fetchedAt = fetchedAt; self.requiresRefresh = requiresRefresh
    }
}

public enum RepositoryAction: Equatable, Sendable {
    case rename(String), describe(String), transfer(String), archive(Bool), delete
    public var title: String {
        switch self {
        case .rename: "Rename repository"
        case .describe: "Update description"
        case .transfer: "Transfer repository"
        case .archive(let value): value ? "Archive repository" : "Unarchive repository"
        case .delete: "Delete repository"
        }
    }
    public var requiresTyping: Bool {
        switch self { case .delete, .transfer: true; default: false }
    }
    public func validate(for repo: Repository, destinations: [String]) throws {
        guard repo.safeIdentity else { throw GroveError.invalidResponse }
        guard repo.canAdminister else { throw GroveError.noAdministration }
        switch self {
        case .rename(let name):
            guard Self.validComponent(name), name != repo.name else { throw GroveError.invalidName }
        case .describe(let text):
            guard text.count <= 350, text != (repo.description ?? "") else { throw GroveError.invalidDescription }
        case .transfer(let owner):
            guard Self.validComponent(owner), owner.lowercased() != repo.owner.login.lowercased(),
                  destinations.contains(where: { $0.lowercased() == owner.lowercased() }) else { throw GroveError.invalidDestination }
        case .archive(let value):
            guard value != repo.archived else { throw GroveError.stalePreview }
        case .delete: break
        }
    }
    public static func validComponent(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 100 && value != "." && value != ".." &&
        value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.").contains($0) }
    }
}

public struct ActionPreview: Identifiable, Sendable {
    public let id: UUID
    public let repository: Repository
    public let action: RepositoryAction
    public let account: String
    public let createdAt: Date
    public var destination: String {
        switch action {
        case .rename(let name): "\(repository.owner.login)/\(name)"
        case .describe(let value): value.isEmpty ? "No description" : value
        case .transfer(let owner): "\(owner)/\(repository.name)"
        case .archive(let value): value ? "Archived and read-only" : "Active"
        case .delete: "Repository permanently removed from GitHub"
        }
    }
}

public enum MutationOutcome: Sendable { case verified(Repository?), transferRequested, acceptedUnverified }
public enum GroveError: Error, LocalizedError, Equatable {
    case missingCLI, loginRequired, commandFailed(Int32), timeout, invalidName, invalidDescription
    case invalidDestination, noAdministration, confirmationRequired, expiredPreview, stalePreview, accountChanged
    case destinationExists, unavailableAI, invalidResponse, transportFailure, outcomeUnknown
    public var errorDescription: String? {
        switch self {
        case .missingCLI: "GitHub CLI is required. Install it with brew install gh, then sign in with gh auth login."
        case .loginRequired: "GitHub could not authenticate. Check your GitHub CLI login in Terminal."
        case .commandFailed(let status):
            switch status {
            case 403: "GitHub refused this operation (403). Check account permissions, organization policy, and token scopes. Deletion requires delete_repo."
            case 404: "GitHub could not find this repository (404). Refresh to check its current owner and name."
            case 409: "GitHub reported a conflict (409). Refresh and review the repository's current state."
            case 422: "GitHub rejected the proposed values (422). Check the name, description, destination, and organization restrictions."
            default: "GitHub rejected the request (HTTP \(status)). Refresh and review the current repository state."
            }
        case .transportFailure: "GitHub could not be reached. Check your network connection and refresh. Your login has not been changed."
        case .outcomeUnknown: "The connection ended during the change. It may have been applied. Refresh to check GitHub before taking another action."
        case .timeout: "GitHub did not respond before the timeout. Refresh to check the current state before trying again."
        case .invalidName: "Enter a different repository name using letters, numbers, dots, underscores, or hyphens."
        case .invalidDescription: "Enter a changed description of at most 350 characters."
        case .invalidDestination: "Choose a different organization from your connected account."
        case .noAdministration: "This account does not have repository administrator permission."
        case .confirmationRequired: "Type the exact full repository name to confirm this action."
        case .expiredPreview: "This confirmation has expired or was already used. Review the action again."
        case .stalePreview: "The repository changed since this preview. Refresh and review the action again."
        case .accountChanged: "The GitHub CLI account changed. Refresh and review the action using the current account."
        case .destinationExists: "A repository with this name already exists at the destination."
        case .unavailableAI: "Apple Intelligence is unavailable on this Mac. Enable it in System Settings on a supported Mac."
        case .invalidResponse: "GitHub returned an unexpected response. Refresh and try again."
        }
    }
}
