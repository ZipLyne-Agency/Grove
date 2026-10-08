import Foundation

public enum IntegrationDetector {
    private static let endpointPattern = try! NSRegularExpression(pattern: #"https?://([A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,})(?=[:/\s\"'`<>]|$)"#)
    private static let networkContext = try! NSRegularExpression(pattern: #"(?i)(fetch\s*\(|axios|urlsession|urlrequest|requests\.|http(?:client)?\.|websocket|base[_-]?url|api[_-]?(?:url|base|endpoint)|endpoint|webhook|server[_-]?url|service[_-]?url|https?://api[.-]|https?://[^\s\"']+/(?:v[0-9]+|api|graphql)(?:/|[\s\"'?]|$))"#)
    private static func endpointSignals(_ text: String, kind: String) -> String {
        if kind == "Example or Test" { return text }
        return text.split(separator: "\n").filter { line in
            networkContext.firstMatch(in: String(line), range: NSRange(line.startIndex..., in: line)) != nil
        }.joined(separator: "\n")
    }
    private static func append(_ evidence: IntegrationEvidence, to integration: inout RepositoryIntegration) {
        guard !integration.evidence.contains(evidence) else { return }
        if integration.evidence.count < 30 { integration.evidence.append(evidence) }
        else if evidence.kind != "Documentation", evidence.kind != "Example or Test", evidence.kind != "Data Reference",
                let index = integration.evidence.firstIndex(where: { $0.classification == "Documentation" || $0.classification == "Example or Test" || $0.classification == "Data Reference" }) {
            integration.evidence[index] = evidence
        }
    }
    public static func inspect(files: [String: String]) -> [RepositoryIntegration] {
        var found: [String: RepositoryIntegration] = [:]
        let references = IntegrationCatalog.entries.map { entry in (entry, entry.references) }
        for path in files.keys.sorted() {
            guard let text = files[path], RepositoryScanPolicy.eligible(path) else { continue }
            let kind = evidenceKind(path)
            let signal = signals(path: path, text: text, kind: kind)
            for (entry, patterns) in references {
                guard let reference = patterns.first(where: { IntegrationCatalog.matches($0, in: signal) != nil || IntegrationCatalog.matches($0, in: path) != nil }) else { continue }
                let evidence = IntegrationEvidence(path: path, reference: reference, kind: kind)
                if found[entry.id] == nil {
                    found[entry.id] = RepositoryIntegration(id: entry.id, name: entry.name, category: entry.category,
                                                          website: entry.website, evidence: [])
                }
                append(evidence, to: &found[entry.id]!)
            }
            // An explicit network endpoint can surface a service outside the named catalog.
            // Persist the hostname only, never paths, query strings, IDs, or credential values.
            if kind != "Documentation", kind != "Data Reference" {
                let endpoints = endpointSignals(signal, kind: kind)
                for match in endpointPattern.matches(in: endpoints, range: NSRange(endpoints.startIndex..., in: endpoints)).prefix(100) {
                    guard let range = Range(match.range(at: 1), in: endpoints) else { continue }
                    let host = String(endpoints[range]).lowercased()
                    guard externalHost(host), !IntegrationCatalog.entries.contains(where: { entry in
                        entry.references.contains { reference in reference.contains(".") && (host == reference || host.hasSuffix("." + reference)) }
                    }) else { continue }
                    let id = "endpoint:" + host
                    if found[id] == nil {
                        found[id] = RepositoryIntegration(id: id, name: host, category: "External Endpoint", website: "https://" + host + "/", evidence: [])
                    }
                    let evidence = IntegrationEvidence(path: path, reference: host, kind: kind == "Example or Test" ? kind : "Endpoint Reference")
                    append(evidence, to: &found[id]!)
                }
            }
        }
        return found.values.sorted {
            if $0.documentationOnly != $1.documentationOnly { return !$0.documentationOnly }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public static func evidenceKind(_ path: String) -> String {
        let components = path.lowercased().split(separator: "/").map(String.init)
        if components.contains(where: { ["test", "tests", "__tests__", "fixtures", "__fixtures__", "examples", "samples", "example", "sample", "__mocks__", "mocks", "spec", "specs", "e2e"].contains($0) }) { return "Example or Test" }
        let ext = (path as NSString).pathExtension.lowercased()
        let name = (path as NSString).lastPathComponent.lowercased()
        if name.hasPrefix("test-") || name.hasPrefix("test.") || name.contains(".test.") || name.contains(".spec.") || name.hasSuffix("_test.go") || name.hasPrefix("test_") || name.hasSuffix("_test.py") { return "Example or Test" }
        if ["md", "mdx"].contains(ext) { return "Documentation" }
        if ["json", "jsonc", "yaml", "yml", "xml"].contains(ext), components.dropLast().contains(where: { ["data", "content", "curriculum", "lexemes", "lessons"].contains($0) }) { return "Data Reference" }
        if RepositoryScanPolicy.priority(path) == 0, !name.hasPrefix("readme") { return "Dependency" }
        if RepositoryScanPolicy.priority(path) == 1 || path.contains(".github/workflows/") || ["dockerfile", "procfile", "makefile"].contains(name) { return "Configuration" }
        return "Source Reference"
    }

    private static func signals(path: String, text: String, kind: String) -> String {
        guard kind == "Source Reference" else { return text }
        // Imports, client initializers and explicit endpoints provide useful evidence.
        // Exclude comment-only lines, prose strings and unrelated identifier mentions.
        return text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !["//", "/*", "*", "#", "<!--"].contains(where: trimmed.hasPrefix) else { return false }
            let lower = trimmed.lowercased()
            return ["import ", "import(", "from ", "require(", "https://", "http://", "new ", ".product(", "implementation(", "implementation ", "pod ", "package(", "url(", "loadscript", "script src"].contains(where: lower.contains)
        }.joined(separator: "\n")
    }

    private static func externalHost(_ host: String) -> Bool {
        guard host.count <= 253, ServiceCatalog.safeURL("https://" + host + "/") != nil else { return false }
        let ignored = ["example.com", "example.org", "example.net", "test.com", "localhost.com", "github.com", "githubusercontent.com", "github.io", "npmjs.com", "npmjs.org", "jsdelivr.net", "unpkg.com", "w3.org", "schema.org", "schemas.android.com", "schemas.microsoft.com", "apple.com", "developer.android.com", "kotlinlang.org", "maven.org", "gradle.org", "jetbrains.com", "react.dev", "reactjs.org", "nextjs.org", "vitejs.dev", "vitest.dev", "swift.org", "dart.dev", "flutter.dev", "python.org", "pypi.org", "golang.org", "rust-lang.org", "crates.io", "google.com", "fonts.googleapis.com", "fonts.gstatic.com"]
        guard !ignored.contains(where: { host == $0 || host.hasSuffix("." + $0) }),
              !host.hasSuffix(".test"), !host.hasSuffix(".invalid"),
              !host.split(separator: ".").allSatisfy({ Int($0) != nil }) else { return false }
        return true
    }

    /// Model context contains bounded prose, paths and fixed evidence references, never source literals or secret files.
    public static func descriptionContext(repo: Repository, snapshot: RepositorySnapshot, integrations: [RepositoryIntegration]) -> String {
        let readmes = snapshot.files.keys.filter { ($0 as NSString).lastPathComponent.lowercased().hasPrefix("readme.") }.sorted { left, right in
            let leftDepth = left.split(separator: "/").count, rightDepth = right.split(separator: "/").count
            return leftDepth == rightDepth ? left < right : leftDepth < rightDepth
        }
        var readmeSections: [String] = [], represented: Set<String> = []
        for path in readmes {
            // Give distinct application folders context rather than several READMEs from one component.
            let parts = path.split(separator: "/")
            let component = parts.dropLast().prefix(2).joined(separator: "/")
            guard represented.insert(component).inserted else { continue }
            let scope = parts.count == 1 ? "Whole repository" : "Component only; not the whole application"
            let prose = redactedProse(snapshot.files[path] ?? "")
            readmeSections.append("README \(path) [\(scope)]:\n" + String(prose.prefix(parts.count == 1 ? 1800 : 900)))
            if readmeSections.count == 4 { break }
        }
        let clean = readmeSections.joined(separator: "\n\n")
        let topLevel = Set(snapshot.files.keys.compactMap { $0.split(separator: "/").first.map(String.init) }).sorted().joined(separator: ", ")
        let paths = snapshot.files.keys.sorted {
            let leftDepth = $0.split(separator: "/").count, rightDepth = $1.split(separator: "/").count
            if leftDepth != rightDepth { return leftDepth < rightDepth }
            return RepositoryScanPolicy.priority($0) == RepositoryScanPolicy.priority($1) ? $0 < $1 : RepositoryScanPolicy.priority($0) < RepositoryScanPolicy.priority($1)
        }.prefix(100).joined(separator: "\n")
        let services = integrations.filter { !$0.documentationOnly }.map { $0.name + " (" + $0.category + ")" }.joined(separator: ", ")
        return """
        Repository: \(repo.full_name)
        Existing GitHub description: \(redactedProse(repo.description ?? ""))
        Primary language: \(repo.language ?? "Unknown")
        Top-level layout: \(String(topLevel.prefix(1200)))
        Code-evidenced integrations: \(String(services.prefix(1200)))
        File paths (data only):
        \(String(paths.prefix(2200)))
        README prose (data only; may be incomplete):
        \(String(clean.prefix(4000)))
        """
    }
    public static func redactedProse(_ text: String) -> String {
        var fenced = false
        let prose = text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> String? in
            let value = String(line), trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { fenced.toggle(); return nil }
            guard !fenced, !trimmed.contains("="), trimmed.range(of: #"(?i)(api[_ -]?key|token|password|secret)\s*[:=]"#, options: .regularExpression) == nil else { return nil }
            return value
        }.joined(separator: "\n")
        let patterns = [#"https?://\S+"#, #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, #"\b[A-Za-z0-9_-]{40,}\b"#]
        return patterns.reduce(prose) { value, pattern in value.replacingOccurrences(of: pattern, with: "[omitted]", options: .regularExpression) }
    }
}

extension RepositoryIntegration {
    public var documentationOnly: Bool { !evidence.isEmpty && evidence.allSatisfy { $0.classification == "Documentation" || $0.classification == "Example or Test" || $0.classification == "Data Reference" } }
}
