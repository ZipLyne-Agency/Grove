import SwiftUI
import GroveCore

struct ProjectDetailView: View {
    @Bindable var store: Store
    let ui: WorkspaceUI
    let project: GroveProject
    private var workspace: WorkspaceStore { store.workspace }
    private var repos: [Repository] {
        (store.inventory?.repositories ?? []).filter { project.repositoryIDs.contains($0.id) }
            .sorted { $0.full_name.localizedStandardCompare($1.full_name) == .orderedAscending }
    }
    private var services: [ServiceConnection] { workspace.connections(for: project) }
    var body: some View {
        VStack(spacing: 0) {
            header()
            DetailTabs(tabs: ProjectTab.allCases, selection: Binding(get: { workspace.projectTab }, set: { workspace.projectTab = $0 }),
                       counts: [.services: services.count])
                .padding(.top, 16)
            ScrollView {
                Group {
                    switch workspace.projectTab {
                    case .overview: overview()
                    case .services: servicesTab
                    case .activity: ActivityList(items: ActivityFeed.items(connections: services, repositories: repos))
                    case .settings: ProjectSettingsForm(store: store, ui: ui, project: project)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.vertical, 18)
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.inspector)
    }

    private func header() -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProjectTile(project: project, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name).font(.system(size: 20, weight: .semibold)).lineLimit(2).truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                HStack(spacing: 4) {
                    Text("\(countLabel(repos.count, "Repository", "Repositories")) · \(countLabel(services.count, "Service", "Services"))").foregroundStyle(.secondary)
                }
                .font(.system(size: 12)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { var next = project; next.pinned.toggle(); workspace.saveProject(next) } label: {
                Label(project.pinned ? "Pinned" : "Pin", systemImage: project.pinned ? "pin.fill" : "pin")
            }
            .disabled(!workspace.canEdit)
            .accessibilityAddTraits(project.pinned ? .isSelected : [])
            Button { askAboutProject() } label: { Label { Text("Ask") } icon: { GroveMark(size: 15, available: Intelligence.available) } }
                .buttonStyle(AskGroveButtonStyle(active: store.showAssistant && store.assistantProjectID == project.id))
                .help("Ask Grove About \(project.name)")
            Menu {
                ProjectMenu(store: store, ui: ui, project: project)
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("More Project Actions")
        }
        .controlSize(.regular)
        .padding(.horizontal, 24).padding(.top, 18)
    }

    private func askAboutProject() {
        store.assistantFocus = .library; store.assistantProjectID = project.id; store.assistantOwner = nil; store.showAssistant = true
    }

    private func overview() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailSection(title: "Notes") {
                if project.notes.isEmpty {
                    Button("Add Notes…") { workspace.projectTab = .settings }.buttonStyle(.link).font(.system(size: 12))
                } else {
                    Text(project.notes).font(.system(size: 13)).lineSpacing(2).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
            DetailSection(title: "Repositories", caption: "Stored on This Mac") {
                if repos.isEmpty {
                    Text("No repositories in this project yet.").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    TableBox {
                        ForEach(repos) { repo in
                            Button { store.selectedID = repo.id; ui.showAllProjects = false; ui.projectRepositoryID = repo.id } label: {
                                HStack(spacing: 9) {
                                    RepositoryGlyph(repo: repo, size: 22)
                                    Text(repo.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                                    Text(repo.owner.login).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(countLabel(workspace.connections(for: repo.id).count, "Service", "Services")).font(.system(size: 11)).foregroundStyle(.secondary)
                                    Text(GroveDates.short(GroveDates.pushed(repo))).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                                }
                                .padding(.horizontal, 10).frame(minHeight: 36).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            DetailSection(title: "Services Across This Project", caption: "Each Service Listed Once") {
                if services.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No services are linked to this project or its repositories. Add a connection, or discover services from a repository's Services tab.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Add Connection") { addConnection() }.controlSize(.small).disabled(!workspace.canEdit)
                    }
                } else {
                    TableBox {
                        ForEach(services) { connection in
                            ServiceRow(store: store, ui: ui, connection: connection, usedBy: usedBy(connection), context: .project(project.id))
                        }
                    }
                }
            }
        }
    }

    private var servicesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(countLabel(services.count, "Service", "Services")).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                if repos.count == 1, let repo = repos.first {
                    Button("Find Services") { ui.sheet = .discover(repo) }.disabled(!workspace.canEdit)
                } else {
                    Menu("Find Services") {
                        ForEach(repos) { repo in Button(repo.name) { ui.sheet = .discover(repo) } }
                    }.disabled(repos.isEmpty || !workspace.canEdit)
                }
                Button("Add Service") { addConnection() }.buttonStyle(.borderedProminent).disabled(!workspace.canEdit)
            }
            .controlSize(.small)
            ServiceList(store: store, ui: ui, connections: services, context: .project(project.id)) { addConnection() }
        }
    }
    private func addConnection() {
        ui.sheet = .editConnection(ServiceConnection(provider: .custom, name: "", projectIDs: [project.id]), isNew: true)
    }

    private func usedBy(_ connection: ServiceConnection) -> String? {
        let linked = repos.filter { connection.repositoryIDs.contains($0.id) }
        if connection.projectIDs.contains(project.id) && linked.isEmpty { return "Whole Project" }
        if linked.count == 1 { return linked[0].name }
        if linked.count > 1 { return "\(linked.count.formatted()) Repositories" }
        return nil
    }
}

/// Editable name, notes, pin, and membership. Everything here stays on this Mac.
struct ProjectSettingsForm: View {
    let store: Store
    let ui: WorkspaceUI
    let project: GroveProject
    @State private var draft: GroveProject?
    private var workspace: WorkspaceStore { store.workspace }
    var body: some View {
        let current = draft ?? project
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                FieldLabel("Name")
                TextField("Project Name", text: Binding(get: { current.name }, set: { var next = current; next.name = $0; draft = next }))
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 420)
            }
            VStack(alignment: .leading, spacing: 5) {
                FieldLabel("Notes")
                TextField("Notes for this project", text: Binding(get: { current.notes }, set: { var next = current; next.notes = $0; draft = next }), axis: .vertical)
                    .lineLimit(3...10).textFieldStyle(.roundedBorder).frame(maxWidth: 560)
            }
            Toggle("Pin to Sidebar", isOn: Binding(get: { current.pinned }, set: { var next = current; next.pinned = $0; draft = next }))
                .toggleStyle(.checkbox)
            HStack(spacing: 8) {
                Button("Save Changes") {
                    guard let pending = draft else { return }
                    workspace.error = nil; workspace.saveProject(pending)
                    if workspace.error == nil { draft = nil }
                }
                .buttonStyle(.borderedProminent).disabled(draft == nil || !workspace.canEdit)
                Button("Revert") { draft = nil }.disabled(draft == nil)
            }
            .controlSize(.small)
            Divider()
            DetailSection(title: "Repositories") {
                HStack {
                    Text("\(countLabel(project.repositoryIDs.count, "repository", "repositories")) in this project.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit Repositories…") { ui.sheet = .editProject(project, isNew: false) }.controlSize(.small).disabled(!workspace.canEdit)
                }
            }
            DetailSection(title: "Delete") {
                HStack(alignment: .firstTextBaseline) {
                    Text("Deletes the project's name, notes, and membership from this Mac. Repositories and services are not deleted.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button("Delete Project…") { ui.sheet = .deleteProject(project) }
                        .foregroundStyle(Color.danger).controlSize(.small).disabled(!workspace.canEdit)
                }
            }
        }
        .onChange(of: project.id) { draft = nil }
    }
}
