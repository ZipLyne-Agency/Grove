import SwiftUI
import AppKit
import GroveCore

/// Window-only presentation state for projects, connections, and their sheets.
@MainActor @Observable
final class WorkspaceUI {
    var sheet: WorkspaceSheet?
    var showAllProjects = true
    var projectRepositoryID: Int?
    var selectedAccountID: UUID?
}

enum LinkTarget: Hashable { case repository(Int), project(UUID) }

extension LinkTarget {
    var unlinkTitle: String {
        switch self { case .repository: "Unlink From This Repository…"; case .project: "Unlink From This Project…" }
    }
}

enum WorkspaceSheet: Identifiable {
    case editProject(GroveProject, isNew: Bool)
    case deleteProject(GroveProject)
    case editConnection(ServiceConnection, isNew: Bool)
    case removeConnection(ServiceConnection)
    case unlink(ServiceConnection, LinkTarget)
    case editAccount(ProviderAccount, isNew: Bool)
    case removeAccount(ProviderAccount)
    case discover(Repository)
    case renameService(ServiceConnection)
    var id: String {
        switch self {
        case .editProject(let project, _): "project-\(project.id)"
        case .deleteProject(let project): "delete-project-\(project.id)"
        case .editConnection(let connection, _): "connection-\(connection.id)"
        case .removeConnection(let connection): "remove-connection-\(connection.id)"
        case .unlink(let connection, _): "unlink-\(connection.id)"
        case .editAccount(let account, _): "account-\(account.id)"
        case .removeAccount(let account): "remove-account-\(account.id)"
        case .discover(let repo): "discover-\(repo.id)"
        case .renameService(let connection): "rename-\(connection.id)"
        }
    }
}

enum RepositoryTab: String, CaseIterable { case overview = "Overview", services = "Services", activity = "Activity", manage = "Manage" }

// MARK: Status

/// How Grove knows about a service, and what it last learned. Green appears only for a current verified read.
struct ServiceLook {
    let badge: String
    let badgeSymbol: String
    let tint: Color
    let dashed: Bool
    let line: String
    let lineSymbol: String
    let lineTint: Color
    let attention: Bool
    let dimmed: Bool

    @MainActor init(_ connection: ServiceConnection, syncing: Bool, now: Date = Date()) {
        let status = connection.status(now: now)
        dashed = status == .suggested
        attention = status == .failed || status == .needsAuthorization
        dimmed = status == .stale
        badge = status.rawValue
        switch status {
        case .verified: badgeSymbol = "checkmark"; tint = .groveInk
        case .stale: badgeSymbol = "clock"; tint = .secondary
        case .failed: badgeSymbol = "exclamationmark.triangle"; tint = .caution
        case .needsAuthorization: badgeSymbol = "key"; tint = .caution
        case .savedLink: badgeSymbol = "link"; tint = .secondary
        case .suggested: badgeSymbol = "sparkle.magnifyingglass"; tint = .secondary
        case .unverified: badgeSymbol = "minus"; tint = .secondary
        }
        if syncing {
            line = connection.snapshot == nil ? "Checking…" : "Checking Again…"
            lineSymbol = "arrow.triangle.2.circlepath"; lineTint = .secondary; return
        }
        switch status {
        case .verified:
            line = "Checked \(GroveDates.named(connection.snapshot?.checkedAt))"; lineSymbol = "checkmark.circle"; lineTint = .groveInk
        case .stale:
            line = "Out of Date · Last Checked \(GroveDates.named(connection.snapshot?.checkedAt))"; lineSymbol = "clock"; lineTint = .secondary
        case .failed:
            line = connection.lastError ?? "The last check failed."; lineSymbol = "exclamationmark.triangle"; lineTint = .caution
        case .needsAuthorization:
            line = connection.lastError ?? "Update this account's credentials."; lineSymbol = "key"; lineTint = .caution
        case .savedLink:
            line = "No Status · Grove does not check saved links."; lineSymbol = "minus"; lineTint = .secondary
        case .suggested:
            line = "Not Connected · Found in \(connection.source ?? "repository configuration")"; lineSymbol = "minus"; lineTint = .secondary
        case .unverified:
            line = "Not Checked Yet"; lineSymbol = "minus"; lineTint = .secondary
        }
    }
}

extension ServiceConnection {
    @MainActor var provenance: String {
        if let snapshot { return "\(provider.title) API · Checked \(GroveDates.named(snapshot.checkedAt))" }
        switch origin {
        case .repository: return "Repository Configuration\(source.map { " · \($0)" } ?? "")"
        case .provider: return "\(provider.title) Account"
        case .manual: return accountID == nil ? "Saved Link" : "Added Manually"
        }
    }
    var displayIdentity: String { resourceID.isEmpty ? (provider == .custom ? dashboardURL : "No Resource ID") : resourceID }
    var canOpen: Bool { ServiceCatalog.safeURL(dashboardURL) != nil }
}

// MARK: Activity

/// One dated event from a verified service or GitHub.
struct ActivityItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let date: Date?
    let url: URL?
    let symbol: String
}

@MainActor enum ActivityFeed {
    static func items(connections: [ServiceConnection], repositories: [Repository]) -> [ActivityItem] {
        var items: [ActivityItem] = []
        for connection in connections {
            for event in connection.snapshot?.activity ?? [] {
                items.append(ActivityItem(id: "\(connection.id)-\(event.id)", title: event.title,
                                          detail: [connection.provider.title, connection.name, event.detail].filter { !$0.isEmpty }.joined(separator: " · "),
                                          date: event.date, url: event.url.flatMap(ServiceCatalog.safeURL), symbol: connection.provider.symbol))
            }
        }
        for repo in repositories {
            if let pushed = GroveDates.pushed(repo) {
                items.append(ActivityItem(id: "push-\(repo.id)", title: "Pushed to \(repo.default_branch)", detail: "GitHub · \(repo.name)", date: pushed, url: repo.webURL, symbol: "arrow.up.circle"))
            }
            if let created = repo.createdDate {
                items.append(ActivityItem(id: "created-\(repo.id)", title: "Repository Created", detail: "GitHub · \(repo.name)", date: created, url: repo.webURL, symbol: "plus.circle"))
            }
        }
        return items.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

struct ActivityList: View {
    let items: [ActivityItem]
    var limit: Int? = nil
    var body: some View {
        let shown = limit.map { Array(items.prefix($0)) } ?? items
        if shown.isEmpty {
            Text("No Recent Activity Recorded").font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(shown) { item in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: item.symbol).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                            Text(item.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(GroveDates.short(item.date)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                            .help(GroveDates.exact(item.date))
                        if let url = item.url {
                            Button { NSWorkspace.shared.open(url) } label: { Label("Open", systemImage: "arrow.up.right") }
                                .buttonStyle(IconButtonStyle(size: 20)).help("Open \(url.host() ?? "Link")")
                        }
                    }
                }
            }
        }
    }
}
