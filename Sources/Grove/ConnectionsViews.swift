import SwiftUI
import AppKit
import GroveCore

struct ConnectionsColumn: View {
    @Bindable var store: Store
    let ui: WorkspaceUI
    private var workspace: WorkspaceStore { store.workspace }
    private struct ConnectionGroup: Identifiable {
        let id: String
        let hint: String
        let items: [ServiceConnection]
    }
    private var groups: [ConnectionGroup] {
        let all = workspace.connections.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let attention: Set<ConnectionStatus> = [.failed, .needsAuthorization]
        let checked: Set<ConnectionStatus> = [.verified, .stale, .unverified]
        return [
            ConnectionGroup(id: "Needs Attention", hint: "Grove could not read these", items: all.filter { attention.contains($0.status()) }),
            ConnectionGroup(id: "Verified", hint: "Checked with an account", items: all.filter { checked.contains($0.status()) }),
            ConnectionGroup(id: "Saved Links", hint: "Opened, never checked", items: all.filter { $0.status() == .savedLink }),
            ConnectionGroup(id: "Suggested", hint: "Found in repository configuration", items: all.filter { $0.status() == .suggested })
        ].filter { !$0.items.isEmpty }
    }
    var body: some View {
        Group {
            if workspace.loading {
                ProgressView("Loading Connections…").controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        if workspace.connections.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("No Connections Yet").font(.system(size: 13, weight: .semibold))
                                Text("Add a service with an account to see its status, or save a dashboard link. Discover Services is in each repository's Services tab.")
                                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                        }
                        ForEach(groups) { group in
                            header(group.id, hint: group.hint)
                            ForEach(group.items) { connection in
                                Button {
                                    workspace.selectedConnectionID = connection.id; ui.selectedAccountID = nil
                                } label: { ConnectionListRow(store: store, connection: connection) }
                                .buttonStyle(.plain)
                                .rowPlate(selected: ui.selectedAccountID == nil && workspace.selectedConnectionID == connection.id)
                                .contextMenu { ServiceMenu(store: store, ui: ui, connection: connection) }
                            }
                        }
                        accounts
                    }
                    .padding(6)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var accounts: some View {
        HStack {
            header("Accounts", hint: "Credentials in macOS Keychain")
            Menu {
                ForEach(ServiceProvider.allCases.filter(\.supportsAPI)) { provider in
                    Button(provider.title) { ui.sheet = .editAccount(ProviderAccount(provider: provider, name: ""), isNew: true) }
                }
            } label: { Image(systemName: "plus") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Add Account").help("Add Account")
            .disabled(!workspace.canEdit)
            .padding(.trailing, 8).padding(.top, 10)
        }
        if workspace.accounts.isEmpty {
            Text("No accounts. Saved links work without one.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 4)
        }
        ForEach(workspace.accounts) { account in
            Button { ui.selectedAccountID = account.id } label: {
                HStack(spacing: 10) {
                    ProviderTile(provider: account.provider)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text("\(account.provider.title) · \(countLabel(usage(account), "Service", "Services"))")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).frame(minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .rowPlate(selected: ui.selectedAccountID == account.id)
        }
    }
    private func header(_ title: String, hint: String) -> some View {
        HStack(spacing: 6) {
            SectionHeader(title)
            Text(hint).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 3)
    }
    private func usage(_ account: ProviderAccount) -> Int { workspace.connections.filter { $0.accountID == account.id }.count }
}

struct ConnectionListRow: View {
    let store: Store
    let connection: ServiceConnection
    var body: some View {
        let look = ServiceLook(connection, syncing: store.workspace.syncing.contains(connection.id))
        HStack(spacing: 10) {
            ProviderTile(provider: connection.provider)
                .overlay {
                    if look.dashed {
                        RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(connection.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    if connection.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary).accessibilityLabel("Pinned") }
                }
                Text("\(connection.provider.title) · \(connection.displayIdentity)").font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 6)
            Label(look.badge, systemImage: look.badgeSymbol).labelStyle(CompactLabelStyle())
                .font(.system(size: 11)).foregroundStyle(look.tint).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 10).frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

struct ConnectionDetailView: View {
    @Bindable var store: Store
    let ui: WorkspaceUI
    let connection: ServiceConnection
    @State private var copied = false
    private var workspace: WorkspaceStore { store.workspace }
    var body: some View {
        let look = ServiceLook(connection, syncing: workspace.syncing.contains(connection.id))
        let account = workspace.account(for: connection)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    ProviderTile(provider: connection.provider, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(connection.name).font(.system(size: 20, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Text([connection.provider.title, account?.name].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    KindBadge(look: look)
                }
                actions(look: look, account: account)
                if look.attention || look.dimmed {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: look.lineSymbol).foregroundStyle(look.attention ? Color.caution : Color.secondary).accessibilityHidden(true)
                        Text(look.line + (connection.snapshot.map { " Showing data checked \(GroveDates.exact($0.checkedAt))." } ?? ""))
                            .font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((look.attention ? Color.caution : Color.secondary).opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                DetailSection(title: "Details") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                        fact("Service", connection.provider.title)
                        fact(connection.provider.resourceLabel, connection.resourceID.isEmpty ? "Not Set" : connection.resourceID, mono: !connection.resourceID.isEmpty)
                        fact("Environment", connection.environment.isEmpty ? "None" : connection.environment)
                        fact("Connection", account.map { "Checked With \($0.name)" } ?? "Saved Link · Not Checked")
                        if account != nil { fact("Credential", "Stored in macOS Keychain · Never Shown") }
                        fact("Source", sourceText)
                        fact("Last Successful Check", connection.snapshot.map { GroveDates.exact($0.checkedAt) } ?? "Never")
                        if let attempted = connection.lastAttemptAt { fact("Last Attempt", GroveDates.exact(attempted)) }
                        fact("Dashboard", connection.dashboardURL.isEmpty ? "Not Set" : connection.dashboardURL, mono: true)
                    }
                    .font(.system(size: 12))
                    if connection.provider == .googlePlay {
                        FinePrint("Grove checks that this account can read the package. Releases, reviews, and vitals are not retained; open Play Console for them.")
                    }
                }
                if let snapshot = connection.snapshot, !(snapshot.metrics.isEmpty && snapshot.details.isEmpty) {
                    DetailSection(title: "From \(connection.provider.title)", caption: "Checked \(GroveDates.named(snapshot.checkedAt))") {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                            ForEach(Array((snapshot.metrics + snapshot.details).enumerated()), id: \.offset) { _, metric in fact(metric.label, metric.value) }
                        }
                        .font(.system(size: 12)).opacity(look.dimmed ? 0.6 : 1)
                        if let notice = snapshot.notice { FinePrint(notice) }
                    }
                }
                DetailSection(title: "Used In") { usedIn }
                if !connection.notes.isEmpty {
                    DetailSection(title: "Notes") {
                        Text(connection.notes).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                }
                DetailSection(title: "Recent Activity") {
                    ActivityList(items: ActivityFeed.items(connections: [connection], repositories: []), limit: 10)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Removing this connection takes it out of every repository and project in Grove. Nothing changes at \(connection.provider.title).")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Remove Connection…") { ui.sheet = .removeConnection(connection) }
                        .foregroundStyle(Color.danger).controlSize(.small).disabled(!workspace.canEdit)
                }
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.hairline.opacity(0.7)))
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .background(Color.inspector)
    }

    private func actions(look: ServiceLook, account: ProviderAccount?) -> some View {
        HStack(spacing: 8) {
            if look.attention {
                Button(connection.status() == .needsAuthorization && account != nil ? "Update Account…" : "Try Again") {
                    if connection.status() == .needsAuthorization, let account { ui.sheet = .editAccount(account, isNew: false) }
                    else { workspace.requestSync(connection.id) }
                }
                .buttonStyle(.borderedProminent).disabled(!workspace.canEdit)
            } else if connection.status() == .suggested {
                Button("Connect…") { ui.sheet = .editConnection(connection, isNew: false) }.buttonStyle(.borderedProminent).disabled(!workspace.canEdit)
            } else if connection.provider.supportsAPI && account != nil {
                Button("Sync Now") { workspace.requestSync(connection.id) }.disabled(workspace.syncing.contains(connection.id) || !workspace.canEdit)
            }
            Button { workspace.open(connection) } label: { Label("Open Dashboard", systemImage: "arrow.up.right") }.disabled(!connection.canOpen)
            Button { Clipboard.copy(connection.dashboardURL); flash() } label: {
                Label(copied ? "Copied" : "Copy Link", systemImage: copied ? "checkmark" : "link")
            }
            .disabled(!connection.canOpen)
            Button("Edit…") { ui.sheet = .editConnection(connection, isNew: false) }.disabled(!workspace.canEdit)
            Menu { ServiceMenu(store: store, ui: ui, connection: connection, onCopy: flash) } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("More Connection Actions")
        }
        .controlSize(.small)
    }

    @ViewBuilder private var usedIn: some View {
        let repos = (store.inventory?.repositories ?? []).filter { connection.repositoryIDs.contains($0.id) }
        let projects = workspace.archive.projects.filter { connection.projectIDs.contains($0.id) }
        if repos.isEmpty && projects.isEmpty {
            Text("Not linked to any repository or project. Use Edit to choose where it appears.").font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
            TableBox {
                ForEach(projects) { project in
                    linkRow(title: project.name, detail: "Project", target: .project(project.id)) { ProjectTile(project: project, size: 20) }
                }
                ForEach(repos) { repo in
                    linkRow(title: repo.full_name, detail: "Repository", target: .repository(repo.id)) { RepositoryGlyph(repo: repo, size: 20) }
                }
            }
        }
    }
    private func linkRow<Icon: View>(title: String, detail: String, target: LinkTarget, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 9) {
            icon()
            Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Unlink…") { ui.sheet = .unlink(connection, target) }.controlSize(.small).disabled(!workspace.canEdit)
        }
        .padding(.horizontal, 10).frame(minHeight: 36)
    }
    private var sourceText: String {
        switch connection.origin {
        case .repository: "Found in Repository Configuration\(connection.source.map { " · \($0)" } ?? "")"
        case .provider: "Listed by \(connection.provider.title)"
        case .manual: "Added Manually"
        }
    }
    private func fact(_ label: String, _ value: String, mono: Bool = false) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            Text(value).font(mono ? .system(size: 11.5, design: .monospaced) : .system(size: 12))
                .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func flash() { copied = true; Task { try? await Task.sleep(for: .seconds(1.6)); copied = false } }
}
