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
        Button("Copy Link") { copy(connection.dashboardURL) }.disabled(!connection.canOpen)
        Divider()
        Button("Show in Services") {
            workspace.destination = .connections; workspace.selectedConnectionID = connection.id; ui.selectedAccountID = nil
        }
        Button("Edit…") { ui.sheet = .editConnection(connection, isNew: false) }.disabled(!workspace.canEdit)
        Button(connection.pinned ? "Unpin From Quick Access" : "Pin to Quick Access") {
            var next = connection; next.pinned.toggle(); workspace.saveConnection(next)
        }
        .disabled(!workspace.canEdit)
        Divider()
        if let context {
            Button(context.unlinkTitle) { ui.sheet = .unlink(connection, context) }.disabled(!workspace.canEdit)
        }
        Button("Remove Service…", role: .destructive) { ui.sheet = .removeConnection(connection) }.disabled(!workspace.canEdit)
    }
    private func copy(_ text: String) {
        Clipboard.copy(text)
        if let onCopy { onCopy() } else { workspace.notice = "Copied" }
    }
}

/// Saved services use the same compact rows in repositories and projects.
struct ServiceList: View {
    let store: Store
    let ui: WorkspaceUI
    let connections: [ServiceConnection]
    let context: LinkTarget
    var usedBy: ((ServiceConnection) -> String?)? = nil
    let add: () -> Void
    var body: some View {
        TableBox {
            ForEach(connections) { connection in
                ServiceRow(store: store, ui: ui, connection: connection, context: context)
            }
            Button(action: add) { Label("Add Service", systemImage: "plus") }
                .buttonStyle(.plain).foregroundStyle(Color.groveInk)
                .padding(.horizontal, 12).frame(minHeight: 42)
                .disabled(!store.workspace.canEdit)
        }
    }
}

struct ServiceRow: View {
    let store: Store
    let ui: WorkspaceUI
    let connection: ServiceConnection
    var usedBy: String? = nil
    var context: LinkTarget? = nil
    var body: some View {
        HStack(spacing: 10) {
            ProviderTile(provider: connection.provider, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.linkTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(connection.dashboardURL).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open") { store.workspace.open(connection) }
                .controlSize(.small).disabled(!connection.canOpen).help(connection.dashboardURL)
            Menu { ServiceMenu(store: store, ui: ui, connection: connection, context: context) }
                label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Edit \(connection.name)")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contextMenu { ServiceMenu(store: store, ui: ui, connection: connection, context: context) }
    }
}
