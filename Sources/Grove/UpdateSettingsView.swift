import SwiftUI

struct UpdateSettingsView: View {
    let store: Store
    var body: some View {
        if let updates = store.updates {
            DetailSection(title: "Updates") {
                HStack {
                    Text("Grove \(updates.version)").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("Check for Updates…") { updates.checkForUpdates() }
                        .disabled(!updates.canCheck || store.updateBlockingReason != nil || store.installingUpdate)
                }
                Toggle("Automatically Check for Updates", isOn: Binding(get: { updates.automaticChecks }, set: { updates.setAutomaticChecks($0) }))
                    .font(.system(size: 12))
                Text(updates.status ?? "Grove verifies signed updates before installing. Your repositories and saved settings stay on this Mac.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
