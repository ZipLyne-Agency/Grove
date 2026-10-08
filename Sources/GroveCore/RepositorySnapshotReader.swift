import Foundation

extension GitHubService {
    /// Read one immutable Git tree, then fetch only eligible text blobs in bounded GraphQL batches.
    public func repositorySnapshot(_ repo: Repository, progress: (@Sendable (Int, Int) async -> Void)? = nil) async throws -> RepositorySnapshot {
        guard repo.safeIdentity else { throw GroveError.invalidResponse }
        struct Identity: Decodable { let id: Int }
        func verifyIdentity() async throws {
            let identity = try await transport.send(APIRequest(path: "repos/\(repo.full_name)"))
            try Self.check(identity)
            guard try JSONDecoder().decode(Identity.self, from: identity.data).id == repo.id else { throw GroveError.stalePreview }
        }
        try await verifyIdentity()
        let branch = ServiceCatalog.component(repo.default_branch)
        let response = try await transport.send(APIRequest(path: "repos/\(repo.full_name)/git/trees/\(branch)?recursive=1"))
        if response.status == 409 {
            try await verifyIdentity()
            return RepositorySnapshot(revision: "empty", files: [:], eligibleFiles: 0, excludedFiles: 0, totalFiles: 0, limitations: [])
        }
        try Self.check(response)
        struct Tree: Decodable {
            struct Entry: Decodable { let path: String; let type: String; let size: Int?; let sha: String? }
            let sha: String; let truncated: Bool; let tree: [Entry]
        }
        let tree = try JSONDecoder().decode(Tree.self, from: response.data)
        guard tree.sha.range(of: "^[a-fA-F0-9]{40,64}$", options: .regularExpression) != nil else { throw GroveError.invalidResponse }
        let blobs = tree.tree.filter { $0.type == "blob" }
        let eligible = blobs.filter { RepositoryScanPolicy.eligible($0.path) }.sorted {
            let left = RepositoryScanPolicy.priority($0.path), right = RepositoryScanPolicy.priority($1.path)
            return left == right ? $0.path < $1.path : left < right
        }
        var limitations: [String] = []
        if tree.truncated { limitations.append("GitHub returned a truncated file tree.") }
        let small = eligible.filter { ($0.size ?? 0) <= RepositoryScanPolicy.maximumFileBytes }
        if small.count != eligible.count { limitations.append("\(eligible.count - small.count) eligible files exceeded the per-file size limit.") }
        let selected = Array(small.prefix(RepositoryScanPolicy.maximumFiles))
        if selected.count != small.count { limitations.append("\(small.count - selected.count) eligible files exceeded the file-count limit.") }
        try await verifyIdentity()
        var files: [String: String] = [:], byteCount = 0, unread = 0
        // GitHub GraphQL silently truncates Blob.text at 512 KB. Read larger text via pinned blob IDs.
        let large = selected.filter { ($0.size ?? 0) > 500_000 }
        let batched = selected.filter { ($0.size ?? 0) <= 500_000 }
        func readFullBlob(_ entry: Tree.Entry) async throws -> (text: String, bytes: Int) {
            guard let sha = entry.sha, sha.range(of: "^[a-fA-F0-9]{40,64}$", options: .regularExpression) != nil else { throw GroveError.invalidResponse }
            let response = try await transport.send(APIRequest(path: "repos/\(repo.full_name)/git/blobs/\(sha)"))
            try Self.check(response)
            struct Blob: Decodable { let sha: String; let size: Int; let encoding: String; let content: String }
            let blob = try JSONDecoder().decode(Blob.self, from: response.data)
            guard blob.sha == sha, blob.encoding == "base64", blob.size == entry.size,
                  blob.size >= 0, blob.size <= RepositoryScanPolicy.maximumFileBytes,
                  let data = Data(base64Encoded: blob.content, options: .ignoreUnknownCharacters), data.count == blob.size,
                  let text = String(data: data, encoding: .utf8), !text.contains("\0") else { throw GroveError.invalidResponse }
            return (text, data.count)
        }
        for (index, entry) in large.enumerated() {
            try Task.checkCancellation()
            do {
                guard byteCount + (entry.size ?? 0) <= RepositoryScanPolicy.maximumTotalBytes else { throw GroveError.invalidResponse }
                let full = try await readFullBlob(entry)
                files[entry.path] = full.text; byteCount += full.bytes
            } catch {
                try Task.checkCancellation()
                if let error = error as? GroveError, [.stalePreview, .loginRequired, .commandFailed(403), .commandFailed(429)].contains(error) { throw error }
                unread += 1
            }
            await progress?(index + 1, selected.count)
        }
        for offset in stride(from: 0, to: batched.count, by: 25) {
            try Task.checkCancellation()
            let batch = Array(batched[offset..<min(offset + 25, batched.count)])
            // JSON string encoding escapes repository paths inside the GraphQL document.
            func quoted(_ string: String) throws -> String { String(decoding: try JSONEncoder().encode(string), as: UTF8.self) }
            let fields = try batch.enumerated().map { index, entry in
                "f\(index): object(expression: \(try quoted(tree.sha + ":" + entry.path))) { ... on Blob { text byteSize isBinary } }"
            }.joined(separator: "\n")
            let query = "query { repository(owner: \(try quoted(repo.owner.login)), name: \(try quoted(repo.name))) { databaseId \(fields) } }"
            let body = try JSONSerialization.data(withJSONObject: ["query": query])
            let repository: ServiceJSON
            do {
                let result = try await transport.send(APIRequest(path: "graphql", method: "POST", body: body))
                try Self.check(result)
                let json = try JSONDecoder().decode(ServiceJSON.self, from: result.data)
                repository = json["data"]["repository"]
                guard let identifier = repository["databaseId"].number else { throw GroveError.invalidResponse }
                guard identifier == Double(repo.id) else { throw GroveError.stalePreview }
            } catch {
                try Task.checkCancellation()
                if let error = error as? GroveError, [.stalePreview, .loginRequired, .commandFailed(403), .commandFailed(429)].contains(error) { throw error }
                unread += batch.count
                await progress?(min(large.count + offset + batch.count, selected.count), selected.count)
                continue
            }
            for (index, entry) in batch.enumerated() {
                let blob = repository["f\(index)"]
                if blob["isBinary"].bool == false, let text = blob["text"].string,
                   let size = blob["byteSize"].number, size >= 0, size <= Double(RepositoryScanPolicy.maximumFileBytes),
                   text.utf8.count == Int(size), !text.contains("\0") {
                    guard byteCount + text.utf8.count <= RepositoryScanPolicy.maximumTotalBytes else { unread += 1; continue }
                    files[entry.path] = text; byteCount += text.utf8.count
                } else {
                    // Bulk text can be missing, normalized or truncated. Verify the original pinned bytes.
                    do {
                        guard byteCount + (entry.size ?? 0) <= RepositoryScanPolicy.maximumTotalBytes else { throw GroveError.invalidResponse }
                        let full = try await readFullBlob(entry)
                        files[entry.path] = full.text; byteCount += full.bytes
                    } catch {
                        try Task.checkCancellation()
                        if let error = error as? GroveError, [.stalePreview, .loginRequired, .commandFailed(403), .commandFailed(429)].contains(error) { throw error }
                        unread += 1
                    }
                }
            }
            await progress?(min(large.count + offset + batch.count, selected.count), selected.count)
            if byteCount >= RepositoryScanPolicy.maximumTotalBytes { unread += max(0, batched.count - offset - batch.count); break }
        }
        if unread > 0 { limitations.append("\(unread) eligible files were unreadable, binary, or beyond the total text limit.") }
        let submodules = tree.tree.filter { $0.type == "commit" }.count
        if submodules > 0 { limitations.append("\(submodules) linked submodules were not read.") }
        return RepositorySnapshot(revision: tree.sha, files: files, eligibleFiles: eligible.count,
                                  excludedFiles: blobs.count - eligible.count, totalFiles: blobs.count, limitations: limitations)
    }
}
