import Foundation
import Darwin

public struct APIRequest: Sendable {
    public let path: String
    public let method: String
    public let body: Data?
    public init(path: String, method: String = "GET", body: Data? = nil) {
        self.path = path; self.method = method; self.body = body
    }
}
public struct APIResponse: Sendable {
    public let status: Int
    public let data: Data
    public init(status: Int, data: Data) { self.status = status; self.data = data }
}
public protocol GitHubTransport: Sendable { func send(_ request: APIRequest) async throws -> APIResponse }

/// Fixed executable, no shell. A dedicated queue handles blocking pipe IO; cancellation stops its exact child.
public struct CLITransport: GitHubTransport {
    public init() {}
    public func send(_ request: APIRequest) async throws -> APIResponse {
        let runner = CLIRunner()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { continuation.resume(returning: try runner.run(request)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { runner.cancel() }
    }
    static func parse(_ data: Data, method: String, exitCode: Int32) throws -> APIResponse {
        guard let text = String(data: data, encoding: .utf8) else { throw GroveError.invalidResponse }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard let separator = normalized.range(of: "\n\n"),
              let line = normalized.split(separator: "\n").first, line.hasPrefix("HTTP/"),
              let statusText = line.split(separator: " ").dropFirst().first,
              let status = Int(statusText), (100...599).contains(status) else {
            if exitCode == 4 { throw GroveError.loginRequired }
            if method != "GET" { throw GroveError.outcomeUnknown }
            throw exitCode == 0 ? GroveError.invalidResponse : GroveError.transportFailure
        }
        return APIResponse(status: status, data: Data(normalized[separator.upperBound...].utf8))
    }
}

/// Lock protects process lifecycle across the IO queue, deadline callback, and cancellation callback.
private final class CLIRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false
    func cancel(timeout: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        cancelled = true; timedOut = timedOut || timeout
        guard let process, process.isRunning else { return }
        process.terminate()
        // gh should terminate on SIGTERM. Escalate only this owned child if it does not.
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            self.lock.lock(); defer { self.lock.unlock() }
            if let child = self.process, child === process, child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
        }
    }
    func run(_ request: APIRequest) throws -> APIResponse {
        let paths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        guard let binary = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw GroveError.missingCLI }
        guard !request.path.hasPrefix("/"), !request.path.contains("://"),
              ["GET", "PATCH", "POST", "DELETE"].contains(request.method) else { throw GroveError.invalidResponse }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: binary)
        var args = ["api", "--hostname", "github.com", "--include", "--method", request.method,
                    "-H", "Accept: application/vnd.github+json", request.path]
        if request.body != nil { args += ["-H", "Content-Type: application/json", "--input", "-"] }
        child.arguments = args
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "GH_DEBUG"); environment.removeValue(forKey: "GH_TOKEN")
        environment.removeValue(forKey: "GITHUB_TOKEN"); environment.removeValue(forKey: "GH_API_HOST")
        environment["GH_PROMPT_DISABLED"] = "1"; environment["GH_PAGER"] = "cat"
        child.environment = environment
        let output = Pipe(), errors = Pipe(), input = Pipe()
        child.standardOutput = output; child.standardError = errors; child.standardInput = input
        // Protect the GUI process when gh closes stdin early.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try child.run(); process = child; lock.unlock() }
        catch { lock.unlock(); throw error }
        let limit = DispatchWorkItem { self.cancel(timeout: true) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: limit)
        let errorReader = DispatchGroup()
        errorReader.enter()
        DispatchQueue.global().async { _ = errors.fileHandleForReading.readDataToEndOfFile(); errorReader.leave() }
        var inputFailed = false
        do { if let body = request.body { try input.fileHandleForWriting.write(contentsOf: body) } }
        catch { inputFailed = true; cancel() }
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        child.waitUntilExit(); limit.cancel(); errorReader.wait()
        lock.lock()
        let wasCancelled = cancelled, wasTimedOut = timedOut
        process = nil
        lock.unlock()
        if inputFailed || wasCancelled || child.terminationReason == .uncaughtSignal {
            if request.method != "GET" { throw GroveError.outcomeUnknown }
            if wasTimedOut { throw GroveError.timeout }
            throw CancellationError()
        }
        return try CLITransport.parse(data, method: request.method, exitCode: child.terminationStatus)
    }
}
