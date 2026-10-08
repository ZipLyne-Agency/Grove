import Foundation
import Darwin

/// Holds the workspace's writer lock for the entire app or setup process.
public final class WorkspaceLease {
    private let descriptor: Int32
    public init(directory: URL? = nil) throws {
        let folder = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Grove")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = Darwin.open(folder.appendingPathComponent("workspace.lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw WorkspaceError.workspaceBusy }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            throw WorkspaceError.workspaceBusy
        }
        self.descriptor = descriptor
    }
    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}
