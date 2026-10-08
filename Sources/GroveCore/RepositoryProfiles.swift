import Foundation

public struct IntegrationEvidence: Codable, Equatable, Sendable, Identifiable {
    public var id: String { path + ":" + reference }
    public let path: String
    public let reference: String
    public let kind: String
    public var classification: String {
        let inferred = IntegrationDetector.evidenceKind(path)
        return ["Documentation", "Example or Test", "Data Reference"].contains(inferred) ? inferred : kind
    }
    public init(path: String, reference: String, kind: String) {
        self.path = path; self.reference = reference; self.kind = kind
    }
}

public struct RepositoryIntegration: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let category: String
    public let website: String
    public var evidence: [IntegrationEvidence]
    public init(id: String, name: String, category: String, website: String, evidence: [IntegrationEvidence]) {
        self.id = id; self.name = name; self.category = category; self.website = website; self.evidence = evidence
    }
}

public struct RepositoryProfile: Codable, Equatable, Sendable {
    public let repositoryID: Int
    public let fullName: String
    public var summary: String
    public var overview: String
    public var descriptionSource: String
    public var integrations: [RepositoryIntegration]
    public var hiddenIntegrationIDs: Set<String>?
    public var visibleIntegrations: [RepositoryIntegration] {
        integrations.filter { hiddenIntegrationIDs?.contains($0.id) != true }
    }
    public let scannedAt: Date
    public let revision: String
    public let eligibleFiles: Int
    public let scannedFiles: Int
    public let excludedFiles: Int
    public let totalFiles: Int
    public let limitations: [String]
    public var complete: Bool { limitations.isEmpty }
    public init(repositoryID: Int, fullName: String, summary: String, overview: String, descriptionSource: String,
                integrations: [RepositoryIntegration], revision: String, eligibleFiles: Int, scannedFiles: Int,
                excludedFiles: Int, totalFiles: Int, limitations: [String], scannedAt: Date = Date()) {
        self.repositoryID = repositoryID; self.fullName = fullName; self.summary = summary; self.overview = overview
        self.descriptionSource = descriptionSource; self.integrations = integrations; self.revision = revision
        self.eligibleFiles = eligibleFiles; self.scannedFiles = scannedFiles; self.excludedFiles = excludedFiles
        self.totalFiles = totalFiles; self.limitations = limitations; self.scannedAt = scannedAt
    }
}

public struct RepositorySnapshot: Sendable {
    public let revision: String
    public let files: [String: String]
    public let eligibleFiles: Int
    public let excludedFiles: Int
    public let totalFiles: Int
    public let limitations: [String]
    public init(revision: String, files: [String: String], eligibleFiles: Int, excludedFiles: Int, totalFiles: Int, limitations: [String]) {
        self.revision = revision; self.files = files; self.eligibleFiles = eligibleFiles
        self.excludedFiles = excludedFiles; self.totalFiles = totalFiles; self.limitations = limitations
    }
}

/// Only source and public configuration shapes are eligible. Secret files, generated output and vendor code are excluded.
public enum RepositoryScanPolicy {
    public static let maximumFiles = 5000
    public static let maximumFileBytes = 4_000_000
    public static let maximumTotalBytes = 100_000_000
    public static func eligible(_ path: String) -> Bool {
        let components = path.lowercased().split(separator: "/").map(String.init)
        guard !path.hasPrefix("/"), !components.contains(".."), let name = components.last else { return false }
        let excluded = ["node_modules", "vendor", "pods", "carthage", ".git", ".build", ".next", "build", "dist", "coverage", "deriveddata", "generated", ".gradle", "__pycache__", ".venv", "venv", "third_party", "third-party"]
        guard !components.contains(where: excluded.contains),
              !components.contains(where: { $0.hasPrefix(".env") || $0.contains("credential") || $0 == "secrets" || $0 == ".secrets" || $0 == ".infisical" }),
              !name.contains("secret"), !name.contains("credential"), !name.contains("service-account"),
              !["package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lock", "bun.lockb", "composer.lock", "cargo.lock", "poetry.lock", "uv.lock", "podfile.lock", "gemfile.lock", "google-services.json", "googleservice-info.plist"].contains(name) else { return false }
        let ext = (name as NSString).pathExtension
        if ["pem", "key", "p8", "p12", "pfx", "mobileprovision", "provisionprofile", "keystore", "jks", "enc"].contains(ext) { return false }
        return ["swift", "m", "mm", "h", "kt", "kts", "java", "ts", "tsx", "js", "jsx", "mjs", "cjs", "vue", "svelte", "py", "rb", "go", "rs", "php", "dart", "cs", "fs", "ex", "exs", "json", "jsonc", "toml", "yaml", "yml", "xml", "plist", "gradle", "tf", "sh", "sql", "md", "mdx", "html", "c", "cc", "cpp", "hpp", "properties", "pbxproj", "entitlements"].contains(ext)
            || ["dockerfile", "procfile", "gemfile", "podfile", "makefile", "requirements.txt", "go.mod", "fastfile", "appfile"].contains(name)
    }
    public static func priority(_ path: String) -> Int {
        let name = (path as NSString).lastPathComponent.lowercased()
        if name.hasPrefix("readme.") || ["package.json", "package.swift", "pubspec.yaml", "pyproject.toml", "requirements.txt", "podfile", "gemfile", "go.mod", "cargo.toml", "composer.json"].contains(name) { return 0 }
        if ["json", "jsonc", "toml", "yaml", "yml", "plist", "xml", "tf"].contains((path as NSString).pathExtension.lowercased()) { return 1 }
        return 2
    }
}
