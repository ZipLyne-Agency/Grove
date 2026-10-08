import SwiftUI
import GroveCore

struct SidebarRow<Icon: View>: View {
    let title: String
    var badge: String? = nil
    let selected: Bool
    let action: () -> Void
    let icon: Icon
    init(_ title: String, badge: String? = nil, selected: Bool, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) {
        self.title = title; self.badge = badge; self.selected = selected; self.action = action; self.icon = icon()
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                icon.frame(width: 16)
                    .foregroundStyle(selected ? AnyShapeStyle(Color.grove) : AnyShapeStyle(.secondary))
                Text(title).lineLimit(1).truncationMode(.tail)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? AnyShapeStyle(Color.groveInk) : AnyShapeStyle(.primary))
                Spacer(minLength: 4)
                if let badge { Text(badge).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit() }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8).frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowPlate(selected: selected, radius: 6)
        .help(title)
    }
}

struct LibrarySidebar: View {
    @Bindable var store: Store
    let ui: WorkspaceUI
    private var workspace: WorkspaceStore { store.workspace }
    private var account: String? { store.inventory?.account.login }
    private var ownerRows: [String] {
        let others = store.owners.filter { $0 != account }
        if let account, store.owners.contains(account) { return [account] + others }
        return others
    }
    private var sidebarProjects: [GroveProject] {
        let pinned = workspace.projects.filter(\.pinned)
        let recent = workspace.archive.projects.filter { !$0.pinned }.sorted { $0.updatedAt > $1.updatedAt }.prefix(3)
        return pinned + recent
    }
    var body: some View {
        VStack(spacing: 0) {
            WindowDragArea().frame(height: 44)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("Library", add: nil) {
                        ForEach(LibraryScope.allCases, id: \.self) { scope in
                            SidebarRow(scope.title, badge: store.inventory == nil ? nil : store.counts.count(scope).formatted(),
                                       selected: workspace.destination == .library && store.owner == nil && store.scope == scope,
                                       action: { workspace.destination = .library; store.owner = nil; store.scope = scope }) {
                                Image(systemName: scope.symbol)
                            }
                            .contextMenu { ScopeMenu(store: store, scope: scope) }
                        }
                    }
                    section("Projects", add: { ui.sheet = .editProject(GroveProject(name: ""), isNew: true) }) {
                        if workspace.projects.isEmpty {
                            SidebarRow("New Project…", selected: false, action: { ui.sheet = .editProject(GroveProject(name: ""), isNew: true) }) {
                                Image(systemName: "plus.square.dashed")
                            }
                        }
                        ForEach(sidebarProjects) { project in
                            SidebarRow(project.name, badge: project.repositoryIDs.count.formatted(),
                                       selected: workspace.destination == .projects && !ui.showAllProjects && workspace.selectedProjectID == project.id,
                                       action: {
                                           workspace.destination = .projects; workspace.selectedProjectID = project.id
                                           ui.showAllProjects = false; ui.projectRepositoryID = nil
                                       }) {
                                ProjectTile(project: project, size: 14)
                            }
                            .contextMenu { ProjectMenu(store: store, ui: ui, project: project) }
                        }
                        if !workspace.projects.isEmpty {
                            SidebarRow("All Projects", badge: workspace.projects.count.formatted(),
                                       selected: workspace.destination == .projects && ui.showAllProjects,
                                       action: { workspace.destination = .projects; ui.showAllProjects = true; ui.projectRepositoryID = nil }) {
                                Image(systemName: "square.grid.2x2")
                            }
                        }
                    }
                    section("Owners", add: nil) {
                        if store.inventory == nil {
                            Text(store.loadingCache ? "Loading…" : "Connect to See Owners").font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 8)
                        } else if ownerRows.isEmpty {
                            Text("Every Owner Is Hidden").font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 8)
                        }
                        ForEach(ownerRows, id: \.self) { owner in
                            SidebarRow(owner, badge: store.counts.count(owner: owner).formatted(),
                                       selected: workspace.destination == .library && store.owner == owner,
                                       action: { workspace.destination = .library; store.scope = .all; store.owner = owner }) {
                                Image(systemName: owner == account ? "person.crop.circle" : "building.2")
                            }
                            .contextMenu { OwnerMenu(store: store, owner: owner) }
                        }
                        if !store.hiddenOwners.isEmpty { hiddenOwnersRow }
                    }
                }
                .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 10)
            }
            .scrollIndicators(.never)
            footer
        }
        .background(VisualEffectBackground(material: .sidebar).ignoresSafeArea())
    }

    private func section<Content: View>(_ title: String, add: (() -> Void)?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
                Spacer()
                if let add {
                    Button(action: add) { Label("New Project", systemImage: "plus") }
                        .buttonStyle(IconButtonStyle(size: 18)).help("New Project (⌘N)")
                        .disabled(!workspace.canEdit)
                }
            }
            .padding(.horizontal, 8).frame(height: 22)
            content()
        }
    }

    private var hiddenOwnersRow: some View {
        Menu {
            Section("Show in Grove") {
                ForEach(store.hiddenOwners.sorted(), id: \.self) { owner in
                    Button("\(owner) (\(store.counts.count(owner: owner).formatted()))") { store.requestOwnerVisibility(owner, hidden: false) }
                }
            }
        } label: {
            Label("\(store.hiddenOwners.count.formatted()) Hidden", systemImage: "eye.slash")
        }
        .menuStyle(.borderlessButton)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8).frame(height: 28)
        .disabled(!store.canStartReview)
        .help("Owners hidden on this Mac. Choose one to show it again.")
    }

    private var footer: some View {
        return VStack(spacing: 1) {
            SidebarRow("Services", selected: workspace.destination == .connections,
                       action: { workspace.destination = .connections }) {
                Image(systemName: "powerplug")
            }
            SidebarRow("Settings", badge: "⌘,", selected: workspace.destination == .settings,
                       action: { workspace.destination = .settings }) {
                Image(systemName: "gearshape")
            }
            Divider().padding(.vertical, 7)
            HStack(spacing: 9) {
                Text(String((account ?? "?").prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(account == nil ? Color.secondary : Color.grove, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account ?? "Not Connected").font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Group {
                        if store.busy { Text("Syncing Quietly…") }
                        else if store.message != nil, let date = store.inventory?.fetchedAt {
                            Text("Couldn't Sync · Showing Saved Data").foregroundStyle(Color.caution).help("Saved \(GroveDates.exact(date))")
                        }
                        else if let date = store.inventory?.fetchedAt { Text("Synced \(GroveDates.named(date))").help(GroveDates.exact(date)) }
                        else { Text("GitHub CLI Sign-In") }
                    }
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 12)
    }
}
