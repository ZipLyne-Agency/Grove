import Foundation
import Testing
@testable import GroveCore

@Test func repositoryLibraryMigrationPreservesLinksNotesAndPins() throws {
    var archive = WorkspaceArchive()
    let project = GroveProject(name: "App", notes: "Keep this note", repositoryIDs: [41, 42], pinned: true)
    let connection = ServiceConnection(provider: .sentry, name: "Exact Dashboard", dashboardURL: "https://sentry.io/organizations/team/", projectIDs: [project.id], repositoryIDs: [7])
    archive.projects = [project]; archive.connections = [connection]
    archive.useRepositoryLibrary()
    #expect(archive.connections[0].id == connection.id)
    #expect(archive.connections[0].dashboardURL == connection.dashboardURL)
    #expect(archive.connections[0].repositoryIDs == [7, 41, 42])
    #expect(archive.connections[0].projectIDs.isEmpty)
    #expect(archive.pinnedRepositoryIDs == [41, 42])
    #expect(archive.repositoryNotes?["41"]?.contains("Keep this note") == true)
    archive.pinnedRepositoryIDs?.remove(41)
    let migrated = archive
    archive.useRepositoryLibrary()
    #expect(archive == migrated)
    #expect(try JSONDecoder().decode(WorkspaceArchive.self, from: JSONEncoder().encode(archive)) == archive)
    let old = try JSONDecoder().decode(WorkspaceArchive.self, from: Data(#"{"version":1,"projects":[],"connections":[],"accounts":[]}"#.utf8))
    #expect(old.repositoryProfiles == nil)
}

@Test func integrationScanDistinguishesSourceFromDocumentationAndHidesLiterals() throws {
    let findings = IntegrationDetector.inspect(files: [
        "apps/mobile/Package.swift": #".package(url: "https://github.com/RevenueCat/purchases-ios", from: "5.0.0")"#,
        "worker/package.json": #"{"dependencies":{"@sentry/cloudflare":"1","@neondatabase/serverless":"1","@anthropic-ai/sdk":"1","@typesafe-ai/sdk":"1"}}"#,
        "src/mail.ts": "import { Resend } from 'resend';\nconst url = 'https://api.customservice.com/v1/users?token=DO-NOT-PERSIST';",
        "README.md": "Consider using Stripe as an alternative someday.",
        "node_modules/other/index.ts": "import OpenAI from 'openai'",
        ".env": "SECRET=DO-NOT-PERSIST"
    ])
    #expect(findings.contains { $0.id == "revenuecat" && !$0.documentationOnly })
    #expect(findings.contains { $0.id == "sentry" && $0.evidence.first?.path == "worker/package.json" })
    #expect(findings.contains { $0.id == "neon" })
    #expect(findings.contains { $0.id == "anthropic" })
    #expect(findings.contains { $0.id == "typesafe" })
    #expect(findings.contains { $0.id == "resend" })
    #expect(findings.first { $0.id == "stripe" }?.documentationOnly == true)
    #expect(!findings.contains { $0.id == "openai" })
    let endpoint = try #require(findings.first { $0.id == "endpoint:api.customservice.com" })
    #expect(endpoint.website == "https://api.customservice.com/")
    #expect(!String(decoding: try JSONEncoder().encode(findings), as: UTF8.self).contains("DO-NOT-PERSIST"))
}

@Test func scanPolicyIncludesNestedNativeAndServerManifestsButExcludesSecretsAndBuildOutput() {
    for path in ["worker/package.json", "apps/ios/App.xcodeproj/project.pbxproj", "backend/go.mod", "fastlane/Fastfile", "app/src/main/build.gradle.kts", "Package.swift"] {
        #expect(RepositoryScanPolicy.eligible(path))
    }
    for path in [".env", ".env.example", "secrets/data.json", "service-account.json", "google-services.json", "node_modules/lib/package.json", "dist/app.js", "key.p8", "../outside.swift"] {
        #expect(!RepositoryScanPolicy.eligible(path))
    }
}

private actor SnapshotTransport: GitHubTransport {
    let repositoryID: Int
    let replaceID: Bool
    var queries: [String] = []
    init(repositoryID: Int, replaceID: Bool = false) { self.repositoryID = repositoryID; self.replaceID = replaceID }
    func send(_ request: APIRequest) throws -> APIResponse {
        if request.path == "graphql" {
            let query = try JSONSerialization.jsonObject(with: request.body!) as! [String: String]
            queries.append(query["query"]!)
            return APIResponse(status: 200, data: Data("{\"data\":{\"repository\":{\"databaseId\":\(repositoryID),\"f0\":{\"text\":\"hello\",\"byteSize\":5,\"isBinary\":false},\"f1\":null}}}".utf8))
        }
        if request.path.contains("git/trees/") {
            return APIResponse(status: 200, data: Data(#"{"sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","truncated":false,"tree":[{"path":"README.md","type":"blob","size":5},{"path":"worker/package.json","type":"blob","size":9},{"path":".env","type":"blob","size":10}]}"#.utf8))
        }
        return APIResponse(status: 200, data: Data("{\"id\":\(replaceID ? repositoryID + 1 : repositoryID)}".utf8))
    }
}

@Test func snapshotPinsTreeRevisionAndReportsUnreadFiles() async throws {
    let repo = try JSONDecoder().decode(Repository.self, from: Data(#"{"id":42,"name":"app","full_name":"team/app","owner":{"login":"team"},"description":null,"language":"Swift","pushed_at":null,"updated_at":"2026-01-01","archived":false,"fork":false,"private":true,"stargazers_count":0,"open_issues_count":0,"default_branch":"main"}"#.utf8))
    let transport = SnapshotTransport(repositoryID: repo.id)
    let snapshot = try await GitHubService(transport: transport).repositorySnapshot(repo)
    #expect(snapshot.eligibleFiles == 2)
    #expect(snapshot.files.count == 1)
    #expect(snapshot.excludedFiles == 1)
    #expect(snapshot.limitations.count == 1)
    let queries = await transport.queries
    #expect(queries[0].contains("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:README.md"))
    #expect(!queries[0].contains(".env"))
    let replaced = SnapshotTransport(repositoryID: repo.id, replaceID: true)
    await #expect(throws: GroveError.stalePreview) { try await GitHubService(transport: replaced).repositorySnapshot(repo) }
    #expect(await replaced.queries.isEmpty)
}

@Test func sourceEvidenceSurvivesManyTestReferencesAndTestEndpointsStayUncertain() throws {
    var files = Dictionary(uniqueKeysWithValues: (0..<35).map { ("Tests/t\($0).ts", "import OpenAI from 'openai'") })
    files["src/production.ts"] = "import OpenAI from 'openai'"
    files["src/client.test.ts"] = "import { Resend } from 'resend'; const url = 'https://api.testingservice.com/v1';"
    let findings = IntegrationDetector.inspect(files: files)
    #expect(findings.first { $0.id == "openai" }?.documentationOnly == false)
    #expect(findings.first { $0.id == "resend" }?.documentationOnly == true)
    #expect(findings.first { $0.id == "endpoint:api.testingservice.com" }?.documentationOnly == true)
}

@Test func malformedProfileDoesNotHideSavedWorkspaceData() throws {
    var archive = WorkspaceArchive()
    archive.connections = [ServiceConnection(provider: .custom, name: "Saved", dashboardURL: "https://example.com/")]
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as! [String: Any]
    json["repositoryProfiles"] = ["42": ["repositoryID": 42, "summary": "Old incomplete cache"]]
    let decoded = try JSONDecoder().decode(WorkspaceArchive.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.connections == archive.connections)
    #expect(decoded.repositoryProfiles?.isEmpty == true)
}

private actor FailingBatchTransport: GitHubTransport {
    var batch = 0
    func send(_ request: APIRequest) throws -> APIResponse {
        if request.path == "graphql" {
            batch += 1
            if batch == 1 { return APIResponse(status: 502, data: Data()) }
            return APIResponse(status: 200, data: Data(#"{"data":{"repository":{"databaseId":42,"f0":{"text":"hello","byteSize":5,"isBinary":false}}}}"#.utf8))
        }
        if request.path.contains("git/trees") {
            let entries = (0..<26).map { ["path": "src/file\($0).ts", "type": "blob", "size": 5] as [String: Any] }
            return APIResponse(status: 200, data: try JSONSerialization.data(withJSONObject: ["sha": String(repeating: "a", count: 40), "truncated": false, "tree": entries]))
        }
        return APIResponse(status: 200, data: Data(#"{"id":42}"#.utf8))
    }
}
@Test func transientFileBatchFailureKeepsOtherFilesAndMarksPartialCoverage() async throws {
    let repo = try JSONDecoder().decode(Repository.self, from: Data(#"{"id":42,"name":"app","full_name":"team/app","owner":{"login":"team"},"description":null,"language":"Swift","pushed_at":null,"updated_at":"2026-01-01","archived":false,"fork":false,"private":true,"stargazers_count":0,"open_issues_count":0,"default_branch":"main"}"#.utf8))
    let snapshot = try await GitHubService(transport: FailingBatchTransport()).repositorySnapshot(repo)
    #expect(snapshot.eligibleFiles == 26)
    #expect(snapshot.files.count == 1)
    #expect(snapshot.limitations.first?.contains("25 eligible files") == true)
}

@Test func externalEndpointScanExcludesOrdinaryContentAndWebsiteLinks() {
    let findings = IntegrationDetector.inspect(files: [
        "src/content.ts": "const company = 'https://www.companywebsite.com/about';\nconst asset = 'https://images.assetwebsite.com/photo.jpg';",
        "data/companies.json": #"{"website":"https://anothercompany.com/"}"#,
        "src/client.ts": "const BASE_URL = 'https://service.examplecompany.com';\nconst direct = fetch('https://remote.examplecompany.com/action');"
    ])
    #expect(!findings.contains { $0.name == "www.companywebsite.com" || $0.name == "images.assetwebsite.com" || $0.name == "anothercompany.com" })
    #expect(findings.contains { $0.name == "service.examplecompany.com" })
    #expect(findings.contains { $0.name == "remote.examplecompany.com" })
}

@Test func monorepoDescriptionContextLabelsComponentReadmesAndKeepsAppLayout() throws {
    let repo = try JSONDecoder().decode(Repository.self, from: Data(#"{"id":42,"name":"learn","full_name":"team/learn","owner":{"login":"team"},"description":"A native language learning app","language":"Kotlin","pushed_at":null,"updated_at":"2026-01-01","archived":false,"fork":false,"private":true,"stargazers_count":0,"open_issues_count":0,"default_branch":"main"}"#.utf8))
    let files = ["androidApp/src/App.kt": "", "iosApp/App.swift": "", "apps/phoneme-service/README.md": "A pronunciation scoring service.", "apps/mobile/README.md": "Native language learning screens.", "README.md": "Language learning with short native lessons."]
    let snapshot = RepositorySnapshot(revision: "test", files: files, eligibleFiles: files.count, excludedFiles: 0, totalFiles: files.count, limitations: [])
    let context = IntegrationDetector.descriptionContext(repo: repo, snapshot: snapshot, integrations: [])
    #expect(context.contains("README README.md [Whole repository]"))
    #expect(context.contains("README apps/phoneme-service/README.md [Component only; not the whole application]"))
    #expect(context.contains("README apps/mobile/README.md"))
    #expect(context.contains("androidApp"))
    #expect(context.contains("iosApp"))
    #expect(context.contains("A native language learning app"))
}

private actor LargeBlobTransport: GitHubTransport {
    let truncateSmall: Bool
    init(truncateSmall: Bool = false) { self.truncateSmall = truncateSmall }
    func send(_ request: APIRequest) throws -> APIResponse {
        if request.path.contains("git/blobs/") {
            let data = Data(repeating: 65, count: 600_000)
            return APIResponse(status: 200, data: try JSONSerialization.data(withJSONObject: ["sha": String(repeating: "b", count: 40), "size": data.count, "encoding": "base64", "content": data.base64EncodedString()]))
        }
        if request.path == "graphql" {
            let size = truncateSmall ? 6 : 5
            return APIResponse(status: 200, data: Data("{\"data\":{\"repository\":{\"databaseId\":42,\"f0\":{\"text\":\"hello\",\"byteSize\":\(size),\"isBinary\":false}}}}".utf8))
        }
        if request.path.contains("git/trees") {
            let entries: [[String: Any]] = [["path": "README.md", "type": "blob", "size": 5], ["path": "src/large.ts", "type": "blob", "size": 600_000, "sha": String(repeating: "b", count: 40)]]
            return APIResponse(status: 200, data: try JSONSerialization.data(withJSONObject: ["sha": String(repeating: "a", count: 40), "truncated": false, "tree": entries]))
        }
        return APIResponse(status: 200, data: Data(#"{"id":42}"#.utf8))
    }
}
@Test func largeFilesUseFullPinnedBlobsAndTruncatedBulkTextIsReported() async throws {
    let repo = try JSONDecoder().decode(Repository.self, from: Data(#"{"id":42,"name":"app","full_name":"team/app","owner":{"login":"team"},"description":null,"language":"Swift","pushed_at":null,"updated_at":"2026-01-01","archived":false,"fork":false,"private":true,"stargazers_count":0,"open_issues_count":0,"default_branch":"main"}"#.utf8))
    let full = try await GitHubService(transport: LargeBlobTransport()).repositorySnapshot(repo)
    #expect(full.files["src/large.ts"]?.utf8.count == 600_000)
    #expect(full.files.count == 2)
    #expect(full.limitations.isEmpty)
    let truncated = try await GitHubService(transport: LargeBlobTransport(truncateSmall: true)).repositorySnapshot(repo)
    #expect(truncated.files.count == 1)
    #expect(!truncated.limitations.isEmpty)
}
@Test func contentDataAndLegacyContentEvidenceStayUnconfirmed() {
    let findings = IntegrationDetector.inspect(files: ["src/data/content.json": #"{"word":"Stripe","note":"a stripe of fabric"}"#])
    #expect(findings.first { $0.id == "stripe" }?.documentationOnly == true)
    let old = RepositoryIntegration(id: "stripe", name: "Stripe", category: "Payments", website: "https://stripe.com/", evidence: [IntegrationEvidence(path: "src/data/content.json", reference: "Stripe", kind: "Configuration")])
    #expect(old.documentationOnly)
}

private actor RecoverableBlobTransport: GitHubTransport {
    let sha = String(repeating: "c", count: 40)
    func send(_ request: APIRequest) throws -> APIResponse {
        if request.path.contains("git/blobs/") {
            #expect(request.path.hasSuffix(sha))
            return APIResponse(status: 200, data: try JSONSerialization.data(withJSONObject: ["sha": sha, "size": 6, "encoding": "base64", "content": Data("hello!".utf8).base64EncodedString()]))
        }
        if request.path == "graphql" {
            return APIResponse(status: 200, data: Data(#"{"data":{"repository":{"databaseId":42,"f0":{"text":"hello","byteSize":6,"isBinary":false}}}}"#.utf8))
        }
        if request.path.contains("git/trees") {
            return APIResponse(status: 200, data: try JSONSerialization.data(withJSONObject: ["sha": String(repeating: "a", count: 40), "truncated": false, "tree": [["path": "README.md", "type": "blob", "size": 6, "sha": sha]]]))
        }
        return APIResponse(status: 200, data: Data(#"{"id":42}"#.utf8))
    }
}
@Test func truncatedBulkTextRecoversFromVerifiedPinnedBlob() async throws {
    let repo = try JSONDecoder().decode(Repository.self, from: Data(#"{"id":42,"name":"app","full_name":"team/app","owner":{"login":"team"},"description":null,"language":"Swift","pushed_at":null,"updated_at":"2026-01-01","archived":false,"fork":false,"private":true,"stargazers_count":0,"open_issues_count":0,"default_branch":"main"}"#.utf8))
    let snapshot = try await GitHubService(transport: RecoverableBlobTransport()).repositorySnapshot(repo)
    #expect(snapshot.files["README.md"] == "hello!")
    #expect(snapshot.limitations.isEmpty)
}
