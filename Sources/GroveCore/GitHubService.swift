import Foundation

/// Only approve can issue a write; confirmations are bound to an immutable preview and consumed once.
public actor GitHubService {
    let transport: any GitHubTransport
    private var pending: [UUID: ActionPreview] = [:]
    public init(transport: any GitHubTransport = CLITransport()) { self.transport = transport }

    public func inventory() async throws -> Inventory {
        let account: Account = try await get("user")
        let organizations: [Organization] = try await pages("user/orgs")
        let repos: [Repository] = try await pages("user/repos", query: "affiliation=owner,collaborator,organization_member&sort=pushed&direction=desc")
        let current: Account = try await get("user")
        guard current == account else { throw GroveError.accountChanged }
        let unique = Dictionary(repos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Inventory(account: account, organizations: organizations, repositories: unique.values.sorted { ($0.pushed_at ?? "") > ($1.pushed_at ?? "") })
    }
    public func readme(_ repo: Repository) async throws -> String {
        guard repo.safeIdentity else { throw GroveError.invalidResponse }
        struct Readme: Decodable { let content: String; let encoding: String }
        let response = try await transport.send(APIRequest(path: "repos/\(repo.full_name)/readme"))
        if response.status == 404 { return "No README is available." }
        try Self.check(response)
        let readme = try JSONDecoder().decode(Readme.self, from: response.data)
        guard readme.encoding == "base64", let data = Data(base64Encoded: readme.content, options: .ignoreUnknownCharacters),
              let text = String(data: data, encoding: .utf8) else { throw GroveError.invalidResponse }
        return String(text.prefix(7000))
    }
    public func prepare(repo: Repository, action: RepositoryAction, inventory: Inventory) throws -> ActionPreview {
        try action.validate(for: repo, destinations: inventory.organizations.map(\.login))
        guard inventory.repositories.contains(where: { $0.id == repo.id && $0 == repo }) else { throw GroveError.stalePreview }
        pending = pending.filter { Date().timeIntervalSince($0.value.createdAt) < 300 }
        let preview = ActionPreview(id: UUID(), repository: repo, action: action, account: inventory.account.login, createdAt: Date())
        pending[preview.id] = preview
        return preview
    }
    public func cancel(_ id: UUID) { pending[id] = nil }
    public func approve(_ id: UUID, typedName: String = "") async throws -> MutationOutcome {
        guard let preview = pending[id], Date().timeIntervalSince(preview.createdAt) < 300 else { throw GroveError.expiredPreview }
        guard !preview.action.requiresTyping || typedName == preview.repository.full_name else { throw GroveError.confirmationRequired }
        pending[id] = nil // Consume before the first suspension: a double-click cannot issue another write.
        let account: Account = try await get("user")
        guard account.login == preview.account else { throw GroveError.accountChanged }
        let repo = preview.repository
        let live: Repository = try await get("repos/\(repo.full_name)")
        guard live.id == repo.id, live.full_name == repo.full_name, live.updated_at == repo.updated_at,
              live.description == repo.description, live.archived == repo.archived else { throw GroveError.stalePreview }
        guard live.canAdminister else { throw GroveError.noAdministration }
        if case .transfer(let owner) = preview.action {
            let orgs: [Organization] = try await pages("user/orgs")
            try preview.action.validate(for: live, destinations: orgs.map(\.login))
            let target = try await transport.send(APIRequest(path: "repos/\(owner)/\(repo.name)"))
            if target.status == 200 { throw GroveError.destinationExists }
            guard target.status == 404 else { try Self.check(target); throw GroveError.invalidResponse }
        }
        let current: Account = try await get("user")
        guard current.login == preview.account else { throw GroveError.accountChanged }
        let path = "repos/\(repo.full_name)"
        let request: APIRequest
        switch preview.action {
        case .rename(let value): request = try Self.patch(path, ["name": value])
        case .describe(let value): request = try Self.patch(path, ["description": value])
        case .archive(let value): request = try Self.patch(path, ["archived": value])
        case .transfer(let owner):
            request = APIRequest(path: path + "/transfer", method: "POST", body: try JSONSerialization.data(withJSONObject: ["new_owner": owner]))
        case .delete: request = APIRequest(path: path, method: "DELETE")
        }
        let result = try await transport.send(request)
        if result.status >= 500 || result.status == 408 { throw GroveError.outcomeUnknown }
        try Self.check(result)
        if case .transfer = preview.action { return .transferRequested }
        // Verify the observed result; a failed verification never causes an automatic write retry.
        do {
            if case .delete = preview.action {
                let check = try await transport.send(APIRequest(path: path))
                return check.status == 404 ? .verified(nil) : .acceptedUnverified
            }
            let resultPath: String
            if case .rename(let name) = preview.action { resultPath = "repos/\(repo.owner.login)/\(name)" } else { resultPath = path }
            let changed: Repository = try await get(resultPath)
            guard changed.id == repo.id else { return .acceptedUnverified }
            switch preview.action {
            case .rename(let name): return changed.name == name ? .verified(changed) : .acceptedUnverified
            case .describe(let text): return (changed.description ?? "") == text ? .verified(changed) : .acceptedUnverified
            case .archive(let value): return changed.archived == value ? .verified(changed) : .acceptedUnverified
            default: return .acceptedUnverified
            }
        } catch { return .acceptedUnverified }
    }
    private func get<T: Decodable>(_ path: String) async throws -> T {
        let result = try await transport.send(APIRequest(path: path)); try Self.check(result)
        return try JSONDecoder().decode(T.self, from: result.data)
    }
    func configurationFile(_ repo: Repository, path: String) async throws -> Data? {
        guard ServiceDiscovery.paths.contains(path), repo.safeIdentity else { throw GroveError.invalidResponse }
        let escaped = path.split(separator: "/").map { ServiceCatalog.component(String($0)) }.joined(separator: "/")
        let response = try await transport.send(APIRequest(path: "repos/\(repo.full_name)/contents/\(escaped)"))
        if response.status == 404 { return nil }
        try Self.check(response)
        struct File: Decodable { let type: String; let encoding: String; let content: String; let size: Int }
        guard let file = try? JSONDecoder().decode(File.self, from: response.data), file.type == "file",
              file.encoding == "base64", file.size <= 100_000,
              let data = Data(base64Encoded: file.content, options: .ignoreUnknownCharacters), data.count <= 100_000 else { return nil }
        return data
    }
    private func pages<T: Decodable>(_ path: String, query: String = "") async throws -> [T] {
        var all: [T] = []
        for page in 1...100 {
            let separator = query.isEmpty ? "" : query + "&"
            let batch: [T] = try await get("\(path)?\(separator)per_page=100&page=\(page)")
            all += batch
            if batch.count < 100 { return all }
        }
        throw GroveError.invalidResponse // Never silently present a truncated inventory as complete.
    }
    private static func patch(_ path: String, _ body: [String: Any]) throws -> APIRequest {
        APIRequest(path: path, method: "PATCH", body: try JSONSerialization.data(withJSONObject: body))
    }
    static func check(_ result: APIResponse) throws {
        guard (200..<300).contains(result.status) else {
            if result.status == 401 { throw GroveError.loginRequired }
            throw GroveError.commandFailed(Int32(result.status))
        }
    }
}
