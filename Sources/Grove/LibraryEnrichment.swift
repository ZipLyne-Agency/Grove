import Foundation
import GroveCore

struct LibraryEnrichmentProgress {
    var total = 0
    var completed = 0
    var succeeded = 0
    var failed = 0
    var partial = 0
    var currentRepository = ""
    var filesRead = 0
    var filesTotal = 0
    var phase = ""
    var running = false
    var failures: [Int: String] = [:]
}

extension WorkspaceStore {
    func profile(for repositoryID: Int) -> RepositoryProfile? { archive.repositoryProfiles?[String(repositoryID)] }
    func saveProfile(_ profile: RepositoryProfile) {
        guard !persistenceBlocked, !loading else { return }
        var profile = profile
        if let saved = self.profile(for: profile.repositoryID), saved.descriptionSource == "Edited in Grove" {
            profile.summary = saved.summary; profile.overview = saved.overview; profile.descriptionSource = saved.descriptionSource
        }
        if let saved = self.profile(for: profile.repositoryID) {
            profile.hiddenIntegrationIDs = saved.hiddenIntegrationIDs
        }
        if archive.repositoryProfiles == nil { archive.repositoryProfiles = [:] }
        archive.repositoryProfiles?[String(profile.repositoryID)] = profile
        changed()
    }
    func updateDescription(repositoryID: Int, summary: String, overview: String) {
        guard canEdit, var profile = profile(for: repositoryID) else { return }
        profile.summary = RepositoryAnalyzer.clean(summary, maximum: 350)
        profile.overview = RepositoryAnalyzer.clean(overview, maximum: 4000)
        profile.descriptionSource = "Edited in Grove"
        saveProfile(profile)
    }
    func setIntegrationHidden(repositoryID: Int, integrationID: String, hidden: Bool) {
        guard canEdit, var profile = profile(for: repositoryID),
              profile.integrations.contains(where: { $0.id == integrationID }) else { return }
        var ids = profile.hiddenIntegrationIDs ?? []
        if hidden { ids.insert(integrationID) } else { ids.remove(integrationID) }
        profile.hiddenIntegrationIDs = ids
        archive.repositoryProfiles?[String(repositoryID)] = profile
        changed()
    }
    func startEnrichment(repositories: [Repository], using github: GitHubService, onlyMissing: Bool = true, onChange: @escaping @MainActor () -> Void = {}) {
        guard canEdit, !enrichment.running, !repositories.isEmpty else { return }
        let queue = repositories.filter { !onlyMissing || profile(for: $0.id) == nil }
        guard !queue.isEmpty else { notice = "Every repository has a saved profile. Choose Refresh All Profiles to scan again."; return }
        enrichment = LibraryEnrichmentProgress(total: queue.count, running: true)
        enrichmentTask = Task { [weak self] in
            guard let self else { return }
            defer { self.enrichment.running = false; self.enrichmentTask = nil }
            for repo in queue {
                if self.persistenceBlocked { self.enrichment.phase = "Stopped because the workspace could not be saved."; break }
                if Task.isCancelled { self.enrichment.phase = "Stopped. Completed profiles are saved."; break }
                self.enrichment.currentRepository = repo.full_name
                self.enrichment.filesRead = 0; self.enrichment.filesTotal = 0
                self.enrichment.phase = "Reading repository files"
                do {
                    let profile = try await RepositoryAnalyzer.analyze(repo, using: github) { [weak self] read, total in
                        await MainActor.run {
                            self?.enrichment.filesRead = read; self?.enrichment.filesTotal = total
                            if read == total { self?.enrichment.phase = "Analyzing source and generating description" }
                        }
                    }
                    try Task.checkCancellation()
                    self.saveProfile(profile)
                    await self.flush()
                    if self.persistenceBlocked { throw WorkspaceError.invalidInput("The repository profile could not be saved.") }
                    self.enrichment.succeeded += 1
                    if !profile.complete { self.enrichment.partial += 1 }
                    onChange()
                } catch is CancellationError {
                    self.enrichment.phase = "Stopped. Completed profiles are saved."; break
                } catch {
                    if Task.isCancelled { self.enrichment.phase = "Stopped. Completed profiles are saved."; break }
                    self.enrichment.failed += 1
                    self.enrichment.failures[repo.id] = (error as? GroveError)?.localizedDescription ?? (error as? WorkspaceError)?.localizedDescription ?? "This repository could not be scanned."
                }
                self.enrichment.completed += 1
            }
            if !Task.isCancelled && !self.persistenceBlocked { self.enrichment.phase = "Finished" }
            self.notice = "\(self.enrichment.succeeded) repository profiles saved" + (self.enrichment.failed > 0 ? "; \(self.enrichment.failed) could not be scanned." : ".")
        }
    }
    func stopEnrichment() { enrichmentTask?.cancel() }
}

extension WorkspaceStore {
    func isRepositoryPinned(_ repositoryID: Int) -> Bool { archive.pinnedRepositoryIDs?.contains(repositoryID) == true }
    func toggleRepositoryPin(_ repositoryID: Int) {
        guard canEdit else { return }
        var pins = archive.pinnedRepositoryIDs ?? []
        if pins.contains(repositoryID) { pins.remove(repositoryID) } else { pins.insert(repositoryID) }
        archive.pinnedRepositoryIDs = pins; changed()
    }
}

extension Store {
    var localDescriptions: [Int: String] {
        Dictionary((workspace.archive.repositoryProfiles ?? [:]).values.map { ($0.repositoryID, $0.summary) }, uniquingKeysWith: { first, _ in first })
    }
    var localIntegrationNames: [Int: String] {
        Dictionary((workspace.archive.repositoryProfiles ?? [:]).values.map { ($0.repositoryID, $0.visibleIntegrations.filter { !$0.documentationOnly }.map(\.name).joined(separator: " ")) }, uniquingKeysWith: { first, _ in first })
    }
}
