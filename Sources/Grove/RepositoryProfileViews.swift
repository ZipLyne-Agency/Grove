import SwiftUI
import GroveCore

struct RepositoryDescriptionView: View {
    let store: Store
    let repo: Repository
    @State private var editing = false
    @State private var summary = ""
    @State private var overview = ""
    var body: some View {
        let profile = store.workspace.profile(for: repo.id)
        VStack(alignment: .leading, spacing: 10) {
            if let profile {
                Text(profile.summary).font(.system(size: 13)).lineSpacing(2).textSelection(.enabled)
                    .lineLimit(5)
                HStack {
                    Spacer()
                    Button("Edit…") { summary = profile.summary; overview = profile.overview; editing = true }
                        .buttonStyle(.link).disabled(!store.workspace.canEdit)
                }
            } else {
                Text("No Description Yet").font(.system(size: 13)).textSelection(.enabled)
                Button("Generate Description & Integrations") {
                    store.workspace.startEnrichment(repositories: [repo], using: store.service, onlyMissing: false) { store.rebuild() }
                }.controlSize(.small).disabled(store.workspace.enrichment.running || !store.workspace.canEdit)
            }
        }
        .sheet(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Edit Repository Description").font(.headline)
                Text("Saved in Grove on this Mac.").font(.caption).foregroundStyle(.secondary)
                TextField("Short Description", text: $summary).textFieldStyle(.roundedBorder)
                TextEditor(text: $overview).font(.system(size: 13)).frame(height: 150).border(Color.hairline)
                HStack {
                    Spacer()
                    Button("Cancel") { editing = false }.keyboardShortcut(.cancelAction)
                    Button("Save") { store.workspace.updateDescription(repositoryID: repo.id, summary: summary, overview: overview); store.rebuild(); editing = false }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                        .disabled(summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || summary.count > 350 || overview.count > 4000)
                }
            }.padding(24).frame(width: 500)
        }
    }
}

struct RepositoryIntegrationList: View {
    let store: Store
    let repo: Repository
    var compact = false
    var body: some View {
        if let profile = store.workspace.profile(for: repo.id) {
            let confirmed = profile.visibleIntegrations.filter { !$0.documentationOnly }
            let documented = profile.visibleIntegrations.filter(\.documentationOnly)
            VStack(alignment: .leading, spacing: 12) {
                if confirmed.isEmpty {
                    Text("No visible integrations.").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    ForEach(compact ? Array(confirmed.prefix(4)) : confirmed) { integration in
                        findingRow(integration, compact: compact)
                    }
                }
                if !compact, !documented.isEmpty {
                    DisclosureGroup("\(documented.count) Other Detected Integrations") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(documented) { integration in findingRow(integration) }
                        }.padding(.top, 8)
                    }.font(.system(size: 12))
                }
                let hidden = profile.integrations.filter { profile.hiddenIntegrationIDs?.contains($0.id) == true }
                if !compact, !hidden.isEmpty {
                    DisclosureGroup("Hidden Integrations (\(hidden.count))") {
                        ForEach(hidden) { integration in
                            HStack {
                                Text(integration.name).font(.system(size: 12))
                                Spacer()
                                Button("Show") { setHidden(integration, false) }
                                    .controlSize(.small).disabled(!store.workspace.canEdit)
                            }.padding(.vertical, 4)
                        }
                    }.font(.system(size: 12))
                }
            }
        }
    }
    private func setHidden(_ integration: RepositoryIntegration, _ hidden: Bool) {
        store.workspace.setIntegrationHidden(repositoryID: repo.id, integrationID: integration.id, hidden: hidden)
        store.rebuild()
    }
    private func findingRow(_ integration: RepositoryIntegration, compact: Bool = false) -> some View {
        IntegrationFindingRow(integration: integration, compact: compact, canEdit: store.workspace.canEdit) {
            setHidden(integration, true)
        }
    }
}

struct IntegrationFindingRow: View {
    let integration: RepositoryIntegration
    var compact = false
    var canEdit = true
    let hide: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "powerplug").foregroundStyle(.secondary).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(integration.name).font(.system(size: 13, weight: .medium))
                    Text(integration.category).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: hide) { Image(systemName: "eye.slash") }
                    .buttonStyle(.borderless).help("Hide Integration")
                    .accessibilityLabel("Hide \(integration.name)").disabled(!canEdit)
                if let url = ServiceCatalog.safeURL(integration.website) {
                    Link("Open", destination: url).buttonStyle(.bordered).controlSize(.small)
                }
            }

        }.padding(10).background(Color.panel, in: RoundedRectangle(cornerRadius: 8))
    }
}
