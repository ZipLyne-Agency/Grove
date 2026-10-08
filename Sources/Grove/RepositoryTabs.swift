import SwiftUI
import GroveCore

/// Every service linked to a repository, directly or through one of its projects.
struct RepositoryServicesTab: View {
    let store: Store
    let ui: WorkspaceUI
    let repo: Repository
    let services: [ServiceConnection]
    private var workspace: WorkspaceStore { store.workspace }
    var body: some View {
        let direct = services.filter { $0.repositoryIDs.contains(repo.id) }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(summary).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Button("Ask About Services") {
                    store.requestAssistant("Summarize this repository's connected services. Say which are verified, out of date, failing, or only saved links.", repo: store.selected)
                }
                .disabled(!Intelligence.available || store.assistantBusy || !store.canStartReview || services.isEmpty)
                Button("Sync Now") { for connection in services where connection.accountID != nil { workspace.requestSync(connection.id) } }
                    .disabled(!workspace.canEdit || !services.contains { $0.accountID != nil })
                Button("Discover Services") { ui.sheet = .discover(repo) }.disabled(!workspace.canEdit)
                Button("Add Connection") { add() }.buttonStyle(.borderedProminent).disabled(!workspace.canEdit)
            }
            .controlSize(.small)
            if services.count > direct {
                FinePrint("Services marked Via Project are linked to a project this repository belongs to.")
            }
            ServiceGrid(store: store, ui: ui, connections: services, context: .repository(repo.id), usedBy: viaProject) { add() }
        }
    }
    private var summary: String {
        if services.isEmpty { return "No services linked yet." }
        let statuses = services.map { $0.status() }
        let verified = statuses.filter { $0 == .verified || $0 == .stale }.count
        let links = statuses.filter { $0 == .savedLink }.count
        let suggested = statuses.filter { $0 == .suggested }.count
        let attention = statuses.filter { $0 == .failed || $0 == .needsAuthorization }.count
        var parts = ["\(verified.formatted()) Verified", "\(links.formatted()) Saved \(links == 1 ? "Link" : "Links")"]
        if suggested > 0 { parts.append("\(suggested.formatted()) Suggested") }
        if attention > 0 { parts.append("\(attention.formatted()) Need Attention") }
        return parts.joined(separator: " · ")
    }
    private func viaProject(_ connection: ServiceConnection) -> String? {
        guard !connection.repositoryIDs.contains(repo.id) else { return nil }
        let names = workspace.archive.projects(for: repo.id).filter { connection.projectIDs.contains($0.id) }.map(\.name)
        return names.isEmpty ? nil : "Via Project \(names.joined(separator: ", "))"
    }
    private func add() {
        ui.sheet = .editConnection(ServiceConnection(provider: .vercel, name: "", repositoryIDs: [repo.id]), isNew: true)
    }
}

/// GitHub changes through reviews, then local Grove settings.
struct RepositoryManageTab: View {
    let store: Store
    let ui: WorkspaceUI
    let repo: Repository
    private var workspace: WorkspaceStore { store.workspace }
    private var blockedReason: String? {
        if !repo.canAdminister { return "You need admin access to change this repository." }
        if store.needsRefresh { return "Changes are paused while Grove confirms GitHub's current state." }
        if !store.canStartReview { return "Finish the current task first." }
        return nil
    }
    var body: some View {
        let reason = blockedReason
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("GitHub")
            if let reason {
                Label(reason, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                GroupedRows {
                    Button { store.requestEdit(repo, kind: .rename) } label: { label("Rename…", "pencil") }
                    Button { store.requestEdit(repo, kind: .description) } label: { label("Edit Description…", "text.alignleft") }
                    Button { store.requestEdit(repo, kind: .transfer) } label: { label("Transfer to Organization…", "arrow.right.arrow.left") }
                    Button { Task { await store.prepare(repo, action: .archive(!repo.archived)) } } label: {
                        label(repo.archived ? "Unarchive…" : "Archive…", "archivebox")
                    }
                }
                .buttonStyle(RowButtonStyle())
                GroupedRows {
                    Button { Task { await store.prepare(repo, action: .delete) } } label: { label("Delete Repository…", "trash") }
                        .buttonStyle(RowButtonStyle(destructive: true))
                }
                .padding(.top, 6)
            }
            .disabled(reason != nil)
            FinePrint("Each change opens a review before anything is sent to GitHub. Transfer and deletion ask for the full name.")
            SectionHeader("Grove").padding(.top, 14)
            GroupedRows {
                HStack(spacing: 9) {
                    Image(systemName: "square.grid.2x2").frame(width: 15).accessibilityHidden(true)
                    Text("Projects")
                    Spacer(minLength: 0)
                    ProjectMembershipMenu(store: store, ui: ui, repo: repo,
                                          title: workspace.archive.projects(for: repo.id).isEmpty ? "Add to Project" : "Edit Projects")
                }
                .font(.system(size: 12)).padding(.horizontal, 10).frame(minHeight: 30)
                Button { store.requestOwnerVisibility(repo.owner.login, hidden: true) } label: { label("Hide \(repo.owner.login) From Grove", "eye.slash") }
                    .buttonStyle(RowButtonStyle()).disabled(!store.canStartReview)
                Button { store.requestCopy(String(repo.id)) } label: { label("Copy Repository ID", "number") }
                    .buttonStyle(RowButtonStyle())
            }
            FinePrint("Projects, hidden owners, and connections only change Grove on this Mac.")
        }
    }
    private func label(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).frame(width: 15).accessibilityHidden(true)
            Text(title).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

/// Adds or removes a repository from projects. Local only; nothing changes on GitHub.
struct ProjectMembershipMenu: View {
    let store: Store
    let ui: WorkspaceUI
    let repo: Repository
    let title: String
    private var workspace: WorkspaceStore { store.workspace }
    var body: some View {
        Menu {
            ForEach(workspace.projects) { project in
                Button {
                    var next = project
                    if next.repositoryIDs.contains(repo.id) { next.repositoryIDs.remove(repo.id) } else { next.repositoryIDs.insert(repo.id) }
                    workspace.saveProject(next)
                } label: {
                    if project.repositoryIDs.contains(repo.id) { Label(project.name, systemImage: "checkmark") } else { Text(project.name) }
                }
            }
            if !workspace.projects.isEmpty { Divider() }
            Button("New Project…") { ui.sheet = .editProject(GroveProject(name: "", repositoryIDs: [repo.id]), isNew: true) }
        } label: {
            Label(title, systemImage: "plus").foregroundStyle(Color.groveInk)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .frame(height: 30)
        .disabled(!workspace.canEdit)
        .help("Projects stay on this Mac. Nothing changes on GitHub.")
    }
}
