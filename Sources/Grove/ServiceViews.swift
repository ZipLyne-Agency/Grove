import SwiftUI
import AppKit
import GroveCore

struct ProviderTile: View {
    let provider: ServiceProvider
    var size: CGFloat = 28
    var body: some View {
        Image(systemName: provider.symbol)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct ProjectTile: View {
    let project: GroveProject
    var size: CGFloat = 18
    private static let palette: [Color] = [Color(hex: 0x2E7D59), Color(hex: 0x8A5A2B), Color(hex: 0x3F6C8C), Color(hex: 0x7A4E8C),
                                           Color(hex: 0x9C4A3A), Color(hex: 0x4F6B2E), Color(hex: 0x2F6F73), Color(hex: 0x6B5B3E)]
    var body: some View {
        Text(String(project.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.system(size: size * 0.55, weight: .bold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Self.palette[Int(project.id.uuid.0) % Self.palette.count], in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct KindBadge: View {
    let look: ServiceLook
    var body: some View {
        Label(look.badge, systemImage: look.badgeSymbol)
            .labelStyle(CompactLabelStyle())
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(look.tint)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(look.dashed ? Color.clear : look.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                if look.dashed {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
    }
}

struct EnvironmentTag: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.hairline))
    }
}

/// One service with its exact identity, honest state, available metrics, and actions.
struct ServiceCard: View {
    let store: Store
    let ui: WorkspaceUI
    let connection: ServiceConnection
    var context: LinkTarget? = nil
    var usedBy: String? = nil
    @State private var copied = false
    private var workspace: WorkspaceStore { store.workspace }
    var body: some View {
        let look = ServiceLook(connection, syncing: workspace.syncing.contains(connection.id))
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                ProviderTile(provider: connection.provider)
                VStack(alignment: .leading, spacing: 1) {
                    Text(connection.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                    Text(connection.displayIdentity).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail).help(connection.displayIdentity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                KindBadge(look: look)
            }
            HStack(spacing: 6) {
                Image(systemName: look.lineSymbol).imageScale(.small).accessibilityHidden(true)
                Text(look.line).lineLimit(2).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                if !connection.environment.isEmpty { EnvironmentTag(text: connection.environment) }
            }
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(look.lineTint)
            metrics.opacity(look.dimmed ? 0.6 : 1)
            Spacer(minLength: 0)
            footer
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(look.dashed ? Color.clear : Color.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.hairline.opacity(look.dashed ? 1 : 0.7), style: StrokeStyle(lineWidth: 1, dash: look.dashed ? [4, 3] : [])))
        .contextMenu { ServiceMenu(store: store, ui: ui, connection: connection, context: context) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(connection.name), \(connection.provider.title), \(look.badge)")
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array((connection.snapshot?.metrics ?? []).prefix(3).enumerated()), id: \.offset) { _, metric in
                HStack(spacing: 8) {
                    Text(metric.label).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(metric.value).monospacedDigit().lineLimit(1).truncationMode(.tail)
                }
            }
            if let notice = connection.snapshot?.notice {
                Text(notice).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if let usedBy {
                HStack(spacing: 8) {
                    Text("Used By").foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(usedBy).lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .font(.system(size: 11.5))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(copied ? "Copied Dashboard Link" : connection.provenance)
                .font(.system(size: 11)).foregroundStyle(copied ? AnyShapeStyle(Color.groveInk) : AnyShapeStyle(.secondary))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if connection.status() == .suggested {
                Button("Connect…") { ui.sheet = .editConnection(connection, isNew: false) }.disabled(!workspace.canEdit)
            } else if connection.provider.supportsAPI && connection.accountID != nil && connection.status() != .verified {
                Button("Sync") { workspace.requestSync(connection.id) }
                    .disabled(workspace.syncing.contains(connection.id) || !workspace.canEdit)
            }
            Button("Open Dashboard") { workspace.open(connection) }
                .disabled(!connection.canOpen)
                .help(connection.canOpen ? connection.dashboardURL : "Add a dashboard link to open this service.")
            Menu {
                ServiceMenu(store: store, ui: ui, connection: connection, context: context, onCopy: flashCopied)
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("More Actions").accessibilityLabel("More Actions")
        }
        .controlSize(.small)
    }
    private func flashCopied() {
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.6)); copied = false }
    }
}

/// Actions for one service, shared by the card, rows, and the connection detail.
struct ServiceMenu: View {
    let store: Store
    let ui: WorkspaceUI
    let connection: ServiceConnection
    var context: LinkTarget? = nil
    var onCopy: (() -> Void)? = nil
    private var workspace: WorkspaceStore { store.workspace }
    private var settingsURL: String { ServiceCatalog.settings(connection, account: workspace.account(for: connection)) }
    var body: some View {
        Button("Open Dashboard") { workspace.open(connection) }.disabled(!connection.canOpen)
        if settingsURL != connection.dashboardURL, let url = ServiceCatalog.safeURL(settingsURL) {
            Button("Open \(connection.provider.title) Settings") { NSWorkspace.shared.open(url) }
        }
        Button("Copy Dashboard Link") { copy(connection.dashboardURL) }.disabled(!connection.canOpen)
        if !connection.resourceID.isEmpty {
            Button("Copy Resource ID") { copy(connection.resourceID) }
        }
        if connection.provider.supportsAPI && connection.accountID != nil {
            Button("Sync Now") { workspace.requestSync(connection.id) }.disabled(workspace.syncing.contains(connection.id) || !workspace.canEdit)
        }
        Divider()
        Button("Show in Connections") {
            workspace.destination = .connections; workspace.selectedConnectionID = connection.id; ui.selectedAccountID = nil
        }
        Button("Edit…") { ui.sheet = .editConnection(connection, isNew: false) }.disabled(!workspace.canEdit)
        Button(connection.pinned ? "Unpin From Quick Access" : "Pin to Quick Access") {
            var next = connection; next.pinned.toggle(); workspace.saveConnection(next)
        }
        .disabled(!workspace.canEdit)
        if connection.provider.supportsRename && connection.accountID != nil && connection.snapshot != nil {
            Button("Rename at \(connection.provider.title)…") { ui.sheet = .renameService(connection) }.disabled(!workspace.canEdit)
        }
        Divider()
        if let context {
            Button(context.unlinkTitle) { ui.sheet = .unlink(connection, context) }.disabled(!workspace.canEdit)
        }
        Button("Remove Connection…", role: .destructive) { ui.sheet = .removeConnection(connection) }.disabled(!workspace.canEdit)
    }
    private func copy(_ text: String) {
        Clipboard.copy(text)
        if let onCopy { onCopy() } else { workspace.notice = "Copied" }
    }
}

/// Grid of service cards ending in an Add Connection tile.
struct ServiceGrid: View {
    let store: Store
    let ui: WorkspaceUI
    let connections: [ServiceConnection]
    let context: LinkTarget
    var usedBy: ((ServiceConnection) -> String?)? = nil
    let add: () -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
            ForEach(connections) { connection in
                ServiceCard(store: store, ui: ui, connection: connection, context: context, usedBy: usedBy?(connection))
            }
            Button(action: add) {
                VStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                    Text("Add Connection").font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                    Text("Verify With an Account or Save a Link").font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 150)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!store.workspace.canEdit)
        }
    }
}

/// Compact one-line service row for summaries and tables.
struct ServiceRow: View {
    let store: Store
    let ui: WorkspaceUI
    let connection: ServiceConnection
    var usedBy: String? = nil
    var context: LinkTarget? = nil
    var body: some View {
        let look = ServiceLook(connection, syncing: store.workspace.syncing.contains(connection.id))
        HStack(spacing: 9) {
            ProviderTile(provider: connection.provider, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(connection.displayIdentity).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !connection.environment.isEmpty { EnvironmentTag(text: connection.environment) }
            if let usedBy {
                Text(usedBy).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(width: 110, alignment: .leading)
            }
            Label(look.badge, systemImage: look.badgeSymbol).labelStyle(CompactLabelStyle())
                .font(.system(size: 11, weight: .medium)).foregroundStyle(look.tint).lineLimit(1).fixedSize()
            Button { store.workspace.open(connection) } label: { Label("Open Dashboard", systemImage: "arrow.up.right") }
                .buttonStyle(IconButtonStyle(size: 22)).help("Open Dashboard").disabled(!connection.canOpen)
        }
        .padding(.horizontal, 10).frame(minHeight: 42)
        .contentShape(Rectangle())
        .contextMenu { ServiceMenu(store: store, ui: ui, connection: connection, context: context) }
    }
}
