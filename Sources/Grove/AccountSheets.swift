import SwiftUI
import GroveCore

struct AccountEditorSheet: View {
    let store: Store
    let ui: WorkspaceUI
    let isNew: Bool
    var onDone: ((ProviderAccount?) -> Void)? = nil
    @State private var draft: ProviderAccount
    @State private var credential = ""
    @State private var saving = false
    private var workspace: WorkspaceStore { store.workspace }
    init(store: Store, ui: WorkspaceUI, account: ProviderAccount, isNew: Bool, onDone: ((ProviderAccount?) -> Void)? = nil) {
        self.store = store; self.ui = ui; self.isNew = isNew; self.onDone = onDone
        _draft = State(initialValue: account)
    }
    private var google: Bool { [.searchConsole, .analytics, .googlePlay].contains(draft.provider) }
    var body: some View {
        SheetFrame(symbol: "key", tint: .grove, title: isNew ? "Add \(draft.provider.title) Account" : "Edit \(draft.provider.title) Account",
                   subtitle: "The credential is stored in macOS Keychain and never shown again.") {
            if isNew {
                Picker("Service", selection: $draft.provider) {
                    ForEach(ServiceProvider.allCases.filter(\.supportsAPI)) { Text($0.title).tag($0) }
                }
            }
            FormField("Account Name") {
                TextField("For example, the team or company name", text: $draft.name).textFieldStyle(.roundedBorder)
            }
            FormField(draft.provider.scopeLabel) {
                TextField(draft.provider.scopeLabel, text: $draft.scope).textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced)).autocorrectionDisabled()
            }
            if google {
                FormField("Delegated Google Account (Optional)") {
                    TextField("name@example.com", text: Binding(get: { draft.googleSubject ?? "" }, set: { draft.googleSubject = $0.isEmpty ? nil : $0 }))
                        .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                }
                FinePrint("Use this only with a service account that has domain-wide delegation. Grove does not open a browser sign-in.")
            }
            FormField(isNew ? "Credential" : "Replace Credential (Optional)") {
                SecureField(isNew ? "Paste the credential" : "Leave empty to keep the saved credential", text: $credential)
                    .textFieldStyle(.roundedBorder)
            }
            FinePrint(draft.provider.credentialHelp)
            SheetError(store: store)
        } buttons: {
            if saving { ProgressView().controlSize(.small) }
            Button("Cancel") { workspace.error = nil; credential = ""; close(nil) }.keyboardShortcut(.cancelAction)
            Button(isNew ? "Add Account" : "Save") { save() }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled(saving || !workspace.canEdit || draft.name.trimmingCharacters(in: .whitespaces).isEmpty || (isNew && credential.isEmpty))
        }
    }
    private func save() {
        saving = true; workspace.error = nil
        let account = draft, secret = credential
        Task {
            let saved = await workspace.saveAccount(account, credential: secret)
            saving = false
            guard saved else { return }
            credential = ""
            for connection in workspace.connections where connection.accountID == account.id { workspace.requestSync(connection.id) }
            close(account)
        }
    }
    private func close(_ account: ProviderAccount?) {
        if let onDone { onDone(account) } else { ui.sheet = nil }
    }
}

struct RemoveAccountSheet: View {
    let store: Store
    let ui: WorkspaceUI
    let account: ProviderAccount
    @State private var removing = false
    var body: some View {
        let used = store.workspace.connections.filter { $0.accountID == account.id }
        SheetFrame(symbol: "key", tint: .danger, title: "Remove \(account.name)?", subtitle: "\(account.provider.title) Account · Only changes Grove on this Mac.") {
            ValueBox(rows: [
                ("Services Using It", used.isEmpty ? "None" : used.map(\.name).joined(separator: ", "), false),
                ("Keychain", "The saved credential is deleted from this Mac.", false)
            ], tint: .danger)
            FinePrint(used.isEmpty ? "Nothing changes at \(account.provider.title)."
                      : "Those services stay in Grove as saved links until you choose another account. Nothing changes at \(account.provider.title).")
            SheetError(store: store)
        } buttons: {
            Button("Cancel") { ui.sheet = nil }.keyboardShortcut(.cancelAction)
            Button("Remove Account", role: .destructive) {
                removing = true; store.workspace.error = nil
                Task {
                    await store.workspace.removeAccount(account.id)
                    removing = false
                    if store.workspace.error == nil { ui.selectedAccountID = nil; ui.sheet = nil }
                }
            }
            .buttonStyle(.borderedProminent).tint(.danger).disabled(removing || !store.workspace.canEdit)
        }
    }
}

struct DiscoverSheet: View {
    let store: Store
    let ui: WorkspaceUI
    let repo: Repository
    @State private var chosen: Set<String> = []
    @State private var started = false
    private var workspace: WorkspaceStore { store.workspace }
    private func known(_ suggestion: ServiceSuggestion) -> Bool {
        !suggestion.resourceID.isEmpty && workspace.connections.contains {
            $0.provider == suggestion.provider && $0.resourceID == suggestion.resourceID && $0.repositoryIDs.contains(repo.id)
        }
    }
    var body: some View {
        let found = workspace.suggestions.filter { $0.repositoryID == repo.id }
        SheetFrame(symbol: "sparkle.magnifyingglass", tint: .grove, title: "Discover Services", subtitle: repo.full_name, monospacedSubtitle: true, width: 500) {
            Text("Grove reads configuration files on the default branch: \(ServiceDiscovery.paths.joined(separator: ", ")). It never runs them, never reads environment files, and treats nothing it finds as verified.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if workspace.discovering || !started {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Reading Configuration…").font(.system(size: 12)).foregroundStyle(.secondary) }
            } else if found.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No Services Found in Configuration").font(.system(size: 13, weight: .semibold))
                    Text("You can still add a connection or a saved link by hand.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } else {
                ScrollView {
                    TableBox {
                        ForEach(found) { suggestion in
                            row(suggestion, already: known(suggestion))
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 280)
                FinePrint("Selected services are added as Suggested. Connect each one to verify it, or keep it as a saved link.")
            }
            SheetError(store: store)
        } buttons: {
            Button("Scan Again") { scan() }.disabled(workspace.discovering)
            Spacer()
            Button("Cancel") { ui.sheet = nil }.keyboardShortcut(.cancelAction)
            Button(chosen.isEmpty ? "Add Suggestions" : "Add \(countLabel(chosen.count, "Suggestion", "Suggestions"))") { add(found) }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                .disabled(chosen.isEmpty || workspace.discovering || !workspace.canEdit)
        }
        .onAppear { scan() }
    }
    private func row(_ suggestion: ServiceSuggestion, already: Bool) -> some View {
        Toggle(isOn: Binding(get: { chosen.contains(suggestion.id) && !already },
                             set: { on in if on { chosen.insert(suggestion.id) } else { chosen.remove(suggestion.id) } })) {
            HStack(spacing: 9) {
                ProviderTile(provider: suggestion.provider, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.provider.title).font(.system(size: 12.5, weight: .semibold))
                    Text("\(suggestion.source)\(suggestion.resourceID.isEmpty ? "" : " · \(suggestion.resourceID)")")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Text(suggestion.explanation).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Text(already ? "Already Added" : suggestion.resourceID.isEmpty ? "Needs a Resource ID" : "New")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox).disabled(already)
        .padding(.horizontal, 10).padding(.vertical, 8)
    }
    private func scan() {
        started = true; workspace.error = nil
        Task {
            await workspace.discover(repo, using: store.service)
            chosen = Set(workspace.suggestions.filter { $0.repositoryID == repo.id && !known($0) }.map(\.id))
        }
    }
    private func add(_ found: [ServiceSuggestion]) {
        workspace.error = nil
        for suggestion in found where chosen.contains(suggestion.id) && !known(suggestion) {
            workspace.saveConnection(ServiceConnection(provider: suggestion.provider, name: suggestion.name, resourceID: suggestion.resourceID,
                                                       repositoryIDs: [repo.id], origin: .repository, source: suggestion.source))
            if workspace.error != nil { return }
        }
        ui.sheet = nil
    }
}

struct RenameServiceSheet: View {
    let store: Store
    let ui: WorkspaceUI
    let connection: ServiceConnection
    @State private var name = ""
    var body: some View {
        SheetFrame(symbol: "pencil", tint: .grove, title: "Rename at \(connection.provider.title)", subtitle: connection.displayIdentity, monospacedSubtitle: true) {
            FormField("New Name") { TextField("Name", text: $name).textFieldStyle(.roundedBorder) }
            FinePrint("Grove checks the live name first, then shows a review. Nothing changes at \(connection.provider.title) until you confirm. To change only how Grove labels it, use Edit instead.")
        } buttons: {
            Button("Cancel") { ui.sheet = nil }.keyboardShortcut(.cancelAction)
            Button("Review Rename…") {
                let target = name
                ui.sheet = nil
                Task { await store.workspace.prepareRename(connection, name: target) }
            }
            .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == (connection.snapshot?.name ?? connection.name) || !store.workspace.canEdit)
        }
        .onAppear { name = connection.snapshot?.name ?? connection.name }
    }
}

struct RenameReviewSheet: View {
    let store: Store
    let review: ProviderRenameReview
    var body: some View {
        SheetFrame(symbol: "pencil", tint: .grove, title: "Rename at \(review.connection.provider.title)?", subtitle: "Using \(review.account.name)") {
            ValueBox(rows: [
                ("Service", "\(review.connection.provider.title) · \(review.connection.displayIdentity)", true),
                ("From", review.previousName, false),
                ("To", review.newName, false)
            ])
            FinePrint("This changes the name at \(review.connection.provider.title). Grove verifies the result afterwards. The review expires after five minutes.")
        } buttons: {
            if store.workspace.renaming { ProgressView().controlSize(.small) }
            Button("Cancel") { store.workspace.cancelRename() }.keyboardShortcut(.cancelAction).disabled(store.workspace.renaming)
            Button("Rename") { Task { await store.workspace.confirmRename() } }
                .buttonStyle(.borderedProminent).disabled(store.workspace.renaming)
        }
    }
}
