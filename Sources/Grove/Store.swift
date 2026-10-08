import AppKit
import Observation
import GroveCore

@MainActor @Observable
final class Store {
    let workspace: WorkspaceStore
    let service: GitHubService
    let cache: InventoryCache
    let preferences: UserDefaults
    var hiddenOwners: Set<String>
    var inventory: Inventory?
    var scope: LibraryScope = .all
    var owner: String?
    var search = ""
    var sort: RepositorySort = .pushed {
        didSet { preferences.set(sort.rawValue, forKey: "repositorySort") }
    }
    var visible: [Repository] = []
    var selectedID: Int?
    var busy = false
    var preparing = false
    var operationInFlight = false
    var mutationInFlight = false
    var suggestion: AssistantSuggestion?
    var needsRefresh: Bool { inventory?.requiresRefresh == true }
    var canStartReview: Bool { !workspace.hasRemoteReview && !busy && !preparing && !operationInFlight && consent == nil && preview == nil && editor == nil }
    var message: String?
    var lastAction: String?
    var consent: Consent?
    var preview: ActionPreview?
    var editor: EditorRequest?
    var showAssistant = false
    var assistantPrompt = ""
    var assistantOwner: String?
    var assistantScope: LibraryScope = .all
    var assistantAnswer = ""
    var assistantError: String?
    var assistantQuestion: String?
    var assistantProjectID: UUID?
    var assistantServices: [ServiceConnection] = []
    var assistantOpenServices: [ServiceConnection] = []
    var assistantContext: Inventory?
    var assistantSubject: String?
    var assistantFocus: AssistantFocus = .repository
    var assistantBusy = false
    var loadingCache = false
    var counts = LibraryCounts()
    var assistantTask: Task<Void, Never>?
    var operationTask: Task<Void, Never>?
    var queryTask: Task<Void, Never>?
    var queryRevision = 0
    var selected: Repository? { inventory?.repositories.first { $0.id == selectedID } }
    var allOwners: [String] { Array(Set((inventory?.repositories.map(\.owner.login) ?? []) + (inventory?.organizations.map(\.login) ?? []))).sorted() }
    var owners: [String] { allOwners.filter { !hiddenOwners.contains($0) } }
    var destinations: [String] { inventory?.organizations.map(\.login).sorted() ?? [] }
    var title: String { owner ?? scope.rawValue }
    init(service: GitHubService = GitHubService(), cache: InventoryCache = InventoryCache(), loadCache: Bool = true, preferences: UserDefaults = .standard) {
        workspace = WorkspaceStore(load: loadCache)
        self.service = service; self.cache = cache
        self.preferences = preferences
        sort = preferences.string(forKey: "repositorySort").flatMap(RepositorySort.init(rawValue:)) ?? .pushed
        hiddenOwners = Set(preferences.stringArray(forKey: "hiddenOwners") ?? [])
        loadingCache = loadCache
        workspace.repositoryOperationActive = { [weak self] in
            guard let self else { return true }; return self.busy || self.preparing || self.operationInFlight || self.preview != nil || self.editor != nil || self.consent != nil
        }
        if loadCache { Task {
            let cached = await cache.load()
            loadingCache = false
            guard inventory == nil, !busy else { return }
            inventory = cached
            rebuild()
        } }
    }
    func rebuild() {
        queryTask?.cancel()
        queryRevision += 1
        let revision = queryRevision
        let all = inventory?.repositories ?? []
        let repos = all.filter { !hiddenOwners.contains($0.owner.login) }, scope = scope, owner = owner, search = search, sort = sort
        queryTask = Task {
            let (results, totals) = await Task.detached(priority: .userInitiated) {
                (RepositoryQuery.filter(repos, scope: scope, owner: owner, search: search, sort: sort), LibraryCounts(visible: repos, all: all))
            }.value
            guard !Task.isCancelled, revision == queryRevision else { return }
            visible = results
            counts = totals
            if !results.contains(where: { $0.id == selectedID }) { selectedID = results.first?.id }
        }
    }
    func requestRefresh() {
        guard canStartReview else { return }
        operationInFlight = true
        operationTask = Task {
            await refresh(); operationInFlight = false
        }
    }
    func refresh() async {
        guard !busy else { return }
        busy = true; message = nil; lastAction = nil
        defer { busy = false }
        do {
            let next = try await service.inventory()
            inventory = next; rebuild()
            do { try await cache.save(next) } catch { message = "Repositories loaded, but the local cache could not be saved." }
        } catch { message = error.localizedDescription }
    }
    func requestOpen(_ repo: Repository) {
        if let url = repo.webURL { NSWorkspace.shared.open(url) }
    }
    func requestEdit(_ repo: Repository, kind: EditorKind) {
        guard canStartReview, !needsRefresh else { return }; editor = EditorRequest(repo: repo, kind: kind)
    }
    func prepare(_ repo: Repository, action: RepositoryAction) async {
        guard let inventory, !busy, !preparing, !operationInFlight, !workspace.hasRemoteReview else { message = "Finish the current operation before reviewing another change."; return }
        guard preview == nil, consent == nil, editor == nil else { message = "Finish the current review before starting another change."; return }
        guard !needsRefresh else { message = "Refresh GitHub before reviewing another change."; return }
        preparing = true
        defer { preparing = false }
        do { preview = try await service.prepare(repo: repo, action: action, inventory: inventory) }
        catch { message = error.localizedDescription }
    }
    func cancelPreview() {
        if let preview { Task { await service.cancel(preview.id) } }
        preview = nil
    }
    func confirmPreview(_ current: ActionPreview, typedName: String) {
        guard !operationInFlight, !busy, preview?.id == current.id else { return }
        operationInFlight = true; mutationInFlight = true
        operationTask = Task {
            defer { operationInFlight = false; mutationInFlight = false }
            await execute(current, typedName: typedName)
        }
    }
    func execute(_ current: ActionPreview, typedName: String) async {
        guard !busy, preview?.id == current.id else { return }
        busy = true; message = nil; lastAction = nil
        preview = nil
        defer { busy = false }
        do {
            let result = try await service.approve(current.id, typedName: typedName)
            var updated: Repository?
            var uncertain = false
            switch result {
            case .verified(let repo):
                updated = repo
                lastAction = "\(current.action.title) completed and verified."
            case .transferRequested:
                uncertain = true
                lastAction = "Transfer requested. GitHub processes transfers asynchronously. Refresh to verify the new owner."
            case .acceptedUnverified:
                uncertain = true
                lastAction = "GitHub accepted the change. Its final state could not be verified. Refresh before taking another action."
            }
            await updateSnapshot(for: current, updated: updated, uncertain: uncertain)
        } catch {
            message = error.localizedDescription
            if let failure = error as? GroveError, [.outcomeUnknown, .timeout, .transportFailure].contains(failure) {
                await updateSnapshot(for: current, updated: nil, uncertain: true)
            }
        }
    }
    private func updateSnapshot(for current: ActionPreview, updated: Repository?, uncertain: Bool) async {
        guard let inventory else { return }
        var repos = inventory.repositories
        if !uncertain {
            repos.removeAll { $0.id == current.repository.id }
            if let updated { repos.append(updated) }
        }
        let next = Inventory(account: inventory.account, organizations: inventory.organizations, repositories: repos,
                             fetchedAt: inventory.fetchedAt, requiresRefresh: uncertain)
        self.inventory = next; rebuild()
        do { try await cache.save(next) }
        catch { message = "The local snapshot could not be saved. Refresh GitHub before taking another action." }
    }
    func reviewSuggestion() {
        guard let suggestion else { return }
        Task { await prepare(suggestion.repo, action: suggestion.action) }
    }

    func confirmConsent(_ item: Consent) {
        guard consent?.id == item.id, !busy else { return }
        consent = nil
        switch item.kind {
        case .refresh:
            operationInFlight = true
            operationTask = Task {
                defer { operationInFlight = false }
                await refresh()
            }
        case .open(let repo): if let url = repo.webURL { NSWorkspace.shared.open(url) }
        case .assistant(let prompt, let repo, let context): runAssistant(prompt, repo: repo, context: context)
        case .ownerVisibility(let login, let hidden):
            if hidden { hiddenOwners.insert(login) } else { hiddenOwners.remove(login) }
            preferences.set(hiddenOwners.sorted(), forKey: "hiddenOwners")
            if hidden, owner == login { owner = nil }
            rebuild()
        case .url(let url): NSWorkspace.shared.open(url)
        case .copy(let text): Clipboard.copy(text)
        }
    }
    func requestOwnerVisibility(_ login: String, hidden: Bool) {
        guard canStartReview else { return }
        if hidden { hiddenOwners.insert(login) } else { hiddenOwners.remove(login) }
        preferences.set(hiddenOwners.sorted(), forKey: "hiddenOwners")
        if hidden, owner == login { owner = nil }
        rebuild()
        lastAction = hidden ? "Owner Hidden" : "Owner Restored"
    }
    func requestOwnerPage(_ login: String, settings: Bool = false) {
        let encoded = ServiceCatalog.component(login)
        if let url = URL(string: settings ? "https://github.com/organizations/\(encoded)/settings/profile" : "https://github.com/\(encoded)") { NSWorkspace.shared.open(url) }
    }
    func requestCopy(_ text: String) { Clipboard.copy(text); lastAction = "Copied" }
    func requestAssistant() {
        let project = workspace.projects.first { $0.id == assistantProjectID }
        requestAssistant(assistantPrompt, repo: assistantFocus == .repository ? selected : nil, owner: assistantOwner, libraryScope: assistantScope, project: project)
    }
    func requestProjectAssistant(_ prompt: String, project: GroveProject) {
        requestAssistant(prompt, project: project)
    }
    func requestAssistant(_ prompt: String, repo: Repository? = nil, owner: String? = nil, libraryScope: LibraryScope = .all, project: GroveProject? = nil) {
        guard canStartReview, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !assistantBusy else { return }
        assistantProjectID = project?.id
        let candidates = (inventory?.repositories ?? []).filter {
            if let project { return project.repositoryIDs.contains($0.id) }
            if let owner { return $0.owner.login == owner }
            return $0.id == repo?.id || !hiddenOwners.contains($0.owner.login)
        }
        let repositories = RepositoryQuery.filter(candidates, scope: libraryScope, owner: owner, search: "", sort: .pushed)
        let context = inventory.map { Inventory(account: $0.account, organizations: $0.organizations, repositories: repositories,
                                               fetchedAt: $0.fetchedAt, requiresRefresh: $0.requiresRefresh == true) }
        if let repo { selectedID = repo.id }
        assistantFocus = repo != nil ? .repository : owner != nil ? .owner : .library
        showAssistant = true; assistantPrompt = prompt; assistantOwner = owner; assistantScope = libraryScope
        runAssistant(prompt, repo: repo, context: context)
    }
    func runAssistant(_ prompt: String, repo: Repository?, context: Inventory?) {
        assistantContext = context
        let project = workspace.projects.first { $0.id == assistantProjectID }
        let contextIDs = Set(context?.repositories.map(\.id) ?? [])
        let connected = project.map { workspace.connections(for: $0) } ?? repo.map { workspace.connections(for: $0.id) }
            ?? workspace.connections.filter { connection in
                !connection.repositoryIDs.isDisjoint(with: contextIDs) || workspace.projects.contains { connection.projectIDs.contains($0.id) && !$0.repositoryIDs.isDisjoint(with: contextIDs) }
            }
        assistantServices = Array(connected.prefix(15)); assistantOpenServices = []
        let projectContext = project.map { "Project: \($0.name)\nProject Notes (untrusted data): \(String($0.notes.prefix(1000)))\n" } ?? ""
        let serviceContext = projectContext + connected.prefix(15).map { connection in
            "\(connection.name): \(connection.dashboardURL)"
        }.joined(separator: "\n")
        assistantBusy = true; assistantAnswer = ""; assistantError = nil; suggestion = nil
        assistantQuestion = prompt; assistantPrompt = ""
        assistantSubject = project?.name ?? repo?.full_name ?? assistantOwner ?? assistantScope.rawValue
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("open ") {
            assistantOpenServices = ServiceResolver.resolve(prompt, in: connected)
            assistantAnswer = assistantOpenServices.isEmpty ? "No linked dashboard matches that request in this context." : assistantOpenServices.count == 1 ? "Open the linked dashboard below." : "Choose one of these linked dashboards."
            assistantBusy = false; return
        }
        assistantTask = Task {
            defer { assistantBusy = false }
            do {
                let readme: String
                if let repo { readme = try await service.readme(repo) } else { readme = "" }
                guard !Task.isCancelled else { return }
                let result = try await Intelligence.answer(prompt: prompt, repo: repo, readme: readme, inventory: context, serviceContext: serviceContext)
                guard !Task.isCancelled else { return }
                assistantAnswer = result.answer
                if let action = result.action, let repo { suggestion = AssistantSuggestion(repo: repo, action: action) }
            } catch { if !Task.isCancelled { assistantError = error.localizedDescription } }
        }
    }
}

struct Consent: Identifiable {
    enum Kind { case refresh, open(Repository), assistant(String, Repository?, Inventory?), ownerVisibility(String, Bool), url(URL), copy(String) }
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
}
enum EditorKind: String, Identifiable { case rename, description, transfer; var id: String { rawValue } }
struct EditorRequest: Identifiable { let id = UUID(); let repo: Repository; let kind: EditorKind }

struct AssistantSuggestion { let repo: Repository; let action: RepositoryAction }
enum AssistantFocus: String, CaseIterable { case repository = "Repository", owner = "Owner", library = "Library" }

/// Sidebar and popover counts, computed off the main actor with each rebuild.
struct LibraryCounts: Sendable {
    private(set) var scopes: [LibraryScope: Int] = [:]
    private(set) var owners: [String: Int] = [:]
    init() {}
    /// `visible` excludes hidden owners; owner counts use `all` so hidden owners still show their size.
    init(visible: [Repository], all: [Repository], now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-30 * 86400)
        let parser = ISO8601DateFormatter()
        for repo in all { owners[repo.owner.login, default: 0] += 1 }
        for repo in visible {
            scopes[.all, default: 0] += 1
            if let pushed = repo.pushed_at.flatMap({ parser.date(from: $0) }), pushed >= cutoff { scopes[.recent, default: 0] += 1 }
            if !repo.hasDescription { scopes[.missing, default: 0] += 1 }
            if repo.archived { scopes[.archived, default: 0] += 1 }
            if repo.fork { scopes[.forks, default: 0] += 1 }
        }
    }
    func count(_ scope: LibraryScope) -> Int { scopes[scope] ?? 0 }
    func count(owner: String) -> Int { owners[owner] ?? 0 }
}
