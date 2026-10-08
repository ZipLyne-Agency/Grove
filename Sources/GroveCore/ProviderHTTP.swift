import Foundation

public struct ProviderRequest: Sendable {
    public let url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?
    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url; self.method = method; self.headers = headers; self.body = body
    }
}
public struct ProviderResponse: Sendable {
    public let status: Int
    public let data: Data
    public init(status: Int, data: Data) { self.status = status; self.data = data }
}
public protocol ProviderTransport: Sendable { func send(_ request: ProviderRequest) async throws -> ProviderResponse }

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
public struct ProviderHTTP: ProviderTransport {
    public init() {}
    public func send(_ request: ProviderRequest) async throws -> ProviderResponse {
        guard Self.allowedHosts.contains(request.url.host ?? ""), request.url.scheme == "https",
              request.url.user == nil, request.url.password == nil, request.url.fragment == nil,
              request.url.port == nil || request.url.port == 443 else { throw WorkspaceError.invalidInput("Unsupported service endpoint.") }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 40
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method; urlRequest.httpBody = request.body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let response = response as? HTTPURLResponse else { throw WorkspaceError.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 4_000_000 else { throw WorkspaceError.invalidResponse }
                data.append(byte)
            }
            return ProviderResponse(status: response.statusCode, data: data)
        } catch is CancellationError { throw CancellationError() }
        catch let error as WorkspaceError { throw error }
        catch { if Task.isCancelled { throw CancellationError() }; throw WorkspaceError.network }
    }
    public static let allowedHosts: Set<String> = [
        "api.onesignal.com", "api.expo.dev", "api.vercel.com", "api.cloudflare.com", "api.revenuecat.com", "sentry.io",
        "www.googleapis.com", "searchconsole.googleapis.com", "analyticsadmin.googleapis.com", "analyticsdata.googleapis.com",
        "androidpublisher.googleapis.com", "oauth2.googleapis.com", "api.appstoreconnect.apple.com"
    ]
}

public enum ProviderAPI {
    public static func endpoint(_ host: String, _ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard ProviderHTTP.allowedHosts.contains(host), path.hasPrefix("/"), !path.contains(".."), path.count <= 4096,
              path.removingPercentEncoding != nil, !path.contains("?"), !path.contains("#") else { throw WorkspaceError.invalidResponse }
        var components = URLComponents(); components.scheme = "https"; components.host = host
        components.percentEncodedPath = path
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw WorkspaceError.invalidResponse }
        return url
    }
    public static func check(_ response: ProviderResponse) throws {
        switch response.status {
        case 200...299: return
        case 401: throw WorkspaceError.authorization
        case 403: throw WorkspaceError.forbidden
        case 404: throw WorkspaceError.notFound
        case 429: throw WorkspaceError.rateLimited
        case 500...599: throw WorkspaceError.network
        default: throw WorkspaceError.invalidResponse
        }
    }
    public static func json(_ response: ProviderResponse) throws -> ServiceJSON {
        try check(response)
        do { return try JSONDecoder().decode(ServiceJSON.self, from: response.data) }
        catch { throw WorkspaceError.invalidResponse }
    }
}
