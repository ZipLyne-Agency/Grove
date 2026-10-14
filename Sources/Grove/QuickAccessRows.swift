import SwiftUI
import GroveCore

/// One repository in Quick Access, shown by name only. Copy and Open finish here without showing the Grove window.
struct QuickAccessRow: View {
    let repo: GroveCore.Repository
    let highlighted: Bool
    let reveal: () -> Void
    let copy: () -> Void
    let open: () -> Void
    let ask: () -> Void
    @State private var hovering = false
    private var active: Bool { hovering || highlighted }
    var body: some View {
        HStack(spacing: 10) {
            Text(repo.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
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
        .padding(.horizontal, 10).frame(minHeight: 32)
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
