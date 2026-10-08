import AppKit
import Observation
import GroveCore

@MainActor @Observable
final class WorkspaceStore {
    var archive = WorkspaceArchive()
    var destination: WorkspaceDestination = .library
    var selectedProjectID: UUID?
    var selectedConnectionID: UUID?
    var projectTab: ProjectTab = .overview
    var loading = false
    var error: String?
    var notice: String?
    var persistenceBlocked = false
    var syncing: Set<UUID> = []
    var discovering = false
    var enrichment = LibraryEnrichmentProgress()
    var enrichmentTask: Task<Void, Never>?
    var suggestions: [ServiceSuggestion] = []
    var resources: [ProviderResource] = []
    var loadingResources = false
    var resourceAccountID: UUID?
    private var resourceRequestID = UUID()
    var renameReview: ProviderRenameReview?
    var preparingRename = false
    var renaming = false
    let provider: ProviderService
    let vault: any CredentialVault
    let persistence: WorkspacePersistence
    private let persists: Bool
    private var accountRevisions: [UUID: Int] = [:]
    private var saveTask: Task<Void, Never>?
    private var saveRevision = 0
    private var syncTasks: [UUID: Task<Void, Never>] = [:]
    private var stopped = false
    var projects: [GroveProject] { archive.projects.sorted { $0.pinned != $1.pinned ? $0.pinned : $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var connections: [ServiceConnection] { archive.connections }
    var accounts: [ProviderAccount] { archive.accounts }
    var selectedProject: GroveProject? { archive.projects.first { $0.id == selectedProjectID } }
    var selectedConnection: ServiceConnection? { archive.connections.first { $0.id == selectedConnectionID } }
    var hasRemoteReview: Bool { renameReview != nil || preparingRename || renaming }
    var repositoryOperationActive: (() -> Bool)?
    var canEdit: Bool { !(repositoryOperationActive?() ?? false) && !loading && !persistenceBlocked && renameReview == nil && !preparingRename && !renaming }
    init(load: Bool = true, provider: ProviderService = ProviderService(), vault: any CredentialVault = KeychainVault(), persistence: WorkspacePersistence? = nil) {
        self.provider = provider; self.vault = vault
        self.persistence = persistence ?? WorkspacePersistence(vault: vault); persists = load; loading = load
        if load { Task { await reload() } }
    }
    func reload() async {
        do {
            let loaded = try await persistence.load()
            archive = loaded
            archive.useRepositoryLibrary()
            for index in archive.connections.indices { archive.connections[index].useAsSavedLink() }
            persistenceBlocked = false
            if archive != loaded { changed() }
        }
        catch { self.error = error.localizedDescription; persistenceBlocked = true }
        loading = false
    }
    func connections(for repositoryID: Int) -> [ServiceConnection] { archive.connections(for: repositoryID) }
    func connections(for project: GroveProject) -> [ServiceConnection] {
        archive.connections.filter { $0.projectIDs.contains(project.id) || !$0.repositoryIDs.isDisjoint(with: project.repositoryIDs) }
    }
    func account(for connection: ServiceConnection) -> ProviderAccount? { accounts.first { $0.id == connection.accountID } }
    func saveProject(_ project: GroveProject) {
        guard canEdit else { return }
        let name = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 128, project.notes.count <= 8000 else { error = "Enter a project name up to 128 characters and notes up to 8,000 characters."; return }
        var next = project; next.name = name; next.updatedAt = Date()
        if let index = archive.projects.firstIndex(where: { $0.id == project.id }) { archive.projects[index] = next }
        else { archive.projects.append(next) }
        changed()
    }
    func removeProject(_ id: UUID) {
        guard canEdit else { return }; archive.removeProject(id)
        if selectedProjectID == id { selectedProjectID = nil; destination = .library }; changed()
    }
    func saveConnection(_ connection: ServiceConnection) {
        guard canEdit else { return }
        do {
            try ServiceCatalog.validate(connection, accounts: accounts)
            if let accountID = connection.accountID { guard accounts.contains(where: { $0.id == accountID && $0.provider == connection.provider }) else { throw WorkspaceError.invalidInput("Choose an account for this provider.") } }
            syncTasks[connection.id]?.cancel()
            var next = connection; next.lastError = nil; next.authorizationFailed = false
            if let old = connections.first(where: { $0.id == next.id }), old.dashboardURL != next.dashboardURL {
                next.dashboardOverride = !next.dashboardURL.isEmpty
            }
            if let old = connections.first(where: { $0.id == connection.id }), old.resourceID != next.resourceID || old.accountID != next.accountID || old.provider != next.provider { next.snapshot = nil; next.lastAttemptAt = nil }
            if next.dashboardURL.isEmpty { next.dashboardURL = ServiceCatalog.dashboard(provider: next.provider, resourceID: next.resourceID, scope: account(for: next)?.scope ?? "") }
            if let index = archive.connections.firstIndex(where: { $0.id == next.id }) { archive.connections[index] = next }
            else { archive.connections.append(next) }
            changed()
        } catch { self.error = error.localizedDescription }
    }
    func removeConnection(_ id: UUID) {
        guard canEdit else { return }; syncTasks[id]?.cancel(); archive.connections.removeAll { $0.id == id }
        if selectedConnectionID == id { selectedConnectionID = nil }; changed()
    }
    func saveAccount(_ account: ProviderAccount, credential: String) async -> Bool {
        guard canEdit else { return false }
        do {
            try ServiceCatalog.validate(account)
            if let old = accounts.first(where: { $0.id == account.id }), old.provider != account.provider {
                throw WorkspaceError.invalidInput("Create a separate account for a different provider.")
            }
            if !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard credential.utf8.count <= 65536 else { throw WorkspaceError.invalidInput("The credential is too large.") }
                try vault.write(Data(credential.utf8), id: account.id.uuidString)
            } else if try vault.read(account.id.uuidString) == nil { throw WorkspaceError.missingCredential }
            accountRevisions[account.id, default: 0] += 1
            if let index = archive.accounts.firstIndex(where: { $0.id == account.id }) { archive.accounts[index] = account }
            else { archive.accounts.append(account) }
            for index in archive.connections.indices where archive.connections[index].accountID == account.id {
                syncTasks[archive.connections[index].id]?.cancel(); archive.connections[index].snapshot = nil
                archive.connections[index].authorizationFailed = false; archive.connections[index].lastError = nil
            }
            clearResources(); changed()
            await provider.invalidateAccount(account.id)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func removeAccount(_ id: UUID) async {
        guard canEdit else { return }
        do {
            try vault.delete(id.uuidString)
            accountRevisions[id, default: 0] += 1
            archive.accounts.removeAll { $0.id == id }
            for index in archive.connections.indices where archive.connections[index].accountID == id {
                syncTasks[archive.connections[index].id]?.cancel(); archive.connections[index].accountID = nil
                archive.connections[index].snapshot = nil; archive.connections[index].authorizationFailed = false
                archive.connections[index].lastError = nil; archive.connections[index].lastAttemptAt = nil
            }
            clearResources(); changed()
            await provider.invalidateAccount(id)
        } catch { self.error = error.localizedDescription }
    }
    func sync(_ id: UUID) async {
        guard !stopped, canEdit, !syncing.contains(id), let connection = connections.first(where: { $0.id == id }),
              connection.provider.supportsAPI, let account = account(for: connection) else { return }
        let accountRevision = accountRevisions[account.id, default: 0]
        syncing.insert(id)
        defer { syncing.remove(id) }
        do {
            guard let credential = try vault.read(account.id.uuidString) else { throw WorkspaceError.missingCredential }
            let snapshot = try await provider.fetch(connection, account: account, credential: credential)
            guard !stopped, !Task.isCancelled, accountRevision == accountRevisions[account.id, default: 0], let index = currentIndex(connection, account) else { return }
            archive.connections[index].snapshot = snapshot; archive.connections[index].resourceID = snapshot.resourceID
            if archive.connections[index].dashboardOverride != true, let dashboard = snapshot.dashboardURL, ServiceCatalog.safeURL(dashboard) != nil { archive.connections[index].dashboardURL = dashboard }
            archive.connections[index].lastError = nil
            archive.connections[index].authorizationFailed = false; archive.connections[index].lastAttemptAt = Date(); changed()
        } catch {
            guard !stopped, !Task.isCancelled, accountRevision == accountRevisions[account.id, default: 0], let index = currentIndex(connection, account) else { return }
            archive.connections[index].lastError = error.localizedDescription
            archive.connections[index].authorizationFailed = (error as? WorkspaceError).map { [.authorization, .missingCredential].contains($0) } ?? false
            archive.connections[index].lastAttemptAt = Date(); changed()
        }
    }
    private func currentIndex(_ connection: ServiceConnection, _ account: ProviderAccount) -> Int? {
        guard accounts.contains(account) else { return nil }
        return archive.connections.firstIndex { $0 == connection }
    }
    func requestSync(_ id: UUID) { guard syncTasks[id] == nil else { return }; syncTasks[id] = Task { await sync(id); syncTasks[id] = nil } }
    func syncAll(force: Bool = false) async {
        for item in connections where item.provider.supportsAPI && !item.authorizationFailed {
            guard !Task.isCancelled, canEdit else { return }
            if !force, let attempted = item.lastAttemptAt, Date().timeIntervalSince(attempted) < (item.lastError == nil ? 300 : 900) { continue }
            await sync(item.id)
        }
    }
    func loadResources(_ account: ProviderAccount) async {
        guard canEdit, accounts.contains(account) else { return }
        let requestID = UUID(), revision = accountRevisions[account.id, default: 0]
        resourceRequestID = requestID; resourceAccountID = account.id
        loadingResources = true; resources = []
        defer { if resourceRequestID == requestID { loadingResources = false } }
        do {
            guard let credential = try vault.read(account.id.uuidString) else { throw WorkspaceError.missingCredential }
            let result = try await provider.resources(account: account, credential: credential)
            guard resourceRequestID == requestID, accounts.contains(account), revision == accountRevisions[account.id, default: 0] else { return }
            resources = result
            notice = "Showing the first provider page, up to 200 resources. You can also enter an exact resource ID."
        } catch { if resourceRequestID == requestID { self.error = error.localizedDescription } }
    }
    func clearResources() {
        resourceRequestID = UUID(); resourceAccountID = nil; resources = []; loadingResources = false
    }
    func discover(_ repo: Repository, using github: GitHubService) async {
        guard !discovering else { return }; discovering = true; suggestions = []
        defer { discovering = false }
        do {
            let files = try await github.serviceConfiguration(repo)
            var found = ServiceDiscovery.inspect(repository: repo, files: files)
            if Intelligence.available {
                do {
                    let inferred = try await Intelligence.findServices(repo: repo, files: files)
                    for item in inferred where !found.contains(where: { $0.provider != .custom && $0.provider == item.provider || $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) { found.append(item) }
                    notice = "Scanned with the on-device assistant. Review the services and links before adding them."
                } catch is CancellationError { throw CancellationError() }
                catch { notice = "The assistant could not finish. Showing services found directly in configuration instead." }
            } else { notice = "Apple Intelligence is unavailable. Showing services found directly in configuration." }
            try Task.checkCancellation()
            suggestions = found
        }
        catch { self.error = error.localizedDescription }
    }
    func prepareRename(_ connection: ServiceConnection, name: String) async {
        guard canEdit, syncing.isEmpty, let account = account(for: connection) else { return }
        preparingRename = true; defer { preparingRename = false }
        do {
            guard let credential = try vault.read(account.id.uuidString) else { throw WorkspaceError.missingCredential }
            let review = try await provider.prepareRename(connection, account: account, credential: credential, name: name)
            guard currentIndex(connection, account) != nil else { await provider.cancel(review.id); throw WorkspaceError.staleReview }
            renameReview = review
        } catch { self.error = error.localizedDescription }
    }
    func cancelRename() { if let review = renameReview { Task { await provider.cancel(review.id) } }; renameReview = nil }
    func confirmRename() async {
        guard let review = renameReview, !renaming, let index = currentIndex(review.connection, review.account) else { return }
        renaming = true; defer { renaming = false }; renameReview = nil
        do {
            guard let credential = try vault.read(review.account.id.uuidString) else { throw WorkspaceError.missingCredential }
            let snapshot = try await provider.approveRename(review.id, credential: credential)
            archive.connections[index].snapshot = snapshot; archive.connections[index].name = snapshot.name
            archive.connections[index].resourceID = snapshot.resourceID
            if archive.connections[index].dashboardOverride != true, let dashboard = snapshot.dashboardURL, ServiceCatalog.safeURL(dashboard) != nil { archive.connections[index].dashboardURL = dashboard }
            archive.connections[index].lastAttemptAt = Date(); archive.connections[index].authorizationFailed = false
            archive.connections[index].lastError = nil; changed(); notice = "Service name updated and verified."
        } catch { self.error = error.localizedDescription; archive.connections[index].lastError = error.localizedDescription; changed() }
    }
    func open(_ connection: ServiceConnection) {
        guard let url = ServiceCatalog.safeURL(connection.dashboardURL) else { error = "Add a valid HTTPS dashboard URL."; return }; NSWorkspace.shared.open(url)
    }
    func copy(_ connection: ServiceConnection) { Clipboard.copy(connection.dashboardURL); notice = "Copied" }
    func changed() {
        guard persists, !persistenceBlocked else { return }
        saveRevision += 1
        let snapshot = archive, previous = saveTask, persistence = persistence
        saveTask = Task {
            await previous?.value
            guard !self.persistenceBlocked else { return }
            do { try await persistence.save(snapshot) }
            catch { self.error = error.localizedDescription; persistenceBlocked = true }
        }
    }
    func flush() async {
        while let task = saveTask {
            let revision = saveRevision
            await task.value
            if revision == saveRevision { return }
        }
    }
    func stop() { stopped = true; enrichmentTask?.cancel(); syncTasks.values.forEach { $0.cancel() }; clearResources() }
}
