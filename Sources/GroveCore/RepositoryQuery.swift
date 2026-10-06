import Foundation
public enum LibraryScope: String, CaseIterable, Sendable {
    case all = "All repositories", recent = "Recently pushed", missing = "Needs a description", archived = "Archived", forks = "Forks"
    public var symbol: String {
        switch self { case .all: "square.stack.3d.up"; case .recent: "clock"; case .missing: "text.badge.plus"; case .archived: "archivebox"; case .forks: "arrow.triangle.branch" }
    }
}
public enum RepositorySort: String, CaseIterable, Sendable { case pushed = "Last pushed", name = "Name", stars = "Stars" }
public enum RepositoryQuery {
    public static func filter(_ repos: [Repository], scope: LibraryScope, owner: String?, search: String, sort: RepositorySort, now: Date = Date()) -> [Repository] {
        let cutoff = now.addingTimeInterval(-30 * 86400)
        let terms = search.split(whereSeparator: \.isWhitespace).map(String.init)
        let filtered = repos.filter { repo in
            if let owner, repo.owner.login != owner { return false }
            if !terms.allSatisfy({ repo.searchText.localizedCaseInsensitiveContains($0) }) { return false }
            switch scope {
            case .all: return true
            case .recent: return (repo.pushedDate ?? .distantPast) >= cutoff
            case .missing: return !repo.hasDescription
            case .archived: return repo.archived
            case .forks: return repo.fork
            }
        }
        return filtered.sorted { a, b in
            switch sort {
            case .name: return a.full_name.localizedStandardCompare(b.full_name) == .orderedAscending
            case .pushed:
                if a.pushed_at == b.pushed_at { return a.full_name < b.full_name }
                return (a.pushed_at ?? "") > (b.pushed_at ?? "")
            case .stars:
                if a.stargazers_count == b.stargazers_count { return a.full_name < b.full_name }
                return a.stargazers_count > b.stargazers_count
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
        try JSONEncoder().encode(inventory).write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
