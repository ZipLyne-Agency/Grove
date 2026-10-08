import SwiftUI
import AppKit

/// Small borderless icon button with a hover plate, used in toolbars and hover actions.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 26
    var tint: Color? = nil
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, size: size, tint: tint, active: active)
    }
}
private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    let tint: Color?
    let active: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        configuration.label
            .font(.system(size: max(11, size * 0.5), weight: .medium))
            .labelStyle(.iconOnly)
            .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : (hovering || active) ? 0.08 : 0)))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.35)
            .onHover { hovering = $0 }
    }
}

/// Full-width list-style row button for grouped actions.
struct RowButtonStyle: ButtonStyle {
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        RowButtonBody(configuration: configuration, destructive: destructive)
    }
}
private struct RowButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let destructive: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(destructive ? AnyShapeStyle(Color.danger) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(Color.primary.opacity(configuration.isPressed ? 0.1 : (hovering && isEnabled) ? 0.05 : 0))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 }
    }
}

/// Rounded container with hairline dividers between its rows.
struct GroupedRows<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                    if index > 0 { Divider().padding(.leading, 34) }
                    subview
                }
            }
        }
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.hairline.opacity(0.6)))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A rounded group of full-width rows with hairlines, used for tables in detail panes.
struct TableBox<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                    if index > 0 { Divider() }
                    subview
                }
            }
        }
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.hairline.opacity(0.7)))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            size.width = min(size.width, limit)
            if x > 0, x + size.width > limit { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing; row = max(row, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            size.width = min(size.width, bounds.width)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material; view.blendingMode = blending; view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material; view.blendingMode = blending
    }
}

/// Empty toolbar and sidebar space under the transparent title bar still moves and zooms the window.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
        }
    }
}

/// One-line status strip under the toolbar.
struct NoticeBar: View {
    let text: String
    let symbol: String
    let tint: Color
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var dismiss: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 8)
            if let actionTitle, let action { Button(actionTitle, action: action).controlSize(.small) }
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(IconButtonStyle(size: 20)).help("Dismiss").accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(tint.opacity(0.1))
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Selection and hover plate that replaces the system accent highlight.
struct RowPlate: ViewModifier {
    let selected: Bool
    var radius: CGFloat = 8
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(selected ? Color.selection : Color.primary.opacity(hovering ? 0.05 : 0)))
            .onHover { hovering = $0 }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
extension View {
    func rowPlate(selected: Bool, radius: CGFloat = 8) -> some View { modifier(RowPlate(selected: selected, radius: radius)) }
}

/// Small inline confirmation shown after a copy, then removed.
struct CopiedBadge: View {
    var text = "Copied"
    var body: some View {
        Label(text, systemImage: "checkmark")
            .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.groveInk)
            .lineLimit(1).truncationMode(.middle)
            .padding(.horizontal, 8).frame(height: 22)
            .background(Color.selection, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon.imageScale(.small); configuration.title }
    }
}

/// Section label with an optional trailing caption.
struct DetailSection<Content: View>: View {
    let title: String
    var caption: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title)
                Spacer(minLength: 8)
                if let caption { Text(caption).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
            }
            content
        }
    }
}

/// The custom tab bar used by repository and project detail.
struct DetailTabs<Tab: Hashable & RawRepresentable>: View where Tab.RawValue == String {
    let tabs: [Tab]
    @Binding var selection: Tab
    var counts: [Tab: Int] = [:]
    var body: some View {
        HStack(spacing: 22) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                Button { selection = tab } label: {
                    HStack(spacing: 5) {
                        Text(tab.rawValue).font(.system(size: 13, weight: selection == tab ? .semibold : .regular))
                            .foregroundStyle(selection == tab ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        if let count = counts[tab] {
                            Text(count.formatted()).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .padding(.bottom, 9)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(selection == tab ? Color.grove : Color.clear).frame(height: 2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .overlay(alignment: .bottom) { Divider() }
    }
}
