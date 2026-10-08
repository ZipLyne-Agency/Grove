import SwiftUI
import GroveCore

/// One repository in Quick Access. Copy and Open finish here without showing the Grove window.
struct QuickAccessRow: View {
    let repo: GroveCore.Repository
    var description: String? = nil
    let highlighted: Bool
    let reveal: () -> Void
    let copy: () -> Void
    let open: () -> Void
    let ask: () -> Void
    @State private var hovering = false
    private var active: Bool { hovering || highlighted }
    private var detail: String {
        var parts = [repo.owner.login]
        if let language = repo.language { parts.append(language) }
        if repo.archived { parts.append("Archived") }
        if let description = description ?? repo.description, !description.isEmpty { parts.append(description) }
        else { parts.append(repo.visibilityLabel) }
        return parts.joined(separator: " · ")
    }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(repo.language.map(Color.language) ?? Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7).padding(.top, 6).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(repo.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    if repo.private { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary).accessibilityHidden(true) }
                    Spacer(minLength: 6)
                    if !active {
                        let pushed = GroveDates.pushed(repo)
                        Text(GroveDates.short(pushed)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                            .help("Last Pushed \(GroveDates.exact(pushed))")
                    }
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            if active {
                HStack(spacing: 1) {
                    Button(action: copy) { Label("Copy Link", systemImage: "link") }.help("Copy Link")
                    Button(action: open) { Label("Open on GitHub", systemImage: "arrow.up.right") }.help("Open on GitHub")
                    Button(action: ask) { Label { Text("Ask Grove") } icon: { GroveMark(size: 14, available: Intelligence.available) } }
                        .help("Ask Grove About This Repository")
                        .disabled(!Intelligence.available)
                }
                .buttonStyle(IconButtonStyle(size: 24))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(minHeight: 46)
        .background(active ? Color.selection : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: reveal)
        .onHover { hovering = $0 }
        .help("Show in Grove")
        .contextMenu {
            Button("Show in Grove", action: reveal)
            Button("Copy Link", action: copy)
            Button("Open on GitHub", action: open)
            Button("Ask Grove…", action: ask).disabled(!Intelligence.available)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(repo.full_name), pushed \(GroveDates.named(GroveDates.pushed(repo)))")
        .accessibilityAddTraits(highlighted ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { reveal() }
        .accessibilityAction(named: "Copy Link", copy)
        .accessibilityAction(named: "Open on GitHub", open)
        .accessibilityAction(named: "Ask Grove", ask)
    }
}

/// A pinned service: open its exact saved dashboard or copy the link, without showing the window.
struct PinnedServiceRow: View {
    let connection: ServiceConnection
    let look: ServiceLook
    let copy: () -> Void
    let open: () -> Void
    var body: some View {
        HStack(spacing: 9) {
            ProviderTile(provider: connection.provider, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.linkTitle).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                HStack(spacing: 4) {
                    Image(systemName: look.badgeSymbol).imageScale(.small).accessibilityHidden(true)
                    Text(connection.dashboardURL).lineLimit(1)
                }
                .font(.system(size: 11)).foregroundStyle(look.attention ? AnyShapeStyle(Color.caution) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 6)
            Button(action: copy) { Label("Copy Dashboard Link", systemImage: "link") }
                .buttonStyle(IconButtonStyle(size: 24)).help("Copy Dashboard Link").disabled(!connection.canOpen)
            Button(action: open) { Label("Open Dashboard", systemImage: "arrow.up.right") }
                .buttonStyle(IconButtonStyle(size: 24)).help(connection.canOpen ? connection.dashboardURL : "No dashboard link saved").disabled(!connection.canOpen)
        }
        .padding(.horizontal, 10).frame(minHeight: 40)
        .rowPlate(selected: false)
        .contextMenu {
            Button("Open Dashboard", action: open).disabled(!connection.canOpen)
            Button("Copy Dashboard Link", action: copy).disabled(!connection.canOpen)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(connection.name), \(connection.provider.title), \(look.badge)")
    }
}

/// A pinned project: shows it in the Grove window.
struct PinnedProjectRow: View {
    let store: Store
    let project: GroveProject
    let show: () -> Void
    var body: some View {
        let services = store.workspace.connections(for: project)
        Button(action: show) {
            HStack(spacing: 9) {
                ProjectTile(project: project, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    Text("\(countLabel(project.repositoryIDs.count, "Repository", "Repositories")) · \(countLabel(services.count, "Service", "Services"))")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).frame(minHeight: 40).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowPlate(selected: false)
        .help("Show \(project.name) in Grove")
    }
}
