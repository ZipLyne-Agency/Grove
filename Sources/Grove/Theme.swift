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
    /// Text and icons that sit on a selection plate, and positive provider states.
    static let groveInk = Color(nsColor: NSColor(name: "GroveInk") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.56, green: 0.85, blue: 0.70, alpha: 1)
            : NSColor(srgbRed: 0.12, green: 0.35, blue: 0.25, alpha: 1)
    })
    /// Forest green row plate used instead of the system accent for every Grove selection.
    static let selection = Color(nsColor: NSColor(name: "GroveSelection") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.36, green: 0.76, blue: 0.56, alpha: 0.20)
            : NSColor(srgbRed: 0.18, green: 0.49, blue: 0.35, alpha: 0.15)
    })
    /// Warm accent reserved for Ask Grove.
    static let ember = Color(nsColor: NSColor(name: "GroveEmber") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.94, green: 0.64, blue: 0.38, alpha: 1)
            : NSColor(srgbRed: 0.71, green: 0.33, blue: 0.10, alpha: 1)
    })
    static let intelligence = ember
    static let danger = Color(nsColor: NSColor(name: "GroveDanger") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 1.0, green: 0.45, blue: 0.42, alpha: 1)
            : NSColor(srgbRed: 0.75, green: 0.17, blue: 0.15, alpha: 1)
    })
    static let caution = Color(nsColor: NSColor(name: "GroveCaution") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.92, green: 0.77, blue: 0.32, alpha: 1)
            : NSColor(srgbRed: 0.49, green: 0.38, blue: 0.0, alpha: 1)
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

extension LibraryScope {
    var title: String {
        switch self {
        case .all: "All Repositories"
        case .recent: "Recently Pushed"
        case .missing: "Needs a Description"
        case .archived: "Archived"
        case .forks: "Forks"
        }
    }
}

extension RepositorySort {
    var title: String {
        switch self {
        case .createdNewest: "Created: Newest First"
        case .createdOldest: "Created: Oldest First"
        case .pushed: "Pushed: Newest First"
        case .pushedOldest: "Pushed: Oldest First"
        case .updatedNewest: "Updated: Newest First"
        case .updatedOldest: "Updated: Oldest First"
        case .name: "Name: A to Z"
        case .nameDescending: "Name: Z to A"
        case .stars: "Stars: Most First"
        case .starsFewest: "Stars: Fewest First"
        case .issuesMost: "Issues & PRs: Most First"
        case .issuesFewest: "Issues & PRs: Fewest First"
        }
    }
}

extension RepositoryAction {
    var displayTitle: String {
        switch self {
        case .rename: "Rename Repository"
        case .describe: "Update Description"
        case .transfer: "Transfer Repository"
        case .archive(let value): value ? "Archive Repository" : "Unarchive Repository"
        case .delete: "Delete Repository"
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

/// Field label used in forms and fact grids.
struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary) }
}
