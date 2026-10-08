import SwiftUI
import GroveCore

/// The menu bar popover: search, pinned work, and the repository list in the persisted sort.
struct QuickAccessPanel: View {
    let store: Store
    let send: (PopoverIntent) -> Void
    @State private var search = ""
    @State private var ownerFilter: String?
    @State private var highlighted: Int?
    @State private var copied: String?
    @FocusState private var searchFocused: Bool
    static let rowLimit = 40

    private var libraryRepos: [GroveCore.Repository] {
        (store.inventory?.repositories ?? []).filter { !store.hiddenOwners.contains($0.owner.login) }
    }
    private var terms: [String] { search.split(whereSeparator: \.isWhitespace).map(String.init) }
    private var pinnedRepositories: [GroveCore.Repository] {
        libraryRepos.filter { store.workspace.isRepositoryPinned($0.id) }
            .filter { repo in terms.allSatisfy { repo.searchText.localizedCaseInsensitiveContains($0) } }
    }
    private var pinnedServices: [ServiceConnection] {
        store.workspace.connections.filter { connection in
            connection.pinned && terms.allSatisfy { term in
                [connection.name, connection.provider.title, connection.resourceID].contains { $0.localizedCaseInsensitiveContains(term) }
            }
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let matches = RepositoryQuery.filter(libraryRepos, scope: .all, owner: ownerFilter, search: search, sort: store.sort,
                                            descriptions: store.localDescriptions, integrationNames: store.localIntegrationNames)
        let rows = Array(matches.prefix(Self.rowLimit))
        VStack(spacing: 0) {
            header
            if store.inventory == nil {
                disconnected
            } else {
                notices
                searchRow(rows)
                if rows.isEmpty && pinnedServices.isEmpty && pinnedRepositories.isEmpty { noResults } else { list(rows, total: matches.count) }
            }
            Divider()
            footer(hasRows: !rows.isEmpty)
        }
        .frame(width: StatusController.panelSize.width, height: StatusController.panelSize.height)
        .tint(.grove)
        .onAppear { Task { searchFocused = true } }
        .onChange(of: search) { highlighted = nil }
        .onChange(of: ownerFilter) { highlighted = nil }
        .onChange(of: store.sort) { highlighted = nil }
        .task(id: copied) {
            guard copied != nil else { return }
            try? await Task.sleep(for: .seconds(1.6)); copied = nil
        }
    }

    // MARK: Header and notices

    private var header: some View {
        HStack(spacing: 9) {
            LeafMark(size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text("Grove").font(.system(size: 14, weight: .semibold))
                HStack(spacing: 5) {
                    if store.busy { ProgressView().controlSize(.mini) }
                    Text(summary).monospacedDigit().lineLimit(1)
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { send(.ask(nil)) } label: { Label { Text("Ask Grove") } icon: { GroveMark(size: 16, available: Intelligence.available) } }
                .buttonStyle(IconButtonStyle(size: 26, tint: .ember))
                .help("Ask Grove About Your Library")
                .disabled(store.inventory == nil || !Intelligence.available)
            Button { send(.library) } label: { Label("Open Grove", systemImage: "macwindow") }
                .buttonStyle(IconButtonStyle(size: 26))
                .help("Open Grove")
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
    }
    private var summary: String {
        if store.busy { return "Syncing Quietly…" }
        guard store.inventory != nil else { return store.loadingCache ? "Loading…" : "Not Connected" }
        var parts = [countLabel(libraryRepos.count, "Repository", "Repositories"), countLabel(store.owners.count, "Owner", "Owners")]
        if !store.hiddenOwners.isEmpty { parts.append("\(store.hiddenOwners.count.formatted()) Hidden") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var notices: some View {
        if let message = store.message {
            notice(title: "Couldn't Sync", text: message + " Saved data is still shown.", action: "Show", intent: .library)
        } else if store.needsRefresh {
            notice(title: "Changes Paused", text: "Grove is confirming GitHub's current state.", action: "Sync Now", intent: .refresh)
        }
    }
    private func notice(title: String, text: String, action: String, intent: PopoverIntent) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.caution).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 6)
            Button(action) { send(intent) }.controlSize(.small)
        }
        .padding(10)
        .background(Color.caution.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 14).padding(.bottom, 10)
    }

    // MARK: Search, owner, sort

    private func searchRow(_ rows: [GroveCore.Repository]) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search Repositories and Pinned", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityLabel("Search Repositories and Pinned Items")
                    .onSubmit { if let repo = target(in: rows) { send(.reveal(repo)) } }
                    .onKeyPress(.downArrow) { move(1, in: rows); return .handled }
                    .onKeyPress(.upArrow) { move(-1, in: rows); return .handled }
                    .onExitCommand { if search.isEmpty { send(.dismiss) } else { search = "" } }
                if !search.isEmpty {
                    Button { search = "" } label: { Label("Clear Search", systemImage: "xmark.circle.fill") }
                        .buttonStyle(IconButtonStyle(size: 18))
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 9).frame(height: 30)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(searchFocused ? Color.grove.opacity(0.85) : Color.hairline, lineWidth: searchFocused ? 1.5 : 1))
            if store.owners.count > 1 { ownerMenu }
            sortMenu
        }
        .padding(.horizontal, 14).padding(.bottom, 8)
    }

    private var ownerMenu: some View {
        Menu {
            Picker("Owner", selection: $ownerFilter) {
                Text("All Owners").tag(String?.none)
                Divider()
                ForEach(store.owners, id: \.self) { owner in
                    Text("\(owner)  \(store.counts.count(owner: owner).formatted())").tag(String?.some(owner))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(ownerFilter ?? "All Owners").lineLimit(1).truncationMode(.middle)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 110)
        .fixedSize(horizontal: true, vertical: false)
        .help("Filter by Owner")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: Binding(get: { store.sort }, set: { store.sort = $0 })) {
                ForEach(RepositorySort.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Sort: \(store.sort.title)")
        .accessibilityLabel("Sort Repositories, \(store.sort.title)")
    }

    private func target(in rows: [GroveCore.Repository]) -> GroveCore.Repository? {
        if let highlighted, let repo = rows.first(where: { $0.id == highlighted }) { return repo }
        return search.isEmpty ? nil : rows.first
    }
    private func move(_ step: Int, in rows: [GroveCore.Repository]) {
        guard !rows.isEmpty else { return }
        let current = highlighted.flatMap { id in rows.firstIndex { $0.id == id } }
        let next = current.map { min(max($0 + step, 0), rows.count - 1) } ?? (step > 0 ? 0 : rows.count - 1)
        highlighted = rows[next].id
    }

    // MARK: Results

    private func list(_ rows: [GroveCore.Repository], total: Int) -> some View {
        let active = target(in: rows)?.id
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if !pinnedRepositories.isEmpty || !pinnedServices.isEmpty {
                        sectionLabel("Pinned", trailing: nil)
                        ForEach(pinnedRepositories) { repo in
                            QuickAccessRow(repo: repo, description: store.workspace.profile(for: repo.id)?.summary, highlighted: false,
                                           reveal: { send(.reveal(repo)) },
                                           copy: { if let url = repo.webURL { Clipboard.copy(url.absoluteString); copied = "Copied Link" } },
                                           open: { store.requestOpen(repo); send(.dismiss) },
                                           ask: { send(.ask(repo)) })
                        }
                        ForEach(pinnedServices) { connection in
                            PinnedServiceRow(connection: connection, look: ServiceLook(connection, syncing: store.workspace.syncing.contains(connection.id)),
                                             copy: { Clipboard.copy(connection.dashboardURL); copied = "Copied \(connection.name) Link" },
                                             open: { store.workspace.open(connection); send(.dismiss) })
                        }
                    }
                    if !rows.isEmpty {
                        sectionLabel(search.isEmpty ? store.sort.title : countLabel(total, "Match", "Matches"),
                                     trailing: total > rows.count ? "Showing \(rows.count) of \(total.formatted())" : nil)
                    }
                    ForEach(rows) { repo in
                        QuickAccessRow(repo: repo, description: store.workspace.profile(for: repo.id)?.summary, highlighted: repo.id == active,
                                       reveal: { send(.reveal(repo)) },
                                       copy: { if let url = repo.webURL { Clipboard.copy(url.absoluteString); copied = "Copied Link · \(repo.full_name)" } },
                                       open: { store.requestOpen(repo); send(.dismiss) },
                                       ask: { send(.ask(repo)) })
                            .id(repo.id)
                    }
                    if total > rows.count {
                        Button { send(.showAll(query: search, owner: ownerFilter)) } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(countLabel(total - rows.count, "More Repository", "More Repositories")).font(.system(size: 12.5, weight: .semibold))
                                    Text("Quick Access lists the first \(Self.rowLimit). The full list is in the Grove window.").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 6)
                                Text("See All in Grove").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.groveInk)
                            }
                            .padding(.horizontal, 10).frame(minHeight: 44)
                            .background(Color.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.hairline.opacity(0.7)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 6)
            }
            .scrollIndicators(.never)
            .onChange(of: highlighted) { if let highlighted { proxy.scrollTo(highlighted) } }
        }
        .frame(maxHeight: .infinity)
    }

    private func sectionLabel(_ title: String, trailing: String?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let trailing { Text(trailing).fontWeight(.regular) }
        }
        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 3)
    }

    @ViewBuilder private var noResults: some View {
        VStack(spacing: 8) {
            if !search.isEmpty {
                Image(systemName: "magnifyingglass").font(.system(size: 26)).foregroundStyle(.secondary)
                Text("No Matches").font(.system(size: 14, weight: .semibold))
                Text("Nothing\(ownerFilter.map { " in \($0)" } ?? "") matches “\(search)”.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if ownerFilter != nil { Button("Search All Owners") { ownerFilter = nil }.controlSize(.small) }
            } else if store.owners.isEmpty && !store.hiddenOwners.isEmpty {
                Image(systemName: "eye.slash").font(.system(size: 26)).foregroundStyle(.secondary)
                Text("Every Owner Is Hidden").font(.system(size: 14, weight: .semibold))
                Text("Show an owner again from the Grove sidebar.").font(.system(size: 12)).foregroundStyle(.secondary)
                Button("Open Grove") { send(.library) }.controlSize(.small)
            } else {
                Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(.secondary)
                Text("No Repositories").font(.system(size: 14, weight: .semibold))
                Text("This account can't see any repositories yet.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var disconnected: some View {
        VStack(spacing: 8) {
            if store.loadingCache {
                ProgressView().controlSize(.small)
                Text("Loading Your Library…").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Image(systemName: "link").font(.system(size: 26)).foregroundStyle(.secondary).accessibilityHidden(true)
                Text("Connect GitHub").font(.system(size: 15, weight: .semibold))
                Text("Grove reads your repositories with your GitHub CLI sign-in. Nothing on GitHub changes.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Connect") { store.requestRefresh() }.buttonStyle(.borderedProminent).padding(.top, 4)
                    .disabled(store.busy)
                if let message = store.message {
                    Text(message).font(.system(size: 11)).foregroundStyle(Color.caution).multilineTextAlignment(.center)
                        .lineLimit(4).padding(.top, 6)
                }
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func footer(hasRows: Bool) -> some View {
        HStack(spacing: 8) {
            if let copied {
                CopiedBadge(text: copied)
            } else if let date = store.inventory?.fetchedAt {
                Text("Synced \(GroveDates.named(date))").help(GroveDates.exact(date)).lineLimit(1)
                Button { store.requestRefresh() } label: { Label("Sync Now", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(IconButtonStyle(size: 22))
                    .help("Sync Now")
                    .disabled(store.busy || !store.canStartReview)
            }
            Spacer(minLength: 6)
            if hasRows && copied == nil { Text("↑↓ Select · ↩ Show").foregroundStyle(.tertiary).accessibilityHidden(true) }
            Button("Open Grove") { send(.library) }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
