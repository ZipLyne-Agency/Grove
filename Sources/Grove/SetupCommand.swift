import Foundation
import GroveCore

/// Optional local provisioning path. Credentials arrive on stdin, never in arguments or files.
enum SetupCommand {
    private struct AccountInput: Decodable, Sendable { let account: ProviderAccount; let credential: String }
    private struct Input: Decodable, Sendable {
        let accounts: [AccountInput]
        let projects: [GroveProject]
        let connections: [ServiceConnection]
    }
    static func run() -> Never {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        Task.detached {
            do {
                guard data.count <= 1_000_000 else { throw WorkspaceError.invalidInput("Setup input is too large.") }
                let input = try JSONDecoder().decode(Input.self, from: data)
                let vault = KeychainVault(), persistence = WorkspacePersistence()
                var archive = try await persistence.load()
                for item in input.accounts {
                    try ServiceCatalog.validate(item.account)
                    if let existing = archive.accounts.first(where: { $0.id == item.account.id }), existing.provider != item.account.provider {
                        throw WorkspaceError.invalidInput("Create a separate account for a different provider.")
                    }
                    guard !item.credential.isEmpty, item.credential.utf8.count <= 65536 else { throw WorkspaceError.missingCredential }
                }
                var merged = archive.accounts
                for item in input.accounts { merged.removeAll { $0.id == item.account.id }; merged.append(item.account) }
                for item in input.connections { try ServiceCatalog.validate(item, accounts: merged) }
                for project in input.projects {
                    guard !project.name.isEmpty, project.name.count <= 128, project.notes.count <= 8000 else { throw WorkspaceError.invalidInput("Invalid project.") }
                }
                for item in input.accounts { try vault.write(Data(item.credential.utf8), id: item.account.id.uuidString) }
                archive.accounts = merged
                let replaced = Set(input.accounts.map { $0.account.id })
                for index in archive.connections.indices where archive.connections[index].accountID.map(replaced.contains) == true {
                    archive.connections[index].snapshot = nil; archive.connections[index].lastError = nil
                    archive.connections[index].lastAttemptAt = nil; archive.connections[index].authorizationFailed = false
                }
                for item in input.projects { archive.projects.removeAll { $0.id == item.id }; archive.projects.append(item) }
                for item in input.connections { archive.connections.removeAll { $0.id == item.id }; archive.connections.append(item) }
                try await persistence.save(archive)
                print("Saved \(input.projects.count) projects, \(input.connections.count) connections, and \(input.accounts.count) credential accounts.")
                exit(0)
            } catch {
                // Decode errors can contain input fragments. Emit only our own redacted error vocabulary.
                let message = (error as? WorkspaceError)?.localizedDescription ?? "Setup input could not be read. No workspace changes were saved."
                FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1)
            }
        }
        dispatchMain()
    }
}
