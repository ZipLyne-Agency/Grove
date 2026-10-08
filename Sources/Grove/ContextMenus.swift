import SwiftUI
import AppKit
import GroveCore

@MainActor enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Copies immediately. Only used inside an already open confirmation.
struct CopyButton: View {
    let text: String
    var title = "Copy"
    @State private var copied = false
    var body: some View {
        Button {
            Clipboard.copy(text); copied = true
            Task { try? await Task.sleep(for: .seconds(1.6)); copied = false }
        } label: {
            Label(copied ? "Copied" : title, systemImage: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.identity)
        }
        .controlSize(.small)
        .help("Copy \(text)")
        .accessibilityLabel(copied ? "Copied" : "\(title) \(text)")
    }
}

struct AssistantPreset: Identifiable {
    let title: String
    let prompt: String
    let symbol: String
    var id: String { title }
}

enum AssistantPresets {
    /// Presets offered in the panel; the menu adds the deletion-related ones.
    static func repository(_ repo: Repository, includeDeletion: Bool) -> [AssistantPreset] {
        var presets = [
            AssistantPreset(title: "Explain This Project", prompt: "Explain this project's purpose and technology in plain English.", symbol: "text.magnifyingglass"),
            AssistantPreset(title: "What Ships From This Repository?", prompt: "Summarize this repository's connected services. Say which are verified, out of date, failing, or only saved links.", symbol: "powerplug"),
            AssistantPreset(title: "Improve the Description", prompt: "Propose a clearer GitHub description for this repository.", symbol: "text.alignleft"),
            AssistantPreset(title: "Suggest a Clearer Name", prompt: "Propose one clearer repository name, preserving the project's identity.", symbol: "pencil"),
            AssistantPreset(title: "Plan a Transfer", prompt: "Explain which of my available organizations could fit this project. Ask me to choose before proposing a transfer.", symbol: "arrow.right.arrow.left"),
            repo.archived
                ? AssistantPreset(title: "Prepare Unarchive", prompt: "Propose unarchiving this repository.", symbol: "archivebox")
                : AssistantPreset(title: "Prepare Archive", prompt: "Propose archiving this repository. Explain what archiving changes.", symbol: "archivebox")
        ]
        if includeDeletion {
            presets.append(AssistantPreset(title: "Review Before Deletion", prompt: "Explain what I should check before deleting this repository. Do not propose deletion.", symbol: "checklist"))
            presets.append(AssistantPreset(title: "Prepare Deletion", prompt: "Propose deleting this repository. Explain the consequences and that separate exact-name confirmation is required.", symbol: "trash"))
        }
        return presets
    }
    static let project: [AssistantPreset] = [
        AssistantPreset(title: "What Needs Attention?", prompt: "What needs attention in this project? Use only the supplied service and repository records, and say which records are stale or unchecked.", symbol: "exclamationmark.triangle"),
        AssistantPreset(title: "Summarize Recent Builds and Deployments", prompt: "Summarize recent builds, deployments, and releases from the supplied service activity. Say when activity is missing.", symbol: "shippingbox"),
        AssistantPreset(title: "Which Services Are Only Saved Links?", prompt: "List which services in this project are saved links or suggestions that Grove does not check.", symbol: "link"),
        AssistantPreset(title: "How Do These Repositories Fit Together?", prompt: "Explain how the repositories in this project relate, based on their names, descriptions, and linked services.", symbol: "square.grid.2x2")
    ]
    static let collection: [AssistantPreset] = [
        AssistantPreset(title: "Summarize Projects", prompt: "Summarize the projects in this inventory sample. State the coverage limits.", symbol: "list.bullet.rectangle"),
        AssistantPreset(title: "Review Recent Activity", prompt: "Identify projects pushed most recently from the supplied timestamps. State the coverage limits.", symbol: "clock"),
        AssistantPreset(title: "Find Missing Descriptions", prompt: "Identify repositories without descriptions and recommend how to describe them. Do not propose a bulk change.", symbol: "text.badge.plus"),
        AssistantPreset(title: "Review Organization Structure", prompt: "Suggest how to organize these projects across my available organizations. Do not propose a bulk change or invent destinations.", symbol: "building.2")
    ]
}

struct IntelligenceMenu: View {
    let store: Store
    var repo: Repository? = nil
    var owner: String? = nil
    var scope: LibraryScope = .all
    private var presets: [AssistantPreset] { repo.map { AssistantPresets.repository($0, includeDeletion: true) } ?? AssistantPresets.collection }
    var body: some View {
        Menu {
            ForEach(presets) { preset in
                Button { store.requestAssistant(preset.prompt, repo: repo, owner: owner, libraryScope: scope) } label: {
                    Label(preset.title + "…", systemImage: preset.symbol)
                }
            }
            Divider()
            Button {
                if let repo { store.selectedID = repo.id }
                store.assistantProjectID = nil
                store.assistantFocus = repo != nil ? .repository : owner != nil ? .owner : .library
                store.assistantOwner = owner; store.assistantScope = scope
                store.showAssistant = true
            } label: { Label("Write a Question", systemImage: "square.and.pencil") }
        } label: { Label { Text("Ask Grove") } icon: { Image(nsImage: GroveMarkImage.menu) } }
        .disabled(!Intelligence.available || store.assistantBusy || !store.canStartReview)
    }
}

struct RepositoryMenu: View {
    let store: Store
    let repo: Repository
    private var manageDisabled: Bool { !repo.canAdminister || !store.canStartReview || store.needsRefresh }
    var body: some View {
        Button { store.requestOpen(repo) } label: { Label("Open on GitHub", systemImage: "arrow.up.right.square") }
        Menu {
            Button("Link") { if let url = repo.webURL { store.requestCopy(url.absoluteString) } }
            Button("Full Name") { store.requestCopy(repo.full_name) }
            Button("Clone Command") { store.requestCopy(repo.cloneCommand) }
        } label: { Label("Copy", systemImage: "doc.on.doc") }
        IntelligenceMenu(store: store, repo: repo)
        Divider()
        Group {
            Button { store.requestEdit(repo, kind: .rename) } label: { Label("Rename…", systemImage: "pencil") }
            Button { store.requestEdit(repo, kind: .description) } label: { Label("Edit Description…", systemImage: "text.alignleft") }
            Button { store.requestEdit(repo, kind: .transfer) } label: { Label("Transfer to Organization…", systemImage: "arrow.right.arrow.left") }
            Button { Task { await store.prepare(repo, action: .archive(!repo.archived)) } } label: {
                Label(repo.archived ? "Unarchive…" : "Archive…", systemImage: "archivebox")
            }
        }.disabled(manageDisabled)
        Divider()
        Button(role: .destructive) { Task { await store.prepare(repo, action: .delete) } } label: {
            Label("Delete Repository…", systemImage: "trash")
        }.disabled(manageDisabled)
    }
}

struct OwnerMenu: View {
    let store: Store
    let owner: String
    var body: some View {
        Button { store.workspace.destination = .library; store.scope = .all; store.owner = owner } label: { Label("Show Repositories", systemImage: "list.bullet") }
        IntelligenceMenu(store: store, owner: owner)
        Divider()
        Button { store.requestOwnerPage(owner) } label: { Label("Open on GitHub", systemImage: "arrow.up.right.square") }
        if store.destinations.contains(owner) {
            Button { store.requestOwnerPage(owner, settings: true) } label: { Label("Open Organization Settings", systemImage: "gearshape") }
        }
        Menu {
            Button("Link") { store.requestCopy("https://github.com/\(owner)") }
            Button("Name") { store.requestCopy(owner) }
        } label: { Label("Copy", systemImage: "doc.on.doc") }
        Divider()
        Button { store.requestOwnerVisibility(owner, hidden: true) } label: { Label("Hide From Grove", systemImage: "eye.slash") }
            .disabled(!store.canStartReview)
    }
}

struct ScopeMenu: View {
    let store: Store
    let scope: LibraryScope
    var body: some View {
        Button { store.workspace.destination = .library; store.owner = nil; store.scope = scope } label: { Label("Show \(scope.title)", systemImage: scope.symbol) }
        IntelligenceMenu(store: store, scope: scope)
    }
}
