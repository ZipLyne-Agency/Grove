import SwiftUI
import GroveCore

struct LibraryView: View {
    @Bindable var store: Store
    @FocusState private var searchFocused: Bool
    var body: some View {
        HStack(spacing: 0) {
            LibrarySidebar(store: store).frame(width: 232)
            Divider().ignoresSafeArea()
            VStack(spacing: 0) {
                toolbar
                Divider()
                notices
                HSplitView {
                    RepositoryList(store: store)
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                    Group {
                        if store.showAssistant { AssistantView(store: store) } else { InspectorView(store: store) }
                    }
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 440, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.panel)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 1040)
        .tint(.grove)
        .onChange(of: store.scope) { store.rebuild() }
        .onChange(of: store.owner) { store.rebuild() }
        .onChange(of: store.search) { store.rebuild() }
        .onChange(of: store.sort) { store.rebuild() }
        .sheet(item: $store.consent) { ConsentView(store: store, item: $0) }
        .sheet(item: $store.editor) { EditorView(store: store, request: $0) }
        .sheet(item: $store.preview) { ConfirmationView(store: store, preview: $0) }
        .background {
            Button("Find") { searchFocused = true }.keyboardShortcut("f").hidden()
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(store.title).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(countLine).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            .layoutPriority(1)
            .contextMenu { IntelligenceMenu(store: store, owner: store.owner, scope: store.scope) }
            Spacer(minLength: 12)
            searchField.frame(minWidth: 180, idealWidth: 260, maxWidth: 300)
            Menu {
                Picker("Sort By", selection: $store.sort) {
                    ForEach(RepositorySort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(store.sort.rawValue, systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Sort repositories")
            Button { store.requestRefresh() } label: {
                if store.busy { ProgressView().controlSize(.small) }
                else { Label(store.inventory == nil ? "Connect" : "Refresh", systemImage: "arrow.clockwise") }
            }
            .buttonStyle(IconButtonStyle(size: 28))
            .keyboardShortcut("r")
            .help(store.inventory == nil ? "Connect to GitHub (⌘R)" : "Refresh from GitHub (⌘R)")
            .accessibilityLabel(store.busy ? "Refreshing" : store.inventory == nil ? "Connect to GitHub" : "Refresh from GitHub")
            .disabled(store.busy || !store.canStartReview)
            Button { store.showAssistant.toggle() } label: { Label("Ask Grove", systemImage: "sparkles") }
                .buttonStyle(IconButtonStyle(size: 28, tint: .intelligence, active: store.showAssistant))
                .help(store.showAssistant ? "Hide assistant" : "Ask Grove")
                .accessibilityAddTraits(store.showAssistant ? .isSelected : [])
        }
        .padding(.leading, 18).padding(.trailing, 12)
        .frame(height: 52)
        .background(WindowDragArea())
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search", text: $store.search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand { store.search = ""; searchFocused = false }
                .accessibilityLabel("Search repositories")
            if !store.search.isEmpty {
                Button { store.search = "" } label: { Label("Clear Search", systemImage: "xmark.circle.fill") }
                    .buttonStyle(IconButtonStyle(size: 18))
            } else if !searchFocused {
                Text("⌘F").font(.system(size: 11)).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(searchFocused ? Color.grove.opacity(0.8) : Color.clear, lineWidth: 1.5))
    }

    private var countLine: String {
        guard store.inventory != nil else { return store.loadingCache ? "Loading…" : "Not connected" }
        let total = store.owner.map { store.counts.count(owner: $0) } ?? store.counts.count(store.scope)
        if store.search.isEmpty { return countLabel(total, "repository", "repositories") }
        return "\(store.visible.count.formatted()) of \(countLabel(total, "repository", "repositories"))"
    }

    // MARK: Notices

    @ViewBuilder private var notices: some View {
        if store.needsRefresh {
            NoticeBar(text: "Changes are paused until you refresh, so Grove can confirm GitHub's current state.",
                      symbol: "arrow.clockwise.circle", tint: .caution,
                      actionTitle: "Refresh…", action: { store.requestRefresh() })
        }
        if let message = store.message {
            NoticeBar(text: message, symbol: "exclamationmark.triangle.fill", tint: .caution, dismiss: { store.message = nil })
        }
        if let done = store.lastAction {
            NoticeBar(text: done, symbol: "checkmark.circle.fill", tint: .grove, dismiss: { store.lastAction = nil })
        }
    }
}

// MARK: Sidebar

private enum SidebarItem: Hashable { case scope(LibraryScope), owner(String) }

struct LibrarySidebar: View {
    @Bindable var store: Store
    private var selection: Binding<SidebarItem?> {
        Binding(get: { store.owner.map { .owner($0) } ?? .scope(store.scope) }, set: { item in
            switch item {
            case .scope(let scope): store.owner = nil; store.scope = scope
            case .owner(let owner): store.scope = .all; store.owner = owner
            case nil: break
            }
        })
    }
    private var account: String? { store.inventory?.account.login }
    private var ownerRows: [String] {
        let others = store.owners.filter { $0 != account }
        if let account, store.owners.contains(account) { return [account] + others }
        return others
    }
    var body: some View {
        VStack(spacing: 0) {
            WindowDragArea().frame(height: 44)
            List(selection: selection) {
                Section("Library") {
                    ForEach(LibraryScope.allCases, id: \.self) { scope in
                        Label(scope.rawValue, systemImage: scope.symbol)
                            .badge(store.inventory == nil ? 0 : store.counts.count(scope))
                            .tag(SidebarItem.scope(scope))
                            .contextMenu { ScopeMenu(store: store, scope: scope) }
                    }
                }
                Section("Owners") {
                    if store.inventory == nil {
                        Text(store.loadingCache ? "Loading…" : "Connect to see owners").foregroundStyle(.secondary)
                    } else if ownerRows.isEmpty {
                        Text("Every owner is hidden").foregroundStyle(.secondary)
                    }
                    ForEach(ownerRows, id: \.self) { owner in
                        Label { Text(owner).lineLimit(1).truncationMode(.middle) } icon: {
                            Image(systemName: owner == account ? "person.crop.circle" : "building.2")
                        }
                        .badge(store.counts.count(owner: owner))
                        .help(owner)
                        .tag(SidebarItem.owner(owner))
                        .contextMenu { OwnerMenu(store: store, owner: owner) }
                    }
                    if !store.hiddenOwners.isEmpty { hiddenOwnersRow }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            footer
        }
        .background(VisualEffectBackground(material: .sidebar).ignoresSafeArea())
    }

    private var hiddenOwnersRow: some View {
        Menu {
            Section("Show in Grove") {
                ForEach(store.hiddenOwners.sorted(), id: \.self) { owner in
                    Button("\(owner) (\(store.counts.count(owner: owner).formatted()))…") { store.requestOwnerVisibility(owner, hidden: false) }
                }
            }
        } label: {
            Label("\(store.hiddenOwners.count.formatted()) hidden", systemImage: "eye.slash")
        }
        .menuStyle(.borderlessButton)
        .foregroundStyle(.secondary)
        .disabled(!store.canStartReview)
        .help("Owners hidden from this Mac. Choose one to show it again.")
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button { store.showAssistant.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles").accessibilityHidden(true)
                    Text("Ask Grove")
                    Spacer(minLength: 0)
                    if store.assistantBusy { ProgressView().controlSize(.mini) }
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.intelligence)
                .padding(.horizontal, 10).frame(height: 30)
                .background(Color.intelligence.opacity(store.showAssistant ? 0.2 : 0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(store.showAssistant ? .isSelected : [])
            Divider()
            HStack(spacing: 9) {
                Text(String((account ?? "?").prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(account == nil ? Color.secondary : Color.grove, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account ?? "Not connected").font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Group {
                        if store.busy { Text("Refreshing from GitHub…") }
                        else if let date = store.inventory?.fetchedAt { Text("Updated \(GroveDates.named(date))").help(GroveDates.exact(date)) }
                        else { Text("GitHub CLI sign-in") }
                    }
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 12)
    }
}

// MARK: Repository list

struct RepositoryList: View {
    @Bindable var store: Store
    var body: some View {
        Group {
            if store.inventory == nil {
                if store.loadingCache {
                    ProgressView("Loading your library…").controlSize(.small)
                } else {
                    ContentUnavailableView {
                        Label("Connect GitHub", systemImage: "link")
                    } description: {
                        Text("Grove reads your repositories with your GitHub CLI sign-in. Nothing on GitHub changes.")
                    } actions: {
                        Button("Connect…") { store.requestRefresh() }.buttonStyle(.borderedProminent).disabled(store.busy || !store.canStartReview)
                    }
                }
            } else if store.visible.isEmpty {
                emptyState
            } else {
                List(selection: $store.selectedID) {
                    ForEach(store.visible) { repo in
                        RepositoryRow(repo: repo, store: store, selected: store.selectedID == repo.id)
                            .tag(repo.id)
                            .contextMenu { RepositoryMenu(store: store, repo: repo) }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var emptyState: some View {
        if !store.search.isEmpty {
            ContentUnavailableView {
                Label("No Matches", systemImage: "magnifyingglass")
            } description: {
                Text("Nothing in \(store.title) matches “\(store.search)”.")
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
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var showActions: Bool { hovering || selected }
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
                        let pushed = GroveDates.pushed(repo)
                        Text(GroveDates.short(pushed)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                            .help("Last pushed \(GroveDates.exact(pushed))")
                            .opacity(showActions ? 0 : 1)
                        if showActions { actions.transition(.opacity) }
                    }
                    .frame(height: 16)
                }
                Text(repo.hasDescription ? (repo.description ?? "") : "No description")
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
        .accessibilityLabel("\(repo.full_name), \(repo.visibilityLabel)\(repo.archived ? ", archived" : "")")
        .accessibilityAction(named: "Copy GitHub Link") { copyLink() }
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
            if repo.stargazers_count > 0 {
                Label(repo.stargazers_count.formatted(), systemImage: "star").labelStyle(CompactLabelStyle())
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var actions: some View {
        HStack(spacing: 1) {
            Button { copyLink() } label: { Label("Copy GitHub Link", systemImage: "link") }
                .help("Copy GitHub link")
            Button { store.requestOpen(repo) } label: { Label("Open on GitHub", systemImage: "arrow.up.right.square") }
                .help("Open on GitHub")
            Button { ask() } label: { Label("Ask Grove", systemImage: "sparkles") }
                .help("Ask Grove about this repository")
                .disabled(!Intelligence.available)
        }
        .buttonStyle(IconButtonStyle(size: 22))
        .disabled(!store.canStartReview)
    }

    private func copyLink() { if let url = repo.webURL { store.requestCopy(url.absoluteString) } }
    private func ask() {
        store.selectedID = repo.id; store.assistantFocus = .repository; store.assistantOwner = nil; store.showAssistant = true
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon.imageScale(.small); configuration.title }
    }
}
