import SwiftUI
import GroveCore

struct LibraryView: View {
    @Bindable var store: Store
    @State private var ui = WorkspaceUI()
    @FocusState private var searchFocused: Bool
    private var workspace: WorkspaceStore { store.workspace }
    private var copied: Bool { store.lastAction == "Copied" || workspace.notice == "Copied" }
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 1180
            HStack(spacing: 0) {
                LibrarySidebar(store: store, ui: ui).frame(width: compact ? 216 : 232)
                Divider().ignoresSafeArea()
                VStack(spacing: 0) {
                    toolbar(compact: compact)
                    Divider()
                    notices
                    content(width: geometry.size.width - (compact ? 217 : 233))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color.inspector)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 1040)
        .tint(.grove)
        .onChange(of: store.scope) { store.rebuild() }
        .onChange(of: store.owner) { store.rebuild() }
        .onChange(of: store.search) { store.rebuild() }
        .onChange(of: store.sort) { store.rebuild() }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.6))
            if store.lastAction == "Copied" { store.lastAction = nil }
            if workspace.notice == "Copied" { workspace.notice = nil }
        }
        .sheet(item: $store.consent) { ConsentView(store: store, item: $0) }
        .sheet(item: $store.editor) { EditorView(store: store, request: $0) }
        .sheet(item: $store.preview) { ConfirmationView(store: store, preview: $0) }
        .sheet(item: $ui.sheet) { WorkspaceSheetView(store: store, ui: ui, sheet: $0) }
        .sheet(item: Binding(get: { workspace.renameReview }, set: { if $0 == nil, !workspace.renaming { workspace.cancelRename() } })) {
            RenameReviewSheet(store: store, review: $0).interactiveDismissDisabled(workspace.renaming)
        }
        .background {
            Group {
                Button("Find") { workspace.destination = .library; searchFocused = true }.keyboardShortcut("f")
                Button("New Project") { ui.sheet = .editProject(GroveProject(name: ""), isNew: true) }.keyboardShortcut("n")
                Button("Settings") { workspace.destination = .settings }.keyboardShortcut(",")
                Button("Ask Grove") { store.showAssistant.toggle() }.keyboardShortcut("a", modifiers: [.command, .shift])
            }
            .hidden()
        }
    }

    // MARK: Columns

    @ViewBuilder private func content(width: CGFloat) -> some View {
        let listWidth: CGFloat = width >= 948 ? 360 : 300
        let dock = width - listWidth - 341 >= 440
        if workspace.destination == .settings {
            HStack(spacing: 0) {
                SettingsPane(store: store, ui: ui)
                if store.showAssistant { Divider(); AssistantView(store: store).frame(width: 340) }
            }
        } else {
            HStack(spacing: 0) {
                middle.frame(width: listWidth).frame(maxHeight: .infinity).background(Color.panel)
                Divider()
                if store.showAssistant && !dock {
                    AssistantView(store: store)
                } else {
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if store.showAssistant && dock {
                    Divider()
                    AssistantView(store: store).frame(width: 340)
                }
            }
        }
    }

    @ViewBuilder private var middle: some View {
        switch workspace.destination {
        case .projects: ProjectsColumn(store: store, ui: ui)
        case .connections: ConnectionsColumn(store: store, ui: ui)
        default: RepositoryList(store: store, ui: ui)
        }
    }

    @ViewBuilder private var detail: some View {
        switch workspace.destination {
        case .projects:
            if !ui.showAllProjects, ui.projectRepositoryID != nil, store.selected != nil {
                InspectorView(store: store, ui: ui)
            } else if let project = workspace.selectedProject {
                ProjectDetailView(store: store, ui: ui, project: project)
            } else {
                ContentUnavailableView("No Project Selected", systemImage: "square.grid.2x2",
                                       description: Text("Choose a project, or create one to group repositories and services."))
            }
        case .connections:
            if let id = ui.selectedAccountID, let account = workspace.accounts.first(where: { $0.id == id }) {
                AccountDetailView(store: store, ui: ui, account: account)
            } else if let connection = workspace.selectedConnection {
                ConnectionDetailView(store: store, ui: ui, connection: connection)
            } else {
                ContentUnavailableView("No Connection Selected", systemImage: "powerplug",
                                       description: Text("Choose a connection or an account to see its details."))
            }
        default:
            InspectorView(store: store, ui: ui)
        }
    }

    // MARK: Toolbar

    private func toolbar(compact: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(countLine).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            .layoutPriority(1)
            .contextMenu { if workspace.destination == .library { IntelligenceMenu(store: store, owner: store.owner, scope: store.scope) } }
            Spacer(minLength: 12)
            if copied { CopiedBadge() }
            switch workspace.destination {
            case .library:
                searchField.frame(width: compact ? 190 : 250)
                sortMenu
            case .projects:
                Button { ui.sheet = .editProject(GroveProject(name: ""), isNew: true) } label: { Label("New Project", systemImage: "plus") }
                    .disabled(!workspace.canEdit)
            case .connections:
                Button { ui.sheet = .editConnection(ServiceConnection(provider: .vercel, name: ""), isNew: true) } label: { Label("Add Connection", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).disabled(!workspace.canEdit)
            case .settings:
                EmptyView()
            }
            syncButton
            Button { store.showAssistant.toggle() } label: {
                Label { Text("Ask Grove") } icon: { GroveMark(size: 16, thinking: store.assistantBusy, available: Intelligence.available) }
            }
            .buttonStyle(AskGroveButtonStyle(active: store.showAssistant))
            .help(store.showAssistant ? "Hide Ask Grove (⇧⌘A)" : "Ask Grove (⇧⌘A)")
            .accessibilityAddTraits(store.showAssistant ? .isSelected : [])
        }
        .controlSize(.small)
        .padding(.leading, 18).padding(.trailing, 14)
        .frame(height: 52)
        .background(WindowDragArea())
    }

    private var syncing: Bool { store.busy || !workspace.syncing.isEmpty }
    private var syncButton: some View {
        Button {
            store.requestRefresh()
            Task { await workspace.syncAll(force: true) }
        } label: { Label("Sync Now", systemImage: "arrow.triangle.2.circlepath") }
        .buttonStyle(IconButtonStyle(size: 28, tint: syncing ? .grove : store.message != nil ? .caution : nil))
        .keyboardShortcut("r")
        .help(syncHelp)
        .accessibilityLabel(syncHelp)
        .disabled(syncing || !store.canStartReview)
    }
    private var syncHelp: String {
        if syncing { return "Syncing" }
        if let date = store.inventory?.fetchedAt { return "Sync Now. Updated \(GroveDates.named(date)) (⌘R)" }
        return "Connect to GitHub (⌘R)"
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $store.sort) {
                ForEach(RepositorySort.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(store.sort.title, systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort Repositories")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search", text: $store.search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand { store.search = ""; searchFocused = false }
                .accessibilityLabel("Search Repositories")
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

    private var title: String {
        switch workspace.destination {
        case .library: store.owner ?? store.scope.title
        case .projects: ui.showAllProjects ? "All Projects" : workspace.selectedProject?.name ?? "Projects"
        case .connections: "Connections"
        case .settings: "Settings"
        }
    }
    private var countLine: String {
        switch workspace.destination {
        case .projects:
            if !ui.showAllProjects, let project = workspace.selectedProject {
                return "Project · \(countLabel(project.repositoryIDs.count, "Repository", "Repositories")) · \(countLabel(workspace.connections(for: project).count, "Service", "Services"))"
            }
            return countLabel(workspace.projects.count, "Project", "Projects")
        case .connections:
            let attention = workspace.connections.filter { ServiceLook($0, syncing: false).attention }.count
            return countLabel(workspace.connections.count, "Connection", "Connections") + (attention > 0 ? " · \(attention.formatted()) Need Attention" : "")
        case .settings:
            return "Stored on This Mac"
        case .library:
            guard store.inventory != nil else { return store.loadingCache ? "Loading…" : "Not Connected" }
            let total = store.owner.map { store.counts.count(owner: $0) } ?? store.counts.count(store.scope)
            if store.search.isEmpty { return countLabel(total, "Repository", "Repositories") }
            return "\(store.visible.count.formatted()) of \(countLabel(total, "Repository", "Repositories"))"
        }
    }

    // MARK: Notices

    @ViewBuilder private var notices: some View {
        if store.needsRefresh {
            NoticeBar(text: "Changes are paused while Grove confirms GitHub's current state.",
                      symbol: "arrow.triangle.2.circlepath", tint: .caution,
                      actionTitle: "Sync Now", action: { store.requestRefresh() })
        }
        if let message = store.message {
            NoticeBar(text: message, symbol: "exclamationmark.triangle.fill", tint: .caution, dismiss: { store.message = nil })
        }
        if let done = store.lastAction, done != "Copied" {
            NoticeBar(text: done, symbol: "checkmark.circle.fill", tint: .grove, dismiss: { store.lastAction = nil })
        }
        if let error = workspace.error, ui.sheet == nil {
            NoticeBar(text: error, symbol: "exclamationmark.triangle.fill", tint: .caution, dismiss: { workspace.error = nil })
        }
        if let notice = workspace.notice, notice != "Copied" {
            NoticeBar(text: notice, symbol: "info.circle.fill", tint: .grove, dismiss: { workspace.notice = nil })
        }
    }
}
