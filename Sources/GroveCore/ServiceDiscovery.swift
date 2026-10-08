import Foundation

public struct ServiceSuggestion: Identifiable, Sendable, Equatable {
    public var id: String { "\(repositoryID)-\(provider.rawValue)-\(resourceID)-\(name)" }
    public let repositoryID: Int
    public let provider: ServiceProvider
    public let resourceID: String
    public let name: String
    public let source: String
    public let explanation: String
    public let dashboardURL: String
    public init(repositoryID: Int, provider: ServiceProvider, resourceID: String, name: String, source: String, explanation: String, dashboardURL: String? = nil) {
        self.repositoryID = repositoryID; self.provider = provider; self.resourceID = resourceID
        self.name = name; self.source = source; self.explanation = explanation
        self.dashboardURL = dashboardURL ?? ServiceCatalog.homepage(provider)
    }
}
public enum ServiceDiscovery {
    public static let paths = ["package.json", "app.json", "app.config.ts", "app.config.js", "eas.json", "wrangler.jsonc", "wrangler.toml", "cloudflare.config.ts", ".vercel/project.json", "sentry.properties", "README.md", "Package.swift", "Podfile", "pubspec.yaml", "Cargo.toml", "pyproject.toml", "requirements.txt", "build.gradle.kts", "composeApp/build.gradle.kts", "worker/package.json", "backend/package.json"]
    /// Inspect source text without evaluating JavaScript/configuration or reading environment/credential files.
    public static func inspect(repository: Repository, files: [String: String]) -> [ServiceSuggestion] {
        var suggestions: [ServiceSuggestion] = []
        func add(_ provider: ServiceProvider, _ id: String, _ source: String, _ explanation: String) {
            guard id.count <= 512 else { return }
            if suggestions.contains(where: { $0.provider == provider && ($0.resourceID == id || id.isEmpty) }) { return }
            if !id.isEmpty { suggestions.removeAll { $0.provider == provider && $0.resourceID.isEmpty } }
            suggestions.append(ServiceSuggestion(repositoryID: repository.id, provider: provider, resourceID: id,
                                                name: "\(repository.name) · \(provider.title)", source: source, explanation: explanation))
        }
        func match(_ pattern: String, _ text: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern), let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(result.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
        for path in paths {
            guard let text = files[path], text.utf8.count <= 100_000 else { continue }
            if path == "package.json", let data = text.data(using: .utf8), let json = try? JSONDecoder().decode(ServiceJSON.self, from: data) {
                for (provider, packages) in [(ServiceProvider.expo, ["expo"]), (.oneSignal, ["react-native-onesignal", "@onesignal/node-onesignal"]),
                                             (.revenueCat, ["react-native-purchases", "@revenuecat/purchases-js"]), (.sentry, ["@sentry/react-native", "@sentry/nextjs", "@sentry/node"])] {
                    if packages.contains(where: { json["dependencies"][$0] != .null || json["devDependencies"][$0] != .null }) {
                        add(provider, "", path, "Service SDK found in this repository.")
                    }
                }
            }
            if ["app.json", "app.config.ts", "app.config.js"].contains(path) {
                if let id = match(#"[\"']?projectId[\"']?\s*:\s*[\"']([a-fA-F0-9-]{36})[\"']"#, text) {
                    add(.expo, id, path, "EAS project ID found in configuration. ")
                }
                if let id = match(#"[\"']?(?:oneSignalAppId|onesignalAppId|ONESIGNAL_APP_ID)[\"']?\s*[:=]\s*[\"']([a-fA-F0-9-]{36})[\"']"#, text) {
                    add(.oneSignal, id, path, "OneSignal app ID found in configuration. ")
                }
            }
            if path == ".vercel/project.json", let data = text.data(using: .utf8), let json = try? JSONDecoder().decode(ServiceJSON.self, from: data), let id = json["projectId"].string {
                add(.vercel, id, path, "Vercel project ID found. ")
            }
            if ["wrangler.jsonc", "wrangler.toml", "cloudflare.config.ts"].contains(path),
               let name = match(#"[\"']?name[\"']?\s*[:=]\s*[\"']([A-Za-z0-9_-]+)[\"']"#, text) {
                add(.cloudflare, name, path, "Worker name found. ")
            }
            if path == "sentry.properties", let name = match(#"(?m)^defaults\.project\s*=\s*([A-Za-z0-9_-]+)"#, text) {
                add(.sentry, name, path, "Sentry project slug found. ")
            }
        }
        return suggestions
    }
}

extension GitHubService {
    public func serviceConfiguration(_ repo: Repository) async throws -> [String: String] {
        guard repo.safeIdentity else { throw GroveError.invalidResponse }
        var files: [String: String] = [:]
        for path in ServiceDiscovery.paths {
            try Task.checkCancellation()
            let data = try await configurationFile(repo, path: path)
            if let data, let text = String(data: data, encoding: .utf8) { files[path] = text }
        }
        return files
    }
    public func discoverServices(_ repo: Repository) async throws -> [ServiceSuggestion] {
        ServiceDiscovery.inspect(repository: repo, files: try await serviceConfiguration(repo))
    }
}
