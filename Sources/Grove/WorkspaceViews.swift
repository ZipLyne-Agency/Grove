import SwiftUI
import GroveCore

/// All Projects, or the contents of one project, in the middle column.
struct ProjectsColumn: View {
    @Bindable var store: Store
    let ui: WorkspaceUI
    private var workspace: WorkspaceStore { store.workspace }
    var body: some View {
        Group {
            if ui.showAllProjects || workspace.selectedProject == nil { allProjects }
            else if let project = workspace.selectedProject { contents(project) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var allProjects: some View {
        if workspace.loading {
            ProgressView("Loading Projects…").controlSize(.small)
        } else if workspace.projects.isEmpty {
            ContentUnavailableView {
                Label("No Projects Yet", systemImage: "square.grid.2x2")
            } description: {
                Text("A project groups repositories and the services they ship with. Projects live on this Mac and change nothing on GitHub.")
            } actions: {
                Button("New Project…") { ui.sheet = .editProject(GroveProject(name: ""), isNew: true) }
                    .buttonStyle(.borderedProminent).disabled(!workspace.canEdit)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(workspace.projects) { project in
                        Button { workspace.selectedProjectID = project.id } label: { ProjectRow(store: store, project: project) }
                            .buttonStyle(.plain)
                            .rowPlate(selected: workspace.selectedProjectID == project.id)
                            .contextMenu { ProjectMenu(store: store, ui: ui, project: project) }
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.never)
            .onAppear { if workspace.selectedProjectID == nil { workspace.selectedProjectID = workspace.projects.first?.id } }
        }
    }

    private func contents(_ project: GroveProject) -> some View {
        let repos = members(project)
        let known = Set((store.inventory?.repositories ?? []).map(\.id))
        let missing = project.repositoryIDs.filter { !known.contains($0) }.sorted()
        return ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                Button { ui.projectRepositoryID = nil } label: {
                    HStack(spacing: 10) {
                        ProjectTile(project: project, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Project Overview").font(.system(size: 13, weight: .semibold))
                            Text("Notes, shared services, and activity").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .rowPlate(selected: ui.projectRepositoryID == nil)
                HStack {
                    SectionHeader("Repositories")
                    Spacer()
                    Button { ui.sheet = .editProject(project, isNew: false) } label: { Label("Add Repository", systemImage: "plus") }
                        .buttonStyle(.borderless).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.groveInk)
                        .disabled(!workspace.canEdit)
                }
                .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
                if repos.isEmpty && missing.isEmpty {
                    Text("No repositories in this project yet.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 6)
                }
                ForEach(repos) { repo in
                    RepositoryRow(repo: repo, store: store, selected: ui.projectRepositoryID == repo.id, showsProjects: false)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { store.selectedID = repo.id; ui.projectRepositoryID = repo.id }
                        .rowPlate(selected: ui.projectRepositoryID == repo.id)
                        .contextMenu { RepositoryMenu(store: store, repo: repo) }
                        .accessibilityAction { store.selectedID = repo.id; ui.projectRepositoryID = repo.id }
                }
                ForEach(missing, id: \.self) { id in
                    HStack(spacing: 10) {
                        Image(systemName: "questionmark.folder").foregroundStyle(.secondary).frame(width: 28).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not Available").font(.system(size: 13, weight: .semibold))
                            Text("GitHub repository ID \(id.formatted(.number.grouping(.never))) is not in the current library. It may be hidden, out of reach, or deleted.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 6)
                        Button("Remove") {
                            var next = project; next.repositoryIDs.remove(id); workspace.saveProject(next)
                        }
                        .controlSize(.small).disabled(!workspace.canEdit)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                }
                Text("A repository can belong to several projects, or to none. Membership is stored by GitHub repository ID, so a rename or transfer keeps it here. Changes stay on this Mac.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .padding(.horizontal, 6).padding(.top, 12)
            }
            .padding(6)
        }
        .scrollIndicators(.never)
    }

    private func members(_ project: GroveProject) -> [Repository] {
        (store.inventory?.repositories ?? []).filter { project.repositoryIDs.contains($0.id) }
            .sorted { $0.full_name.localizedStandardCompare($1.full_name) == .orderedAscending }
    }
}

struct ProjectRow: View {
    let store: Store
    let project: GroveProject
    var body: some View {
        let services = store.workspace.connections(for: project)
        HStack(spacing: 10) {
            ProjectTile(project: project, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(project.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    if project.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary).accessibilityLabel("Pinned") }
                }
                HStack(spacing: 4) {
                    Text("\(countLabel(project.repositoryIDs.count, "Repository", "Repositories")) · \(countLabel(services.count, "Service", "Services"))")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

struct ProjectMenu: View {
    let store: Store
    let ui: WorkspaceUI
    let project: GroveProject
    private var workspace: WorkspaceStore { store.workspace }
    var body: some View {
        Button("Open") { workspace.destination = .projects; workspace.selectedProjectID = project.id; ui.showAllProjects = false; ui.projectRepositoryID = nil }
        Button("Ask Grove About This Project") {
            store.assistantFocus = .library; store.assistantProjectID = project.id; store.assistantOwner = nil; store.showAssistant = true
        }
        Button(project.pinned ? "Unpin" : "Pin") { var next = project; next.pinned.toggle(); workspace.saveProject(next) }
            .disabled(!workspace.canEdit)
        Button("Edit Project…") { ui.sheet = .editProject(project, isNew: false) }.disabled(!workspace.canEdit)
        Divider()
        Button("Delete Project…", role: .destructive) { ui.sheet = .deleteProject(project) }.disabled(!workspace.canEdit)
    }
}
