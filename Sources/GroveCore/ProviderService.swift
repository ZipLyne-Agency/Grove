import Foundation
import CryptoKit

public struct ProviderRenameReview: Identifiable, Sendable {
    public let id: UUID
    public let connection: ServiceConnection
    public let account: ProviderAccount
    public let previousName: String
    public let newName: String
    public let createdAt: Date
}

public actor ProviderService {
    let transport: any ProviderTransport
    let authorizer: ProviderAuthorizer
    private struct Pending { let review: ProviderRenameReview; let credentialHash: SHA256.Digest }
    private var requestsInFlight = 0
    private var pending: [UUID: Pending] = [:]
    public init(transport: any ProviderTransport = ProviderHTTP()) {
        self.transport = transport; authorizer = ProviderAuthorizer(transport: transport)
    }
    public func invalidateAccount(_ id: UUID) async { await authorizer.invalidate(id) }
    func request(_ host: String, _ path: String, account: ProviderAccount, credential: Data,
                 method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) async throws -> ServiceJSON {
        let deadline = Date().addingTimeInterval(120)
        while requestsInFlight >= 2 {
            try Task.checkCancellation()
            guard Date() < deadline else { throw WorkspaceError.network }
            try await Task.sleep(for: .milliseconds(50))
        }
        requestsInFlight += 1; defer { requestsInFlight -= 1 }
        let token = try await authorizer.bearer(account: account, credential: credential)
        let headers = ["Authorization": "\(account.provider == .oneSignal ? "Key" : "Bearer") \(token)", "Content-Type": "application/json"]
        let response = try await transport.send(ProviderRequest(url: ProviderAPI.endpoint(host, path, query: query), method: method, headers: headers, body: body))
        return try ProviderAPI.json(response)
    }
    public func fetch(_ connection: ServiceConnection, account: ProviderAccount, credential: Data) async throws -> ServiceSnapshot {
        guard account.id == connection.accountID, account.provider == connection.provider, !connection.resourceID.isEmpty else { throw WorkspaceError.invalidInput("Check this connection’s account and resource ID.") }
        try ServiceCatalog.validate(account)
        switch connection.provider {
        case .oneSignal: return try await oneSignal(connection, account, credential)
        case .expo: return try await expo(connection, account, credential)
        case .vercel: return try await vercel(connection, account, credential)
        case .cloudflare: return try await cloudflare(connection, account, credential)
        case .revenueCat: return try await revenueCat(connection, account, credential)
        case .sentry: return try await sentry(connection, account, credential)
        case .searchConsole: return try await searchConsole(connection, account, credential)
        case .analytics: return try await analytics(connection, account, credential)
        case .appStore: return try await appStore(connection, account, credential)
        case .googlePlay: return try await googlePlay(connection, account, credential)
        case .custom: throw WorkspaceError.unsupported
        }
    }
    public func prepareRename(_ connection: ServiceConnection, account: ProviderAccount, credential: Data, name: String) async throws -> ProviderRenameReview {
        guard connection.provider.supportsRename, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 128 else { throw WorkspaceError.invalidInput("Enter a name up to 128 characters.") }
        let live = try await fetch(connection, account: account, credential: credential)
        guard name != live.name else { throw WorkspaceError.invalidInput("The service already has this name.") }
        let review = ProviderRenameReview(id: UUID(), connection: connection, account: account, previousName: live.name, newName: name, createdAt: Date())
        pending = pending.filter { Date().timeIntervalSince($0.value.review.createdAt) < 300 }
        pending[review.id] = Pending(review: review, credentialHash: SHA256.hash(data: credential))
        return review
    }
    public func cancel(_ id: UUID) { pending[id] = nil }
    public func approveRename(_ id: UUID, credential: Data) async throws -> ServiceSnapshot {
        guard let item = pending.removeValue(forKey: id), Date().timeIntervalSince(item.review.createdAt) < 300,
              SHA256.hash(data: credential) == item.credentialHash else { throw WorkspaceError.staleReview }
        let review = item.review, account = review.account
        var connection = review.connection
        let live = try await fetch(connection, account: account, credential: credential)
        guard live.name == review.previousName else { throw WorkspaceError.staleReview }
        connection.resourceID = live.resourceID
        let resource = ServiceCatalog.component(connection.resourceID)
        let host: String, path: String, method: String
        var query: [URLQueryItem] = []
        switch connection.provider {
        case .oneSignal: host = "api.onesignal.com"; path = "/apps/\(resource)"; method = "PUT"
        case .sentry: host = "sentry.io"; path = "/api/0/projects/\(ServiceCatalog.component(account.scope))/\(resource)/"; method = "PUT"
        case .vercel:
            host = "api.vercel.com"; path = "/v9/projects/\(resource)"; method = "PATCH"
            if !account.scope.isEmpty { query = [URLQueryItem(name: "teamId", value: account.scope)] }
        default: throw WorkspaceError.unsupported
        }
        let body = try JSONEncoder().encode(["name": review.newName])
        do { _ = try await request(host, path, account: account, credential: credential, method: method, query: query, body: body) }
        catch let error as WorkspaceError where [.authorization, .forbidden, .notFound, .rateLimited].contains(error) { throw error }
        catch { throw WorkspaceError.outcomeUnknown }
        do {
            let updated = try await fetch(connection, account: account, credential: credential)
            guard updated.name == review.newName else { throw WorkspaceError.outcomeUnknown }
            return updated
        } catch { throw WorkspaceError.outcomeUnknown }
    }
}
