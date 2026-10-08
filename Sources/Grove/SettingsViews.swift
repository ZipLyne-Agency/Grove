import SwiftUI
import GroveCore

struct AccountDetailView: View {
    @Bindable var store: Store
    let ui: WorkspaceUI
    let account: ProviderAccount
    private var workspace: WorkspaceStore { store.workspace }
    private var google: Bool { [.searchConsole, .analytics, .googlePlay].contains(account.provider) }
    var body: some View {
        let used = workspace.connections.filter { $0.accountID == account.id }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    ProviderTile(provider: account.provider, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.name).font(.system(size: 20, weight: .semibold)).lineLimit(2).textSelection(.enabled)
                        Text("\(account.provider.title) Account · \(countLabel(used.count, "Service", "Services"))").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Edit Account…") { ui.sheet = .editAccount(account, isNew: false) }.disabled(!workspace.canEdit)
                    Button("Remove…") { ui.sheet = .removeAccount(account) }.foregroundStyle(Color.danger).disabled(!workspace.canEdit)
                }
                .controlSize(.small)
                DetailSection(title: "Details") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                        GridRow { Text("Service").foregroundStyle(.secondary); Text(account.provider.title) }
                        GridRow {
                            Text(account.provider.scopeLabel).foregroundStyle(.secondary)
                            Text(account.scope.isEmpty ? "Not Set" : account.scope).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled)
                        }
                        if google {
                            GridRow {
                                Text("Delegated Account").foregroundStyle(.secondary)
                                Text(account.googleSubject.flatMap { $0.isEmpty ? nil : $0 } ?? "None").textSelection(.enabled)
                            }
                        }
                        GridRow { Text("Credential").foregroundStyle(.secondary); Text("Stored in macOS Keychain · Never Shown") }
                    }
                    .font(.system(size: 12))
                    if google {
                        FinePrint("Google access uses the credentials JSON you saved. The account name above is your label for it; Grove does not open a browser sign-in.")
                    }
                }
                DetailSection(title: "Services Using This Account") {
                    if used.isEmpty {
                        Text("No services use this account yet. Choose it when you add a connection.").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        TableBox { ForEach(used) { ServiceRow(store: store, ui: ui, connection: $0) } }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .background(Color.inspector)
    }
}

struct SettingsPane: View {
    @Bindable var store: Store
    let ui: WorkspaceUI
    private var workspace: WorkspaceStore { store.workspace }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings").font(.system(size: 20, weight: .semibold))
                    Text("Projects, connections, and preferences are stored on this Mac. Credentials stay in macOS Keychain and are never shown.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                DetailSection(title: "GitHub") {
                    TableBox {
                        row("Account", value: store.inventory?.account.login ?? "Not Connected")
                        row("Last Updated", value: store.inventory.map { GroveDates.exact($0.fetchedAt) } ?? "Never") {
                            Button(store.busy ? "Syncing…" : "Sync Now") { store.requestRefresh() }.disabled(store.busy || !store.canStartReview)
                        }
                        row("Sign-In", value: "GitHub CLI (gh auth login)")
                    }
                }
                DetailSection(title: "Services") {
                    TableBox {
                        row("Connections", value: countLabel(workspace.connections.count, "Connection", "Connections")) {
                            Button("Show Connections") { workspace.destination = .connections }
                        }
                        row("Background Checks", value: "While Grove is open, and after waking or reconnecting. Failed checks back off.") {
                            Button(workspace.syncing.isEmpty ? "Sync All" : "Syncing…") { Task { await workspace.syncAll(force: true) } }
                                .disabled(!workspace.syncing.isEmpty || !workspace.canEdit)
                        }
                    }
                }
                DetailSection(title: "Accounts") {
                    if workspace.accounts.isEmpty {
                        Text("No provider accounts. Saved links work without one.").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        TableBox {
                            ForEach(workspace.accounts) { account in
                                HStack(spacing: 9) {
                                    ProviderTile(provider: account.provider, size: 22)
                                    Text(account.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Text(account.provider.title).font(.system(size: 11)).foregroundStyle(.secondary)
                                    Spacer(minLength: 8)
                                    Button("Edit…") { ui.sheet = .editAccount(account, isNew: false) }.disabled(!workspace.canEdit)
                                    Button("Remove…") { ui.sheet = .removeAccount(account) }.disabled(!workspace.canEdit)
                                }
                                .controlSize(.small).padding(.horizontal, 10).frame(minHeight: 38)
                            }
                        }
                    }
                    Menu("Add Account") {
                        ForEach(ServiceProvider.allCases.filter(\.supportsAPI)) { provider in
                            Button(provider.title) { ui.sheet = .editAccount(ProviderAccount(provider: provider, name: ""), isNew: true) }
                        }
                    }
                    .fixedSize().controlSize(.small).disabled(!workspace.canEdit)
                }
                DetailSection(title: "Hidden Owners") {
                    if store.hiddenOwners.isEmpty {
                        Text("No owners are hidden.").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        TableBox {
                            ForEach(store.hiddenOwners.sorted(), id: \.self) { owner in
                                row(owner, value: countLabel(store.counts.count(owner: owner), "Repository", "Repositories")) {
                                    Button("Show") { store.requestOwnerVisibility(owner, hidden: false) }
                                }
                            }
                        }
                    }
                }
                DetailSection(title: "Ask Grove") {
                    HStack(spacing: 9) {
                        GroveMark(size: 18, available: Intelligence.available)
                        Text(Intelligence.available
                             ? "Available. Answers run on this Mac with Apple Intelligence. Suggested changes always open a review."
                             : "Apple Intelligence isn't available. Turn it on in System Settings on a supported Mac. Everything else works without it.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .background(Color.inspector)
    }
    private func row(_ title: String, value: String) -> some View { row(title, value: value) { EmptyView() } }
    private func row<Trailing: View>(_ title: String, value: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
            Text(value).font(.system(size: 12)).lineLimit(2).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            trailing().controlSize(.small)
        }
        .padding(.horizontal, 12).frame(minHeight: 38)
    }
}
