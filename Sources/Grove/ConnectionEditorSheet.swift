import SwiftUI
import GroveCore

struct ConnectionEditorSheet: View {
    let store: Store
    let ui: WorkspaceUI
    let isNew: Bool
    @State private var draft: ServiceConnection
    init(store: Store, ui: WorkspaceUI, connection: ServiceConnection, isNew: Bool) {
        self.store = store; self.ui = ui; self.isNew = isNew
        _draft = State(initialValue: connection)
    }
    var body: some View {
        SheetFrame(symbol: "link", tint: .grove, title: isNew ? "Add Service" : "Edit Service",
                   subtitle: "Remember a service and open its link.", width: 460) {
            FormField("Name") { TextField("Service Name", text: $draft.name).textFieldStyle(.roundedBorder) }
            FormField("Link") { TextField("https://", text: $draft.dashboardURL).textFieldStyle(.roundedBorder).autocorrectionDisabled() }
            ShowInField(store: store, draft: $draft)
            SheetError(store: store)
        } buttons: {
            Button("Cancel") { store.workspace.error = nil; ui.sheet = nil }.keyboardShortcut(.cancelAction)
            Button(isNew ? "Add Service" : "Save") {
                var next = draft
                next.name = next.name.trimmingCharacters(in: .whitespacesAndNewlines)
                next.dashboardURL = next.dashboardURL.trimmingCharacters(in: .whitespacesAndNewlines)
                next.useAsSavedLink(); next.dashboardOverride = true
                store.workspace.error = nil; store.workspace.saveConnection(next)
                if store.workspace.error == nil { ui.sheet = nil }
            }
            .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            .disabled(!store.workspace.canEdit || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ServiceCatalog.safeURL(draft.dashboardURL) == nil)
        }
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
                FinePrint("Not shown anywhere yet. It still appears in Services.")
            }
        }
    }
}
