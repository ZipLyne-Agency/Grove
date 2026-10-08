import SwiftUI
import GroveCore

/// Adds or edits one connection. Local metadata only; renaming at the provider has its own review.
struct ConnectionEditorSheet: View {
    let store: Store
    let ui: WorkspaceUI
    let isNew: Bool
    private let original: ServiceConnection
    @State private var draft: ServiceConnection
    @State private var linkOnly: Bool
    @State private var customEnvironment: Bool
    @State private var newAccount: ProviderAccount?
    @State private var linkEdited = false
    @FocusState private var nameFocused: Bool
    private var workspace: WorkspaceStore { store.workspace }
    private static let environments = ["", "Production", "Preview"]
    init(store: Store, ui: WorkspaceUI, connection: ServiceConnection, isNew: Bool) {
        self.store = store; self.ui = ui; self.isNew = isNew; original = connection
        _draft = State(initialValue: connection)
        _linkOnly = State(initialValue: connection.accountID == nil)
        _customEnvironment = State(initialValue: !Self.environments.contains(connection.environment))
    }
    private var accounts: [ProviderAccount] { workspace.accounts.filter { $0.provider == draft.provider } }
    private var account: ProviderAccount? { accounts.first { $0.id == draft.accountID } }
    private var savedLink: Bool { linkOnly || !draft.provider.supportsAPI }
    private var template: String { ServiceCatalog.dashboard(provider: draft.provider, resourceID: draft.resourceID, scope: account?.scope ?? "") }
    private var listable: Bool { ![.expo, .googlePlay, .custom].contains(draft.provider) }
    private var resources: [ProviderResource] {
        guard let id = draft.accountID, workspace.resourceAccountID == id else { return [] }
        return workspace.resources
    }
    private var identityChanged: Bool {
        draft.provider != original.provider || draft.resourceID != original.resourceID || draft.accountID != original.accountID
    }

    var body: some View {
        SheetFrame(symbol: "powerplug", tint: .grove, title: title, subtitle: subtitle, width: 500) {
            if isNew {
                Picker("Service", selection: Binding(get: { draft.provider }, set: choose)) {
                    ForEach(ServiceProvider.allCases) { Text($0.title).tag($0) }
                }
            }
            FormField("Name") {
                TextField(draft.provider.title, text: $draft.name).textFieldStyle(.roundedBorder).focused($nameFocused)
            }
            if draft.provider.supportsAPI {
                Picker("Connection", selection: Binding(get: { linkOnly }, set: { linkOnly = $0; if $0 { draft.accountID = nil } })) {
                    Text("Verify With an Account").tag(false)
                    Text("Save as Link Only").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            if !savedLink { accountPicker }
            resourceField
            environmentField
            FormField("Dashboard Link") {
                TextField(draft.provider == .custom ? "https://" : template,
                          text: Binding(get: { draft.dashboardURL }, set: { draft.dashboardURL = $0; linkEdited = true }))
                    .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced)).autocorrectionDisabled()
            }
            FinePrint(linkHelp)
            ShowInField(store: store, draft: $draft)
            FormField("Notes (Optional)") {
                TextField("Notes", text: $draft.notes, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
            }
            SheetError(store: store)
        } buttons: {
            Button("Cancel") { workspace.error = nil; workspace.clearResources(); ui.sheet = nil }.keyboardShortcut(.cancelAction)
            Button(isNew ? "Add Connection" : "Save") { save() }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled(!workspace.canEdit || (!savedLink && draft.accountID == nil))
        }
        .onAppear { workspace.clearResources(); nameFocused = true }
        .onChange(of: draft.accountID) { workspace.clearResources() }
        .sheet(item: $newAccount) { item in
            AccountEditorSheet(store: store, ui: ui, account: item, isNew: true) { saved in
                if let saved { draft.accountID = saved.id }
                newAccount = nil
            }
        }
    }

    @ViewBuilder private var accountPicker: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Picker("Account", selection: $draft.accountID) {
                Text("Choose…").tag(UUID?.none)
                ForEach(accounts) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            Button("New Account…") { newAccount = ProviderAccount(provider: draft.provider, name: "") }
                .disabled(!workspace.canEdit)
        }
        if accounts.isEmpty {
            FinePrint("Add a \(draft.provider.title) account first. Its credential is stored in macOS Keychain and never shown.")
        }
    }

    private var resourceField: some View {
        FormField(draft.provider.resourceLabel) {
            HStack(spacing: 8) {
                TextField(draft.provider.resourceLabel, text: $draft.resourceID)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12.5, design: .monospaced)).autocorrectionDisabled()
                if !savedLink && listable, let account {
                    if workspace.loadingResources && workspace.resourceAccountID == account.id {
                        ProgressView().controlSize(.small)
                    } else if resources.isEmpty {
                        Button("Browse…") { Task { await workspace.loadResources(account) } }
                    } else {
                        Menu("Choose") {
                            ForEach(resources) { resource in
                                Button("\(resource.name) · \(resource.id)") {
                                    draft.resourceID = resource.id
                                    if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { draft.name = resource.name }
                                }
                            }
                        }
                        .fixedSize()
                    }
                }
            }
        }
    }

    @ViewBuilder private var environmentField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Picker("Environment", selection: Binding(get: { customEnvironment ? "custom" : draft.environment },
                                                     set: { value in
                                                         customEnvironment = value == "custom"
                                                         if !customEnvironment { draft.environment = value }
                                                     })) {
                Text("None").tag("")
                Text("Production").tag("Production")
                Text("Preview").tag("Preview")
                Text("Custom…").tag("custom")
            }
            .fixedSize()
            if customEnvironment {
                TextField("Label, for example Staging", text: $draft.environment).textFieldStyle(.roundedBorder)
            }
        }
    }

    private var linkHelp: String {
        switch draft.provider {
        case .custom: "Opens directly. Grove does not check custom links. HTTPS only, without tokens in the address."
        case .googlePlay: "Paste the exact Play Console page for this app. Grove reads package access only and does not retain releases or reviews."
        default: draft.dashboardOverride == true && !linkEdited
            ? "This exact address is kept through checks and renames. Clear it to let \(draft.provider.title) resolve the address."
            : "A typed HTTPS address is kept exactly. Leave it empty to use the address \(draft.provider.title) reports, or the standard one shown."
        }
    }
    private var title: String {
        if isNew { return "Add Connection" }
        return draft.status() == .suggested ? "Connect \(draft.provider.title)" : "Edit Connection"
    }
    private var subtitle: String {
        if let source = draft.source, draft.origin == .repository { return "Found in \(source). Nothing was checked with \(draft.provider.title) yet." }
        return "Verified connections show status from the provider. Saved links only open the dashboard."
    }
    private func choose(_ provider: ServiceProvider) {
        draft.provider = provider; draft.accountID = nil; draft.dashboardURL = ""
        workspace.clearResources()
        if !provider.supportsAPI { linkOnly = true }
    }
    private func save() {
        var next = draft
        if savedLink { next.accountID = nil }
        next.dashboardURL = next.dashboardURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if linkEdited && next.dashboardURL != original.dashboardURL {
            // An explicit typed address is kept exactly; clearing it lets the provider resolve the address again.
            next.dashboardOverride = !next.dashboardURL.isEmpty
        } else if identityChanged && next.provider != .custom && original.dashboardOverride != true {
            next.dashboardURL = ""; next.dashboardOverride = false
        }
        next.environment = next.environment.trimmingCharacters(in: .whitespacesAndNewlines)
        if next.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { next.name = next.provider.title }
        if next.origin == .repository { next.origin = .manual }
        workspace.error = nil
        workspace.saveConnection(next)
        guard workspace.error == nil else { return }
        if next.accountID != nil { workspace.requestSync(next.id) }
        workspace.clearResources()
        ui.sheet = nil
    }
}

/// Where a connection appears: projects and repositories, as removable chips.
private struct ShowInField: View {
    let store: Store
    @Binding var draft: ServiceConnection
    var body: some View {
        let repos = (store.inventory?.repositories ?? []).sorted { $0.full_name.localizedStandardCompare($1.full_name) == .orderedAscending }
        let known = Set(repos.map(\.id))
        let projects = store.workspace.projects
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel("Show In")
            FlowLayout(spacing: 5) {
                ForEach(projects.filter { draft.projectIDs.contains($0.id) }) { project in
                    Chip(text: "Project: \(project.name)") { draft.projectIDs.remove(project.id) }
                }
                ForEach(repos.filter { draft.repositoryIDs.contains($0.id) }) { repo in
                    Chip(text: repo.name) { draft.repositoryIDs.remove(repo.id) }
                }
                ForEach(draft.repositoryIDs.filter { !known.contains($0) }.sorted(), id: \.self) { id in
                    Chip(text: "Repository \(id.formatted(.number.grouping(.never)))") { draft.repositoryIDs.remove(id) }
                }
                Menu("Add…") {
                    Section("Projects") {
                        ForEach(projects.filter { !draft.projectIDs.contains($0.id) }) { project in
                            Button(project.name) { draft.projectIDs.insert(project.id) }
                        }
                    }
                    Section("Repositories") {
                        ForEach(Array(repos.filter { !draft.repositoryIDs.contains($0.id) }.prefix(300))) { repo in
                            Button(repo.full_name) { draft.repositoryIDs.insert(repo.id) }
                        }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11.5))
            }
            if draft.projectIDs.isEmpty && draft.repositoryIDs.isEmpty {
                FinePrint("Not shown anywhere yet. It still appears in Connections.")
            }
        }
    }
}
