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
    @State private var scanTask: Task<Void, Never>?
    @State private var started = false
    private var workspace: WorkspaceStore { store.workspace }
    private func known(_ item: ServiceSuggestion) -> Bool {
        workspace.connections(for: repo.id).contains {
            item.provider != .custom && $0.provider == item.provider || $0.dashboardURL == item.dashboardURL || $0.name.caseInsensitiveCompare(item.name) == .orderedSame
        }
    }
    var body: some View {
        let found = workspace.suggestions.filter { $0.repositoryID == repo.id }
        SheetFrame(symbol: "magnifyingglass", tint: .grove, title: "Find Services", subtitle: repo.full_name, monospacedSubtitle: true, width: 520) {
            Text("Scan repository configuration, dependency manifests, and README excerpts with the on-device assistant. Review the suggested services and website links below. You can edit each link to point to your project's dashboard.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if workspace.discovering {
                HStack { ProgressView().controlSize(.small); Text("Finding Services…").font(.system(size: 12)) }
            } else if started {
                if found.isEmpty { Text("No services found in the scanned files. Add any others manually.").font(.system(size: 12)) }
                ScrollView {
                    TableBox {
                        ForEach(found) { item in
                            Toggle(isOn: Binding(get: { chosen.contains(item.id) && !known(item) }, set: { on in
                                if on { chosen.insert(item.id) } else { chosen.remove(item.id) }
                            })) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.provider == .custom ? item.name : item.provider.title).font(.system(size: 13, weight: .medium))
                                    Text(item.dashboardURL).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    Text(known(item) ? "Already Added" : "Found in \(item.source)").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }.toggleStyle(.checkbox).disabled(known(item)).padding(10)
                        }
                    }
                }.scrollIndicators(.never).frame(maxHeight: 270)
                if let notice = workspace.notice { FinePrint(notice) }
                FinePrint("The scan covers known files and catalogued services, so it may miss others. Links open service websites; edit them for your project dashboards.")
            }
            SheetError(store: store)
        } buttons: {
            Button(started ? "Scan Again" : "Scan Repository") { scan() }.disabled(workspace.discovering)
            Spacer()
            Button("Cancel") { scanTask?.cancel(); ui.sheet = nil }.keyboardShortcut(.cancelAction)
            Button("Add Selected") {
                workspace.error = nil
                for item in found where chosen.contains(item.id) && !known(item) {
                    workspace.saveConnection(ServiceConnection(provider: item.provider, name: item.provider == .custom ? item.name : item.provider.title,
                                                               dashboardURL: item.dashboardURL, repositoryIDs: [repo.id], source: item.source))
                    if workspace.error != nil { return }
                }
                ui.sheet = nil
            }.buttonStyle(.borderedProminent).disabled(chosen.isEmpty || workspace.discovering || !workspace.canEdit)
        }
        .onAppear { scan() }
        .onDisappear { scanTask?.cancel() }
    }
    private func scan() {
        started = true; chosen = []; workspace.error = nil; workspace.notice = nil
        scanTask = Task {
            await workspace.discover(repo, using: store.service)
            guard !Task.isCancelled else { return }
            chosen = Set(workspace.suggestions.filter { $0.repositoryID == repo.id && !known($0) }.map(\.id))
        }
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
