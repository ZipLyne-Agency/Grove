import AppKit
import SwiftUI
import GroveCore

/// What the popover asks the app to do. Reviews and sheets live in the library window,
/// so the controller closes the popover and shows the window before handing any of these to the store.
enum PopoverIntent: Sendable {
    case library, reveal(GroveCore.Repository), copyLink(GroveCore.Repository), openOnGitHub(GroveCore.Repository)
    case ask(GroveCore.Repository?), refresh
}

/// Owns the status item and releases popover content on close.
@MainActor final class StatusController: NSObject, NSPopoverDelegate {
    private let item: NSStatusItem
    private let popover = NSPopover()
    private let store: Store
    private let openWindow: () -> Void
    static let panelSize = NSSize(width: 420, height: 580)
    init(store: Store, openWindow: @escaping () -> Void) {
        self.store = store; self.openWindow = openWindow
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = NSImage(systemSymbolName: "leaf", accessibilityDescription: "Grove")
        item.button?.toolTip = "Grove"
        item.button?.setAccessibilityLabel("Grove repositories")
        item.button?.target = self; item.button?.action = #selector(toggle)
        popover.behavior = .transient; popover.animates = false; popover.delegate = self
        #if DEBUG
        // Lets native UI checks inspect the panel after their driver restores focus.
        // Release builds always keep normal click-away dismissal.
        if ProcessInfo.processInfo.arguments.contains("--keep-quick-access-open") {
            popover.behavior = .applicationDefined
        }
        #endif
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        popover.contentViewController = NSHostingController(rootView: MenuPanel(store: store) { [weak self] intent in
            self?.handle(intent)
        })
        popover.contentSize = Self.panelSize
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--keep-quick-access-open"),
           let anchor = NSApp.windows.first(where: { $0.title == "Grove" })?.contentView {
            // The driver's background lane does not expose a visible status-bar anchor.
            popover.show(relativeTo: NSRect(x: anchor.bounds.midX, y: anchor.bounds.maxY - 20, width: 1, height: 1),
                         of: anchor, preferredEdge: .minY)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        #else
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        #endif
        popover.contentViewController?.view.window?.makeKey()
    }
    private func handle(_ intent: PopoverIntent) {
        popover.performClose(nil)
        openWindow()
        let store = self.store
        // Next turn of the run loop, so any sheet attaches to the now key library window.
        DispatchQueue.main.async {
            switch intent {
            case .library: break
            case .reveal(let repo): Self.reveal(repo, in: store)
            case .copyLink(let repo):
                Self.reveal(repo, in: store)
                if let url = repo.webURL { store.requestCopy(url.absoluteString) }
            case .openOnGitHub(let repo):
                Self.reveal(repo, in: store)
                store.requestOpen(repo)
            case .ask(let repo):
                if let repo {
                    Self.reveal(repo, in: store)
                    store.assistantFocus = .repository; store.assistantOwner = nil
                } else {
                    store.assistantFocus = .library; store.assistantOwner = nil; store.assistantScope = .all
                }
                store.showAssistant = true
            case .refresh: store.requestRefresh()
            }
        }
    }
    private static func reveal(_ repo: GroveCore.Repository, in store: Store) {
        store.owner = nil; store.scope = .all; store.search = ""
        store.selectedID = repo.id
        store.rebuild()
    }
    func popoverDidClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.popover.isShown else { return }; self.popover.contentViewController = nil
        }
    }
    func stop() { popover.performClose(nil); NSStatusBar.system.removeStatusItem(item) }
}

private struct MenuPanel: View {
    let store: Store
    let send: (PopoverIntent) -> Void
    @State private var search = ""
    @State private var ownerFilter: String?
    @State private var highlighted: Int?
    @FocusState private var searchFocused: Bool
    private static let rowLimit = 40

    private var libraryRepos: [GroveCore.Repository] {
        (store.inventory?.repositories ?? []).filter { !store.hiddenOwners.contains($0.owner.login) }
    }

    var body: some View {
        let matches = RepositoryQuery.filter(libraryRepos, scope: .all, owner: ownerFilter, search: search, sort: .pushed)
        let rows = Array(matches.prefix(Self.rowLimit))
        VStack(spacing: 0) {
            header
            if store.inventory == nil {
                disconnected
            } else {
                notices
                searchRow(rows)
                sectionLabel(matches.count, shown: rows.count)
                if rows.isEmpty { noResults } else { list(rows) }
            }
            Divider()
            footer(hasRows: !rows.isEmpty)
        }
        .frame(width: StatusController.panelSize.width, height: StatusController.panelSize.height)
        .tint(.grove)
        .onAppear { Task { searchFocused = true } }
        .onChange(of: search) { highlighted = nil }
        .onChange(of: ownerFilter) { highlighted = nil }
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
            Button { send(.ask(nil)) } label: { Label("Ask Grove", systemImage: "sparkles") }
                .buttonStyle(IconButtonStyle(size: 26, tint: .intelligence))
                .help("Ask Grove about your library")
                .disabled(store.inventory == nil || !Intelligence.available)
            Button { send(.library) } label: { Label("Open Library", systemImage: "macwindow") }
                .buttonStyle(IconButtonStyle(size: 26))
                .help("Open the Grove library")
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
    }
    private var summary: String {
        if store.busy { return "Refreshing from GitHub…" }
        guard store.inventory != nil else { return store.loadingCache ? "Loading…" : "Not connected" }
        var parts = [countLabel(libraryRepos.count, "repository", "repositories"), countLabel(store.owners.count, "owner", "owners")]
        if !store.hiddenOwners.isEmpty { parts.append("\(store.hiddenOwners.count.formatted()) hidden") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var notices: some View {
        if let message = store.message {
            notice(title: "Needs attention", text: message, symbol: "exclamationmark.triangle.fill", action: "Show", intent: .library)
        } else if store.needsRefresh {
            notice(title: "Refresh needed", text: "Changes are paused until Grove confirms GitHub's current state.",
                   symbol: "arrow.clockwise.circle.fill", action: "Refresh…", intent: .refresh)
        }
    }
    private func notice(title: String, text: String, symbol: String, action: String, intent: PopoverIntent) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(Color.caution).accessibilityHidden(true)
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

    // MARK: Search

    private func searchRow(_ rows: [GroveCore.Repository]) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search repositories", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityLabel("Search repositories")
                    .onSubmit { if let repo = target(in: rows) { send(.reveal(repo)) } }
                    .onKeyPress(.downArrow) { move(1, in: rows); return .handled }
                    .onKeyPress(.upArrow) { move(-1, in: rows); return .handled }
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
            Text(ownerFilter ?? "All owners").lineLimit(1).truncationMode(.middle)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 130)
        .fixedSize(horizontal: true, vertical: false)
        .help("Filter by owner")
    }

    private func sectionLabel(_ total: Int, shown: Int) -> some View {
        HStack {
            Text(search.isEmpty ? "Recently pushed" : countLabel(total, "match", "matches"))
            Spacer()
            if total > shown { Text("Showing \(shown) of \(total.formatted())") }
        }
        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        .padding(.horizontal, 18).padding(.top, 2).padding(.bottom, 4)
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

    // MARK: Rows

    private func list(_ rows: [GroveCore.Repository]) -> some View {
        let active = target(in: rows)?.id
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(rows) { repo in
                        PopoverRow(repo: repo, highlighted: repo.id == active, send: send).id(repo.id)
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 6)
            }
            .onChange(of: highlighted) { if let highlighted { proxy.scrollTo(highlighted) } }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var noResults: some View {
        VStack(spacing: 8) {
            if !search.isEmpty {
                Image(systemName: "magnifyingglass").font(.system(size: 26)).foregroundStyle(.secondary)
                Text("No matches").font(.system(size: 14, weight: .semibold))
                Text("Nothing\(ownerFilter.map { " in \($0)" } ?? "") matches “\(search)”.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if ownerFilter != nil { Button("Search All Owners") { ownerFilter = nil }.controlSize(.small) }
            } else if store.owners.isEmpty && !store.hiddenOwners.isEmpty {
                Image(systemName: "eye.slash").font(.system(size: 26)).foregroundStyle(.secondary)
                Text("Every owner is hidden").font(.system(size: 14, weight: .semibold))
                Text("Show an owner again from the library sidebar.").font(.system(size: 12)).foregroundStyle(.secondary)
                Button("Open Library") { send(.library) }.controlSize(.small)
            } else {
                Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(.secondary)
                Text("No repositories").font(.system(size: 14, weight: .semibold))
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
                Text("Loading your library…").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Image(systemName: "link").font(.system(size: 26)).foregroundStyle(.secondary).accessibilityHidden(true)
                Text("Connect GitHub").font(.system(size: 15, weight: .semibold))
                Text("Grove reads your repositories with your GitHub CLI sign-in. Nothing on GitHub changes.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Connect…") { send(.refresh) }.buttonStyle(.borderedProminent).padding(.top, 4)
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
            if let date = store.inventory?.fetchedAt {
                Text("Updated \(GroveDates.named(date))").help(GroveDates.exact(date)).lineLimit(1)
                Button { send(.refresh) } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(IconButtonStyle(size: 22))
                    .help("Refresh from GitHub…")
                    .disabled(store.busy)
            } else {
                Text("Reviews open in the library window.").lineLimit(1)
            }
            Spacer(minLength: 6)
            if hasRows { Text("↩ Show").foregroundStyle(.tertiary).accessibilityHidden(true) }
            Button("Open Library") { send(.library) }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct PopoverRow: View {
    let repo: GroveCore.Repository
    let highlighted: Bool
    let send: (PopoverIntent) -> Void
    @State private var hovering = false
    private var active: Bool { hovering || highlighted }
    private var detail: String {
        var parts = [repo.owner.login]
        if let language = repo.language { parts.append(language) }
        if repo.archived { parts.append("Archived") }
        if repo.hasDescription, let description = repo.description { parts.append(description) }
        else { parts.append(repo.visibilityLabel) }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(repo.language.map(Color.language) ?? Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7).padding(.top, 6).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(repo.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    if repo.private { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary).accessibilityHidden(true) }
                    Spacer(minLength: 6)
                    if !active {
                        let pushed = GroveDates.pushed(repo)
                        Text(GroveDates.short(pushed)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                            .help("Last pushed \(GroveDates.exact(pushed))")
                    }
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            if active {
                HStack(spacing: 1) {
                    Button { send(.copyLink(repo)) } label: { Label("Copy GitHub Link", systemImage: "link") }
                        .help("Copy GitHub link…")
                    Button { send(.openOnGitHub(repo)) } label: { Label("Open on GitHub", systemImage: "arrow.up.right.square") }
                        .help("Open on GitHub…")
                    Button { send(.ask(repo)) } label: { Label("Ask Grove", systemImage: "sparkles") }
                        .help("Ask Grove about this repository")
                        .disabled(!Intelligence.available)
                }
                .buttonStyle(IconButtonStyle(size: 24))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(minHeight: 46)
        .background(active ? Color.grove.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { send(.reveal(repo)) }
        .onHover { hovering = $0 }
        .help("Show in library")
        .contextMenu {
            Button("Show in Library") { send(.reveal(repo)) }
            Button("Copy GitHub Link…") { send(.copyLink(repo)) }
            Button("Open on GitHub…") { send(.openOnGitHub(repo)) }
            Button("Ask Grove…") { send(.ask(repo)) }.disabled(!Intelligence.available)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(repo.full_name), pushed \(GroveDates.named(GroveDates.pushed(repo)))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { send(.reveal(repo)) }
        .accessibilityAction(named: "Copy GitHub Link") { send(.copyLink(repo)) }
        .accessibilityAction(named: "Open on GitHub") { send(.openOnGitHub(repo)) }
        .accessibilityAction(named: "Ask Grove") { send(.ask(repo)) }
    }
}
