import SwiftUI
import GroveCore

struct LibraryEnrichmentMenu: View {
    let store: Store
    var body: some View {
        Menu {
            Button("Generate Missing Profiles") { start(missing: true) }
            Button("Refresh All Profiles") { start(missing: false) }
            Button("Retry Incomplete Profiles") {
                let repositories = (store.inventory?.repositories ?? []).filter { store.workspace.profile(for: $0.id)?.complete != true }
                store.workspace.startEnrichment(repositories: repositories, using: store.service, onlyMissing: false) { store.rebuild() }
            }
            if let repo = store.selected {
                Divider()
                Button("Refresh \(repo.name)") {
                    store.workspace.startEnrichment(repositories: [repo], using: store.service, onlyMissing: false) { store.rebuild() }
                }
            }
        } label: {
            Label("Enrich Library", systemImage: "sparkle.magnifyingglass")
        }.help("Generate descriptions and discover integrations for all repositories, including hidden owners.")
            .disabled(store.workspace.enrichment.running || store.inventory == nil || !store.workspace.canEdit)
    }
    private func start(missing: Bool) {
        store.workspace.startEnrichment(repositories: store.inventory?.repositories ?? [], using: store.service, onlyMissing: missing) { store.rebuild() }
    }
}

struct LibraryEnrichmentStatus: View {
    let store: Store
    var body: some View {
        let progress = store.workspace.enrichment
        if progress.running || progress.total > 0 {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    if progress.running { ProgressView().controlSize(.small) }
                    Text(progress.running ? "Enriching Library" : progress.phase).font(.system(size: 12, weight: .semibold))
                    Text("\(progress.completed) of \(progress.total) · \(progress.succeeded) saved\(progress.partial > 0 ? " · \(progress.partial) partial" : "")\(progress.failed > 0 ? " · \(progress.failed) failed" : "")")
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    if progress.running { Button("Stop") { store.workspace.stopEnrichment() }.controlSize(.small) }
                    else { Button { store.workspace.enrichment = LibraryEnrichmentProgress() } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                }
                if progress.running {
                    HStack {
                        Text(progress.currentRepository).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(progress.phase + (progress.filesTotal > 0 ? " · \(progress.filesRead)/\(progress.filesTotal) files" : ""))
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                    ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1))).tint(.grove)
                }
                if !progress.running, !progress.failures.isEmpty {
                    DisclosureGroup("Repositories Needing Attention") {
                        ForEach((store.inventory?.repositories ?? []).filter { progress.failures[$0.id] != nil }) { repo in
                            HStack {
                                Text(repo.full_name).font(.system(size: 11, design: .monospaced))
                                Spacer()
                                Text(progress.failures[repo.id] ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }.font(.system(size: 11))
                }
            }.padding(.horizontal, 18).padding(.vertical, 10).background(Color.grove.opacity(0.06))
        }
    }
}
