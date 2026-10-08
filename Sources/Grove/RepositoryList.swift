import SwiftUI
import GroveCore

struct RepositoryList: View {
    @Bindable var store: Store
    let ui: WorkspaceUI
    @FocusState private var focused: Bool
    var body: some View {
        Group {
            if store.inventory == nil {
                if store.loadingCache {
                    ProgressView("Loading Your Library…").controlSize(.small)
                } else {
                    ContentUnavailableView {
                        Label("Connect GitHub", systemImage: "link")
                    } description: {
                        Text("Grove reads your repositories with your GitHub CLI sign-in. Nothing on GitHub changes.")
                    } actions: {
                        Button("Connect") { store.requestRefresh() }.buttonStyle(.borderedProminent).disabled(store.busy || !store.canStartReview)
                    }
                }
            } else if store.visible.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(store.visible) { repo in
                        RepositoryRow(repo: repo, store: store, selected: store.selectedID == repo.id)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture { store.selectedID = repo.id; focused = true }
                            .rowPlate(selected: store.selectedID == repo.id)
                            .contextMenu { RepositoryMenu(store: store, repo: repo) }
                            .accessibilityAction { store.selectedID = repo.id }
                            .id(repo.id)
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.never)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onKeyPress(.home) { select(store.visible.first); return .handled }
            .onKeyPress(.end) { select(store.visible.last); return .handled }
            .onKeyPress(.return) { if let repo = store.selected { store.requestOpen(repo) }; return .handled }
            .onChange(of: store.selectedID) { if let id = store.selectedID { proxy.scrollTo(id) } }
        }
    }
    private func move(_ step: Int) {
        let rows = store.visible
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == store.selectedID }
        let next = current.map { min(max($0 + step, 0), rows.count - 1) } ?? (step > 0 ? 0 : rows.count - 1)
        store.selectedID = rows[next].id
    }
    private func select(_ repo: Repository?) { if let repo { store.selectedID = repo.id } }

    @ViewBuilder private var emptyState: some View {
        if !store.search.isEmpty {
            ContentUnavailableView {
                Label("No Matches", systemImage: "magnifyingglass")
            } description: {
                Text("Nothing in \(store.owner ?? store.scope.title) matches “\(store.search)”.")
            } actions: {
                HStack {
                    Button("Clear Search") { store.search = "" }
                    if store.owner != nil || store.scope != .all {
                        Button("Search All Repositories") { store.owner = nil; store.scope = .all }
                    }
                }
            }
        } else if store.owners.isEmpty && !store.hiddenOwners.isEmpty {
            ContentUnavailableView("Every Owner Is Hidden", systemImage: "eye.slash",
                                   description: Text("Show an owner again from Hidden in the sidebar."))
        } else {
            ContentUnavailableView(emptyTitle, systemImage: store.scope.symbol, description: Text(emptyDetail))
        }
    }
    private var emptyTitle: String {
        if store.owner != nil { return "No Repositories" }
        switch store.scope {
        case .all: return "No Repositories"
        case .recent: return "Nothing Pushed Recently"
        case .missing: return "Every Repository Has a Description"
        case .archived: return "No Archived Repositories"
        case .forks: return "No Forks"
        }
    }
    private var emptyDetail: String {
        if let owner = store.owner { return "\(owner) has no repositories this account can see." }
        switch store.scope {
        case .recent: return "No repository was pushed in the last 30 days."
        default: return "Nothing to show here."
        }
    }
}

struct RepositoryRow: View {
    let repo: Repository
    let store: Store
    let selected: Bool
    var showsProjects = true
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var showActions: Bool { hovering || selected }
    private var rowDate: Date? {
        switch store.sort {
        case .createdNewest, .createdOldest: repo.createdDate
        case .updatedNewest, .updatedOldest: repo.updatedDate
        default: GroveDates.pushed(repo)
        }
    }
    private var dateLabel: String {
        switch store.sort {
        case .createdNewest, .createdOldest: "Created"
        case .updatedNewest, .updatedOldest: "Last Updated"
        default: "Last Pushed"
        }
    }
    private var dateText: String {
        if store.sort == .createdNewest || store.sort == .createdOldest {
            return rowDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"
        }
        return GroveDates.short(rowDate)
    }
    private var projectLabel: String? {
        guard showsProjects else { return nil }
        let names = store.workspace.archive.projects(for: repo.id).map(\.name).sorted()
        guard let first = names.first else { return nil }
        return names.count > 1 ? "\(first) +\(names.count - 1)" : first
    }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RepositoryGlyph(repo: repo, size: 28).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(repo.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        .layoutPriority(1)
                    if store.owner == nil {
                        Text(repo.owner.login).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    ZStack(alignment: .trailing) {
                        Text(dateText).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                            .help("\(dateLabel): \(rowDate.map { GroveDates.exact($0) } ?? "Unknown")")
                            .opacity(showActions ? 0 : 1)
                        if showActions { actions.transition(.opacity) }
                    }
                    .frame(height: 16)
                    .fixedSize()
                }
                Text(repo.hasDescription ? (repo.description ?? "") : "No Description")
                    .font(.system(size: 12))
                    .foregroundStyle(repo.hasDescription ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                    .lineLimit(1)
                meta
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { inside in
            if reduceMotion { hovering = inside } else { withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(repo.full_name), \(repo.visibilityLabel)\(repo.archived ? ", archived" : "")\(projectLabel.map { ", in \($0)" } ?? "")")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction(named: "Copy Link") { copyLink() }
        .accessibilityAction(named: "Open on GitHub") { store.requestOpen(repo) }
        .accessibilityAction(named: "Ask Grove") { ask() }
    }

    private var meta: some View {
        HStack(spacing: 10) {
            if let language = repo.language {
                HStack(spacing: 4) { LanguageDot(language: language, size: 7); Text(language) }
            }
            Label(repo.visibilityLabel, systemImage: repo.visibilitySymbol).labelStyle(CompactLabelStyle())
            if repo.archived { Label("Archived", systemImage: "archivebox").labelStyle(CompactLabelStyle()) }
            if repo.fork { Label("Fork", systemImage: "arrow.triangle.branch").labelStyle(CompactLabelStyle()) }
            if let projectLabel {
                Label(projectLabel, systemImage: "square.grid.2x2").labelStyle(CompactLabelStyle())
                    .foregroundStyle(Color.groveInk).truncationMode(.tail)
            } else if repo.stargazers_count > 0 {
                Label(repo.stargazers_count.formatted(), systemImage: "star").labelStyle(CompactLabelStyle())
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var actions: some View {
        HStack(spacing: 1) {
            Button { copyLink() } label: { Label("Copy Link", systemImage: "link") }
                .help("Copy Link")
            Button { store.requestOpen(repo) } label: { Label("Open on GitHub", systemImage: "arrow.up.right") }
                .help("Open on GitHub")
        }
        .buttonStyle(IconButtonStyle(size: 22))
    }

    private func copyLink() { if let url = repo.webURL { store.requestCopy(url.absoluteString) } }
    private func ask() {
        store.selectedID = repo.id; store.assistantFocus = .repository; store.assistantProjectID = nil
        store.assistantOwner = nil; store.showAssistant = true
    }
}
