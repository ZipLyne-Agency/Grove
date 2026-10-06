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
            AssistantPreset(title: "Explain this project", prompt: "Explain this project's purpose and technology in plain English.", symbol: "text.magnifyingglass"),
            AssistantPreset(title: "Improve the description", prompt: "Propose a clearer GitHub description for this repository.", symbol: "text.alignleft"),
            AssistantPreset(title: "Suggest a clearer name", prompt: "Propose one clearer repository name, preserving the project's identity.", symbol: "pencil"),
            AssistantPreset(title: "Plan a transfer", prompt: "Explain which of my available organizations could fit this project. Ask me to choose before proposing a transfer.", symbol: "arrow.right.arrow.left"),
            repo.archived
                ? AssistantPreset(title: "Prepare unarchive", prompt: "Propose unarchiving this repository.", symbol: "archivebox")
                : AssistantPreset(title: "Prepare archive", prompt: "Propose archiving this repository. Explain what archiving changes.", symbol: "archivebox")
        ]
        if includeDeletion {
            presets.append(AssistantPreset(title: "Review before deletion", prompt: "Explain what I should check before deleting this repository. Do not propose deletion.", symbol: "checklist"))
            presets.append(AssistantPreset(title: "Prepare deletion", prompt: "Propose deleting this repository. Explain the consequences and that separate exact-name confirmation is required.", symbol: "trash"))
        }
        return presets
    }
    static let collection: [AssistantPreset] = [
        AssistantPreset(title: "Summarize projects", prompt: "Summarize the projects in this inventory sample. State the coverage limits.", symbol: "list.bullet.rectangle"),
        AssistantPreset(title: "Review recent activity", prompt: "Identify projects pushed most recently from the supplied timestamps. State the coverage limits.", symbol: "clock"),
        AssistantPreset(title: "Find missing descriptions", prompt: "Identify repositories without descriptions and recommend how to describe them. Do not propose a bulk change.", symbol: "text.badge.plus"),
        AssistantPreset(title: "Review organization structure", prompt: "Suggest how to organize these projects across my available organizations. Do not propose a bulk change or invent destinations.", symbol: "building.2")
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
                store.assistantFocus = repo != nil ? .repository : owner != nil ? .owner : .library
                store.assistantOwner = owner; store.assistantScope = scope
                store.showAssistant = true
            } label: { Label("Write a Question", systemImage: "square.and.pencil") }
        } label: { Label("Ask Grove", systemImage: "sparkles") }
        .disabled(!Intelligence.available || store.assistantBusy || !store.canStartReview)
    }
}

struct RepositoryMenu: View {
    let store: Store
    let repo: Repository
    private var manageDisabled: Bool { !repo.canAdminister || !store.canStartReview || store.needsRefresh }
    var body: some View {
        Button { store.requestOpen(repo) } label: { Label("Open on GitHub…", systemImage: "arrow.up.right.square") }
            .disabled(!store.canStartReview)
        Menu {
            Button("GitHub Link…") { if let url = repo.webURL { store.requestCopy(url.absoluteString) } }
            Button("Full Name…") { store.requestCopy(repo.full_name) }
            Button("Clone Command…") { store.requestCopy(repo.cloneCommand) }
        } label: { Label("Copy", systemImage: "doc.on.doc") }
        .disabled(!store.canStartReview)
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
        Button { store.scope = .all; store.owner = owner } label: { Label("Show Repositories", systemImage: "list.bullet") }
        IntelligenceMenu(store: store, owner: owner)
        Divider()
        Button { store.requestOwnerPage(owner) } label: { Label("Open on GitHub…", systemImage: "arrow.up.right.square") }
            .disabled(!store.canStartReview)
        if store.destinations.contains(owner) {
            Button { store.requestOwnerPage(owner, settings: true) } label: { Label("Open Organization Settings…", systemImage: "gearshape") }
                .disabled(!store.canStartReview)
        }
        Menu {
            Button("GitHub Link…") { store.requestCopy("https://github.com/\(owner)") }
            Button("Name…") { store.requestCopy(owner) }
        } label: { Label("Copy", systemImage: "doc.on.doc") }
        .disabled(!store.canStartReview)
        Divider()
        Button { store.requestOwnerVisibility(owner, hidden: true) } label: { Label("Hide from Grove…", systemImage: "eye.slash") }
            .disabled(!store.canStartReview)
    }
}

struct ScopeMenu: View {
    let store: Store
    let scope: LibraryScope
    var body: some View {
        Button { store.owner = nil; store.scope = scope } label: { Label("Show \(scope.rawValue)", systemImage: scope.symbol) }
        IntelligenceMenu(store: store, scope: scope)
    }
}
