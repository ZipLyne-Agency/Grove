import SwiftUI
import GroveCore

struct ConnectionsColumn: View {
    @Bindable var store: Store
    let ui: WorkspaceUI
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(store.workspace.connections.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { connection in
                    Button { store.workspace.selectedConnectionID = connection.id; ui.selectedAccountID = nil } label: {
                        HStack(spacing: 9) {
                            ProviderTile(provider: connection.provider)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connection.linkTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(connection.dashboardURL).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }.padding(10).contentShape(Rectangle())
                    }.buttonStyle(.plain).rowPlate(selected: store.workspace.selectedConnectionID == connection.id)
                }
            }.padding(6)
        }.scrollIndicators(.never)
    }
}

struct ConnectionDetailView: View {
    let store: Store
    let ui: WorkspaceUI
    let connection: ServiceConnection
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(connection.linkTitle).font(.system(size: 20, weight: .semibold))
            Text(connection.dashboardURL).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button("Open") { store.workspace.open(connection) }.disabled(!connection.canOpen)
                Button("Edit…") { ui.sheet = .editConnection(connection, isNew: false) }.disabled(!store.workspace.canEdit)
                Menu { ServiceMenu(store: store, ui: ui, connection: connection) } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            Spacer()
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color.inspector)
    }
}
