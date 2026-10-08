import SwiftUI
import GroveCore

/// Routes a workspace sheet to its view.
struct WorkspaceSheetView: View {
    let store: Store
    let ui: WorkspaceUI
    let sheet: WorkspaceSheet
    var body: some View {
        switch sheet {
        case .editProject(let project, let isNew): ProjectEditorSheet(store: store, ui: ui, project: project, isNew: isNew)
        case .deleteProject(let project): DeleteProjectSheet(store: store, ui: ui, project: project)
        case .editConnection(let connection, let isNew): ConnectionEditorSheet(store: store, ui: ui, connection: connection, isNew: isNew)
        case .removeConnection(let connection): RemoveConnectionSheet(store: store, ui: ui, connection: connection)
        case .unlink(let connection, let target): UnlinkSheet(store: store, ui: ui, connection: connection, target: target)
        case .editAccount(let account, let isNew): AccountEditorSheet(store: store, ui: ui, account: account, isNew: isNew)
        case .removeAccount(let account): RemoveAccountSheet(store: store, ui: ui, account: account)
        case .discover(let repo): DiscoverSheet(store: store, ui: ui, repo: repo)
        case .renameService(let connection): RenameServiceSheet(store: store, ui: ui, connection: connection)
        }
    }
}

struct SheetError: View {
    let store: Store
    var body: some View {
        if let error = store.workspace.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12)).foregroundStyle(Color.caution)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
}

struct FormField<Field: View>: View {
    let label: String
    let field: Field
    init(_ label: String, @ViewBuilder field: () -> Field) { self.label = label; self.field = field() }
    var body: some View { VStack(alignment: .leading, spacing: 5) { FieldLabel(label); field } }
}

struct Chip: View {
    let text: String
    let remove: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            Text(text).lineLimit(1).truncationMode(.middle)
            Button(action: remove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                .buttonStyle(.plain).accessibilityLabel("Remove \(text)").help("Remove \(text)")
        }
        .font(.system(size: 11.5)).foregroundStyle(Color.groveInk)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.selection, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

// MARK: Projects

struct ProjectEditorSheet: View {
    let store: Store
    let ui: WorkspaceUI
    let isNew: Bool
    @State private var draft: GroveProject
    @State private var filter = ""
    @FocusState private var nameFocused: Bool
    private var workspace: WorkspaceStore { store.workspace }
    init(store: Store, ui: WorkspaceUI, project: GroveProject, isNew: Bool) {
        self.store = store; self.ui = ui; self.isNew = isNew
        _draft = State(initialValue: project)
    }
    private var candidates: [Repository] {
        let terms = filter.split(whereSeparator: \.isWhitespace).map(String.init)
        return (store.inventory?.repositories ?? [])
            .filter { !store.hiddenOwners.contains($0.owner.login) || draft.repositoryIDs.contains($0.id) }
            .filter { repo in terms.allSatisfy { repo.full_name.localizedCaseInsensitiveContains($0) } }
            .sorted { a, b in
                let ai = draft.repositoryIDs.contains(a.id), bi = draft.repositoryIDs.contains(b.id)
                return ai != bi ? ai : a.full_name.localizedStandardCompare(b.full_name) == .orderedAscending
            }
    }
    var body: some View {
        let all = candidates
        let shown = Array(all.prefix(200))
        SheetFrame(symbol: "square.grid.2x2", tint: .grove, title: isNew ? "New Project" : "Edit Project",
                   subtitle: "Groups repositories and services on this Mac. Nothing changes on GitHub.") {
            FormField("Name") {
                TextField("Project Name", text: $draft.name).textFieldStyle(.roundedBorder).focused($nameFocused)
            }
            FormField("Notes (Optional)") {
                TextField("What this project is for", text: $draft.notes, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    FieldLabel("Repositories")
                    Spacer()
                    Text("\(draft.repositoryIDs.count.formatted()) Selected").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                TextField("Filter Repositories", text: $filter).textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if shown.isEmpty {
                            Text(store.inventory == nil ? "Connect GitHub to choose repositories." : "No repositories match.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).padding(10)
                        }
                        ForEach(shown) { repo in
                            Toggle(isOn: Binding(get: { draft.repositoryIDs.contains(repo.id) },
                                                 set: { on in if on { draft.repositoryIDs.insert(repo.id) } else { draft.repositoryIDs.remove(repo.id) } })) {
                                HStack(spacing: 6) {
                                    Text(repo.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                                    Text(repo.owner.login).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    Spacer(minLength: 6)
                                    if let other = otherProjects(repo) {
                                        Text(other).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.horizontal, 10).frame(minHeight: 30)
                        }
                        if all.count > shown.count {
                            Text("Showing 200 of \(all.count.formatted()). Filter to find others.").font(.system(size: 11)).foregroundStyle(.secondary).padding(10)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: 210)
                .background(Color.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.hairline.opacity(0.7)))
            }
            Toggle("Pin to Sidebar", isOn: $draft.pinned).toggleStyle(.checkbox)
            SheetError(store: store)
        } buttons: {
            Button("Cancel") { workspace.error = nil; ui.sheet = nil }.keyboardShortcut(.cancelAction)
            Button(isNew ? "Create Project" : "Save") { save() }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !workspace.canEdit)
        }
        .onAppear { nameFocused = true }
    }
    private func otherProjects(_ repo: Repository) -> String? {
        let names = workspace.archive.projects(for: repo.id).filter { $0.id != draft.id }.map(\.name)
        return names.isEmpty ? nil : "Also in \(names.joined(separator: ", "))"
    }
    private func save() {
        workspace.error = nil
        workspace.saveProject(draft)
        guard workspace.error == nil else { return }
        ui.sheet = nil
        if isNew {
            workspace.destination = .projects; workspace.selectedProjectID = draft.id
            ui.showAllProjects = false; ui.projectRepositoryID = nil
        }
    }
}

struct DeleteProjectSheet: View {
    let store: Store
    let ui: WorkspaceUI
    let project: GroveProject
    var body: some View {
        let direct = store.workspace.connections.filter { $0.projectIDs.contains(project.id) }.count
        SheetFrame(symbol: "trash", tint: .danger, title: "Delete \(project.name)?", subtitle: "Only changes Grove on this Mac.") {
            ValueBox(rows: [
                ("Repositories", "\(countLabel(project.repositoryIDs.count, "repository stays", "repositories stay")) in your library and on GitHub.", false),
                ("Services", direct == 0 ? "No services are linked directly to this project." : "\(countLabel(direct, "service loses", "services lose")) this project link. Connections stay in Connections.", false),
                ("Notes", project.notes.isEmpty ? "None" : "The project's notes are deleted.", false)
            ], tint: .danger)
        } buttons: {
            Button("Cancel") { ui.sheet = nil }.keyboardShortcut(.cancelAction)
            Button("Delete Project", role: .destructive) {
                store.workspace.removeProject(project.id); ui.sheet = nil; ui.showAllProjects = true; ui.projectRepositoryID = nil
            }
            .buttonStyle(.borderedProminent).tint(.danger)
            .disabled(!store.workspace.canEdit)
        }
    }
}

// MARK: Local removal reviews

struct RemoveConnectionSheet: View {
    let store: Store
    let ui: WorkspaceUI
    let connection: ServiceConnection
    var body: some View {
        let projects = store.workspace.archive.projects.filter { connection.projectIDs.contains($0.id) }.map { "Project \($0.name)" }
        let repos = (store.inventory?.repositories ?? []).filter { connection.repositoryIDs.contains($0.id) }.map(\.name)
        let places = projects + repos
        SheetFrame(symbol: "trash", tint: .danger, title: "Remove \(connection.name)?", subtitle: "Only changes Grove on this Mac.") {
            ValueBox(rows: [
                ("Service", "\(connection.provider.title) · \(connection.displayIdentity)", true),
                ("Removed From", places.isEmpty ? "Connections only" : places.joined(separator: ", "), false),
                ("Account", store.workspace.account(for: connection).map { "\($0.name) and its credential stay in Grove." } ?? "None", false)
            ], tint: .danger)
            FinePrint("Nothing changes at \(connection.provider.title). You can add it again at any time.")
        } buttons: {
            Button("Cancel") { ui.sheet = nil }.keyboardShortcut(.cancelAction)
            Button("Remove Connection", role: .destructive) { store.workspace.removeConnection(connection.id); ui.sheet = nil }
                .buttonStyle(.borderedProminent).tint(.danger).disabled(!store.workspace.canEdit)
        }
    }
}

struct UnlinkSheet: View {
    let store: Store
    let ui: WorkspaceUI
    let connection: ServiceConnection
    let target: LinkTarget
    private var targetName: String {
        switch target {
        case .repository(let id): store.inventory?.repositories.first { $0.id == id }?.full_name ?? "Repository \(id)"
        case .project(let id): store.workspace.archive.projects.first { $0.id == id }.map { "Project \($0.name)" } ?? "This Project"
        }
    }
    private var direct: Bool {
        switch target {
        case .repository(let id): connection.repositoryIDs.contains(id)
        case .project(let id): connection.projectIDs.contains(id)
        }
    }
    private var unlinked: ServiceConnection {
        var next = connection
        switch target {
        case .repository(let id): next.repositoryIDs.remove(id)
        case .project(let id): next.projectIDs.remove(id)
        }
        return next
    }
    var body: some View {
        let next = unlinked
        let remaining = store.workspace.archive.projects.filter { next.projectIDs.contains($0.id) }.map { "Project \($0.name)" }
            + (store.inventory?.repositories ?? []).filter { next.repositoryIDs.contains($0.id) }.map(\.name)
        SheetFrame(symbol: "link", tint: .grove, title: "Unlink \(connection.name)?", subtitle: "Only changes Grove on this Mac.") {
            ValueBox(rows: [
                ("Service", "\(connection.provider.title) · \(connection.displayIdentity)", true),
                ("Removed From", targetName, false),
                ("Still Shown In", remaining.isEmpty ? "Connections only" : remaining.joined(separator: ", "), false)
            ])
            FinePrint(direct
                      ? "The connection and its account stay in Grove. Nothing changes at \(connection.provider.title)."
                      : "This service appears here through a project. Unlink it from that project, or edit the project's repositories.")
        } buttons: {
            Button("Cancel") { ui.sheet = nil }.keyboardShortcut(.cancelAction)
            Button("Unlink") { store.workspace.saveConnection(next); ui.sheet = nil }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled(!direct || !store.workspace.canEdit)
        }
    }
}
