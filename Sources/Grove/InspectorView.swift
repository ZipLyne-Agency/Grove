import SwiftUI
import GroveCore

/// Repository detail: header, then Overview, Services, Activity, and Manage tabs.
struct InspectorView: View {
    @Bindable var store: Store
    let ui: WorkspaceUI
    @AppStorage("repositoryTab") private var tabName = RepositoryTab.overview.rawValue
    @State private var width: CGFloat = 600
    @State private var copied = false
    private var workspace: WorkspaceStore { store.workspace }
    private var tab: Binding<RepositoryTab> {
        Binding(get: { RepositoryTab(rawValue: tabName) ?? .overview }, set: { tabName = $0.rawValue })
    }
    var body: some View {
        Group {
            if let repo = store.selected {
                detail(repo)
            } else if store.inventory == nil {
                ContentUnavailableView("No Details Yet", systemImage: "sidebar.right",
                                       description: Text("Connect GitHub to see repository details here."))
            } else {
                ContentUnavailableView("No Selection", systemImage: "sidebar.right",
                                       description: Text("Select a repository to see its details, services, and actions."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.inspector)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func detail(_ repo: Repository) -> some View {
        let services = workspace.connections(for: repo.id)
        return VStack(spacing: 0) {
            header(repo)
            DetailTabs(tabs: RepositoryTab.allCases, selection: tab, counts: [.services: services.count])
                .padding(.top, 14)
            ScrollView {
                Group {
                    switch tab.wrappedValue {
                    case .overview: overview(repo, services: services)
                    case .services: RepositoryServicesTab(store: store, ui: ui, repo: repo, services: services)
                    case .activity: ActivityList(items: ActivityFeed.items(connections: services, repositories: [repo]))
                    case .manage: RepositoryManageTab(store: store, ui: ui, repo: repo)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, width >= 600 ? 24 : 20).padding(.vertical, 18)
            }
            .scrollIndicators(.never)
        }
        .contextMenu { RepositoryMenu(store: store, repo: repo) }
    }

    // MARK: Header

    private func header(_ repo: Repository) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if width >= 560 {
                HStack(alignment: .top, spacing: 12) { identity(repo); actions(repo) }
            } else {
                identity(repo)
                actions(repo)
            }
            FlowLayout(spacing: 6) {
                GroveTag(text: repo.visibilityLabel, symbol: repo.visibilitySymbol)
                GroveTag(text: repo.canAdminister ? "Admin" : "No Admin Access", symbol: repo.canAdminister ? "checkmark.shield" : "shield.slash")
                if let language = repo.language { GroveTag(text: language) }
                if repo.archived { GroveTag(text: "Archived", symbol: "archivebox", tint: .caution) }
                if repo.fork { GroveTag(text: "Fork", symbol: "arrow.triangle.branch") }
            }
            .padding(.leading, 52)
        }
        .padding(.horizontal, width >= 600 ? 24 : 20).padding(.top, 18)
    }
    private func identity(_ repo: Repository) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RepositoryGlyph(repo: repo, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name).font(.system(size: width >= 560 ? 20 : 18, weight: .semibold))
                    .lineLimit(2).truncationMode(.middle).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text(repo.full_name).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(repo.full_name)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func actions(_ repo: Repository) -> some View {
        HStack(spacing: 6) {
            Button { store.requestOpen(repo) } label: { Label("Open", systemImage: "arrow.up.right") }
                .help("Open \(repo.full_name) on GitHub")
            Menu {
                Button("Copy Link") { if let url = repo.webURL { copy(url.absoluteString) } }
                Button("Copy Full Name") { copy(repo.full_name) }
                Button("Copy Clone Command") { copy(repo.cloneCommand) }
            } label: {
                Label(copied ? "Copied" : "Copy Link", systemImage: copied ? "checkmark" : "link")
                    .foregroundStyle(copied ? AnyShapeStyle(Color.groveInk) : AnyShapeStyle(.primary))
            } primaryAction: {
                if let url = repo.webURL { copy(url.absoluteString) }
            }
            .fixedSize()
            .accessibilityLabel(copied ? "Copied" : "Copy Link")
            Button {
                store.selectedID = repo.id; store.assistantFocus = .repository; store.assistantProjectID = nil
                store.assistantOwner = nil; store.showAssistant = true
            } label: { Label { Text("Ask") } icon: { GroveMark(size: 15, available: Intelligence.available) } }
                .buttonStyle(AskGroveButtonStyle(active: store.showAssistant))
                .help("Ask Grove About This Repository")
        }
        .controlSize(.regular)
    }
    private func copy(_ text: String) {
        Clipboard.copy(text); copied = true
        Task { try? await Task.sleep(for: .seconds(1.6)); copied = false }
    }

    // MARK: Overview

    /// Two columns only when the summary column can keep a readable width; otherwise it stacks below Details.
    @ViewBuilder private func overview(_ repo: Repository, services: [ServiceConnection]) -> some View {
        let content = width - 48
        let summaryWidth = min(320, max(260, (content - 28) * 0.38))
        if content - summaryWidth - 28 >= 380 {
            HStack(alignment: .top, spacing: 28) {
                primary(repo).frame(maxWidth: .infinity, alignment: .leading)
                secondary(repo, services: services).frame(width: summaryWidth, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 20) { primary(repo); secondary(repo, services: services) }
        }
    }

    private func primary(_ repo: Repository) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailSection(title: "Project") { projectChips(repo) }
            DetailSection(title: "About") {
                if repo.hasDescription {
                    Text(repo.description ?? "").font(.system(size: 13)).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                } else {
                    Text("No Description").font(.system(size: 13)).foregroundStyle(.secondary)
                    if repo.canAdminister {
                        Button("Add a Description…") { store.requestEdit(repo, kind: .description) }
                            .buttonStyle(.link).font(.system(size: 12))
                            .disabled(!store.canStartReview || store.needsRefresh)
                    }
                }
                if let topics = repo.topics, !topics.isEmpty {
                    FlowLayout(spacing: 5) { ForEach(topics, id: \.self) { GroveTag(text: $0, tint: .groveInk) } }.padding(.top, 2)
                }
            }
            facts(repo)
            DetailSection(title: "Clone") {
                HStack(spacing: 8) {
                    Text(repo.cloneCommand).font(.system(size: 11.5, design: .monospaced)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { copy(repo.cloneCommand) } label: { Label("Copy Clone Command", systemImage: copied ? "checkmark" : "doc.on.doc") }
                        .buttonStyle(IconButtonStyle(size: 24, tint: copied ? .groveInk : nil)).help("Copy Clone Command")
                }
                .padding(.leading, 10).padding(.trailing, 4).frame(height: 32)
                .background(Color.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.hairline.opacity(0.7)))
            }
        }
    }

    private func secondary(_ repo: Repository, services: [ServiceConnection]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailSection(title: "Services") {
                if services.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No Services Yet").font(.system(size: 12, weight: .semibold))
                        Text("Connect the tools this repository ships with, or let Grove look for them in its configuration.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) { emptyServiceActions(repo) }
                            VStack(alignment: .leading, spacing: 6) { emptyServiceActions(repo) }
                        }
                        .controlSize(.small).disabled(!workspace.canEdit)
                    }
                } else {
                    TableBox {
                        ForEach(Array(services.prefix(5))) { connection in
                            ServiceRow(store: store, ui: ui, connection: connection, context: .repository(repo.id))
                        }
                    }
                    Button("View All Services") { tab.wrappedValue = .services }.buttonStyle(.link).font(.system(size: 12))
                }
            }
            DetailSection(title: "Recent Activity") {
                ActivityList(items: ActivityFeed.items(connections: services, repositories: [repo]), limit: 3)
            }
        }
    }

    @ViewBuilder private func emptyServiceActions(_ repo: Repository) -> some View {
        Button("Find Services") { ui.sheet = .discover(repo) }.fixedSize()
        Button("Add Service") { ui.sheet = .editConnection(ServiceConnection(provider: .custom, name: "", repositoryIDs: [repo.id]), isNew: true) }.fixedSize()
    }

    private func projectChips(_ repo: Repository) -> some View {
        let memberships = workspace.archive.projects(for: repo.id).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return FlowLayout(spacing: 6) {
            if memberships.isEmpty {
                Text("Not in a Project").font(.system(size: 12)).foregroundStyle(.secondary).frame(height: 30)
            }
            ForEach(memberships) { project in
                Button {
                    workspace.destination = .projects; workspace.selectedProjectID = project.id
                    ui.showAllProjects = false; ui.projectRepositoryID = nil
                } label: {
                    HStack(spacing: 7) {
                        ProjectTile(project: project, size: 18)
                        Text(project.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                        Text("\(countLabel(project.repositoryIDs.count, "Repository", "Repositories")) · \(countLabel(workspace.connections(for: project).count, "Service", "Services"))")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8).frame(height: 30)
                    .background(Color.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.hairline.opacity(0.7)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show \(project.name)")
            }
            ProjectMembershipMenu(store: store, ui: ui, repo: repo, title: "Add to Project")
        }
    }

    private func facts(_ repo: Repository) -> some View {
        DetailSection(title: "Details") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 7) {
                fact("Language") {
                    if let language = repo.language { HStack(spacing: 5) { LanguageDot(language: language); Text(language) } }
                    else { Text("Not Detected").foregroundStyle(.secondary) }
                }
                fact("Default Branch") { Text(repo.default_branch).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle) }
                fact("Open Issues & PRs") { Text(repo.open_issues_count.formatted()).monospacedDigit() }
                fact("Stars") { Text(repo.stargazers_count.formatted()).monospacedDigit() }
                fact("Created") {
                    if let created = repo.createdDate {
                        Text(created.formatted(date: .abbreviated, time: .omitted)).help(GroveDates.exact(created))
                    } else { Text("Unknown").foregroundStyle(.secondary) }
                }
                fact("Last Updated") { Text(GroveDates.named(repo.updatedDate)).help(GroveDates.exact(repo.updatedDate)) }
                fact("Last Pushed") {
                    let pushed = GroveDates.pushed(repo)
                    Text(pushed == nil ? "Unknown" : GroveDates.named(pushed)).help(GroveDates.exact(pushed))
                }
            }
            .font(.system(size: 12))
        }
    }
    private func fact<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).frame(width: 132, alignment: .leading).gridColumnAlignment(.leading)
            value().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
