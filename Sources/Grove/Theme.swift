import SwiftUI
import AppKit
import GroveCore

extension Color {
    /// Accent dark enough for white text in light mode and light enough to read on dark surfaces.
    static let grove = Color(nsColor: NSColor(name: "GroveAccent") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.36, green: 0.76, blue: 0.56, alpha: 1)
            : NSColor(srgbRed: 0.18, green: 0.49, blue: 0.35, alpha: 1)
    })
    static let intelligence = Color(nsColor: NSColor(name: "GroveIntelligence") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.72, green: 0.60, blue: 0.98, alpha: 1)
            : NSColor(srgbRed: 0.36, green: 0.21, blue: 0.66, alpha: 1)
    })
    static let danger = Color(nsColor: NSColor(name: "GroveDanger") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1.0, green: 0.45, blue: 0.42, alpha: 1)
            : NSColor(srgbRed: 0.75, green: 0.17, blue: 0.15, alpha: 1)
    })
    static let caution = Color(nsColor: NSColor(name: "GroveCaution") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1.0, green: 0.74, blue: 0.35, alpha: 1)
            : NSColor(srgbRed: 0.62, green: 0.38, blue: 0.0, alpha: 1)
    })
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
    static let inspector = Color(nsColor: .windowBackgroundColor)
    static let hairline = Color(nsColor: .separatorColor)

    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    static func language(_ name: String) -> Color {
        switch name {
        case "Swift": Color(hex: 0xF05138)
        case "TypeScript": Color(hex: 0x3178C6)
        case "JavaScript": Color(hex: 0xD9BE2B)
        case "Python": Color(hex: 0x3572A5)
        case "Kotlin": Color(hex: 0xA97BFF)
        case "Go": Color(hex: 0x00ADD8)
        case "Rust": Color(hex: 0xDEA584)
        case "Ruby": Color(hex: 0x701516)
        case "Java": Color(hex: 0xB07219)
        case "C": Color(hex: 0x555555)
        case "C++": Color(hex: 0xF34B7D)
        case "C#": Color(hex: 0x178600)
        case "Objective-C": Color(hex: 0x438EFF)
        case "HTML": Color(hex: 0xE34C26)
        case "CSS", "SCSS": Color(hex: 0x663399)
        case "Shell": Color(hex: 0x89E051)
        case "Dart": Color(hex: 0x00B4AB)
        case "PHP": Color(hex: 0x4F5D95)
        case "Vue": Color(hex: 0x41B883)
        case "Svelte": Color(hex: 0xFF3E00)
        case "Astro": Color(hex: 0xFF5A03)
        case "MDX": Color(hex: 0xFCB32C)
        case "Dockerfile": Color(hex: 0x384D54)
        case "Elixir": Color(hex: 0x6E4A7E)
        case "Lua": Color(hex: 0x000080)
        case "Jupyter Notebook": Color(hex: 0xDA5B0B)
        default: Color.secondary
        }
    }
}

extension Repository {
    var visibilityLabel: String { `private` ? "Private" : "Public" }
    var visibilitySymbol: String { `private` ? "lock.fill" : "globe" }
    var glyphSymbol: String { archived ? "archivebox" : fork ? "arrow.triangle.branch" : "book.closed" }
    var cloneCommand: String { "git clone https://github.com/\(full_name).git" }
}

/// Parsing ISO dates is not free; list rows ask for the same timestamps on every render.
@MainActor enum GroveDates {
    private static let parser = ISO8601DateFormatter()
    private static var cache: [String: Date] = [:]
    static func pushed(_ repo: Repository) -> Date? {
        guard let raw = repo.pushed_at else { return nil }
        if let date = cache[raw] { return date }
        let date = parser.date(from: raw)
        if let date { cache[raw] = date }
        return date
    }
    static func short(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "Never" }
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "Now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<604_800: return "\(Int(seconds / 86_400))d"
        case ..<2_592_000: return "\(Int(seconds / 604_800))w"
        case ..<31_536_000: return "\(Int(seconds / 2_592_000))mo"
        default: return "\(Int(seconds / 31_536_000))y"
        }
    }
    static func named(_ date: Date?) -> String { date?.formatted(.relative(presentation: .named)) ?? "Never" }
    static func exact(_ date: Date?) -> String { date?.formatted(date: .abbreviated, time: .shortened) ?? "Never" }
}

func countLabel(_ count: Int, _ singular: String, _ plural: String) -> String {
    "\(count.formatted()) \(count == 1 ? singular : plural)"
}

struct LeafMark: View {
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: "leaf.fill").font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white).frame(width: size, height: size)
            .background(Color.grove, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct RepositoryGlyph: View {
    let repo: Repository
    var size: CGFloat = 28
    var body: some View {
        Image(systemName: repo.glyphSymbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(repo.archived ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.grove))
            .frame(width: size, height: size)
            .background((repo.archived ? Color.secondary : Color.grove).opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct LanguageDot: View {
    let language: String
    var size: CGFloat = 8
    var body: some View { Circle().fill(Color.language(language)).frame(width: size, height: size).accessibilityHidden(true) }
}

struct GroveTag: View {
    let text: String
    var symbol: String? = nil
    var tint: Color? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background((tint ?? Color.primary).opacity(0.09), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

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
