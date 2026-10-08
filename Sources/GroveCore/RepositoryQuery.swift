import Foundation
public enum LibraryScope: String, CaseIterable, Sendable {
    case all = "All repositories", recent = "Recently pushed", missing = "Needs a description", archived = "Archived", forks = "Forks"
    public var symbol: String {
        switch self { case .all: "square.stack.3d.up"; case .recent: "clock"; case .missing: "text.badge.plus"; case .archived: "archivebox"; case .forks: "arrow.triangle.branch" }
    }
}
public enum RepositorySort: String, CaseIterable, Sendable {
    case createdNewest = "Created: newest first", createdOldest = "Created: oldest first"
    case pushed = "Pushed: newest first", pushedOldest = "Pushed: oldest first"
    case updatedNewest = "Updated: newest first", updatedOldest = "Updated: oldest first"
    case name = "Name: A to Z", nameDescending = "Name: Z to A"
    case stars = "Stars: most first", starsFewest = "Stars: fewest first"
    case issuesMost = "Issues & PRs: most first", issuesFewest = "Issues & PRs: fewest first"
}
public enum RepositoryQuery {
    public static func filter(_ repos: [Repository], scope: LibraryScope, owner: String?, search: String, sort: RepositorySort, now: Date = Date(), descriptions: [Int: String] = [:], integrationNames: [Int: String] = [:]) -> [Repository] {
        let cutoff = now.addingTimeInterval(-30 * 86400)
        let terms = search.split(whereSeparator: \.isWhitespace).map(String.init)
        let filtered = repos.filter { repo in
            if let owner, repo.owner.login != owner { return false }
            let searchable = repo.searchText + " " + (descriptions[repo.id] ?? "") + " " + (integrationNames[repo.id] ?? "")
            if !terms.allSatisfy({ searchable.localizedCaseInsensitiveContains($0) }) { return false }
            switch scope {
            case .all: return true
            case .recent: return (repo.pushedDate ?? .distantPast) >= cutoff
            case .missing: return !repo.hasDescription && (descriptions[repo.id] ?? "").isEmpty
            case .archived: return repo.archived
            case .forks: return repo.fork
            }
        }
        func nameOrder(_ a: Repository, _ b: Repository) -> Bool {
            let result = a.full_name.localizedStandardCompare(b.full_name)
            return result == .orderedSame ? a.id < b.id : result == .orderedAscending
        }
        func dateOrder(_ a: Repository, _ b: Repository, _ lhs: String?, _ rhs: String?, ascending: Bool) -> Bool {
            // Older caches can lack creation dates. Keep unknown dates last in either direction.
            if lhs == rhs { return nameOrder(a, b) }
            guard let lhs else { return false }
            guard let rhs else { return true }
            return ascending ? lhs < rhs : lhs > rhs
        }
        return filtered.sorted { a, b in
            switch sort {
            case .name: return nameOrder(a, b)
            case .nameDescending: return nameOrder(b, a)
            case .createdNewest, .createdOldest:
                return dateOrder(a, b, a.created_at, b.created_at, ascending: sort == .createdOldest)
            case .pushed, .pushedOldest:
                return dateOrder(a, b, a.pushed_at, b.pushed_at, ascending: sort == .pushedOldest)
            case .updatedNewest, .updatedOldest:
                return dateOrder(a, b, a.updated_at, b.updated_at, ascending: sort == .updatedOldest)
            case .stars, .starsFewest:
                if a.stargazers_count == b.stargazers_count { return nameOrder(a, b) }
                return sort == .stars ? a.stargazers_count > b.stargazers_count : a.stargazers_count < b.stargazers_count
            case .issuesMost, .issuesFewest:
                if a.open_issues_count == b.open_issues_count { return nameOrder(a, b) }
                return sort == .issuesMost ? a.open_issues_count > b.open_issues_count : a.open_issues_count < b.open_issues_count
            }
        }
    }
}

public actor InventoryCache {
    private let url: URL
    public init(url customURL: URL? = nil) {
        url = customURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Grove/inventory.json")
    }
    public func load() -> Inventory? { try? JSONDecoder().decode(Inventory.self, from: Data(contentsOf: url)) }
    public func save(_ inventory: Inventory) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try JSONEncoder().encode(inventory).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
