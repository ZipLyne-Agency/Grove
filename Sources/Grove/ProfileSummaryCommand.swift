import Foundation
import GroveCore

/// Read-only local diagnostics. Prints coverage metadata only, never descriptions, source, URLs or credentials.
enum ProfileSummaryCommand {
    private struct Summary: Encodable {
        struct Partial: Encodable { let repository: String; let read: Int; let eligible: Int; let limitations: [String] }
        let profiles: Int
        let generatedDescriptions: Int
        let fallbackDescriptions: Int
        let editedDescriptions: Int
        let integrationReferences: Int
        let filesRead: Int
        let partial: [Partial]
    }
    static func run() -> Never {
        Task.detached {
            do {
                let archive = try await WorkspacePersistence().load()
                let profiles = Array((archive.repositoryProfiles ?? [:]).values)
                let generated = profiles.filter { $0.descriptionSource == "Apple Intelligence" }.count
                let edited = profiles.filter { $0.descriptionSource == "Edited in Grove" }.count
                let summary = Summary(profiles: profiles.count, generatedDescriptions: generated,
                                      fallbackDescriptions: profiles.count - generated - edited, editedDescriptions: edited,
                                      integrationReferences: profiles.reduce(0) { $0 + $1.visibleIntegrations.filter { !$0.documentationOnly }.count },
                                      filesRead: profiles.reduce(0) { $0 + $1.scannedFiles },
                                      partial: profiles.filter { !$0.complete }.sorted { $0.fullName < $1.fullName }.map {
                                          Summary.Partial(repository: $0.fullName, read: $0.scannedFiles, eligible: $0.eligibleFiles, limitations: $0.limitations)
                                      })
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(summary)); print("")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("The saved profile summary could not be read.\n".utf8)); exit(1)
            }
        }
        dispatchMain()
    }
}
