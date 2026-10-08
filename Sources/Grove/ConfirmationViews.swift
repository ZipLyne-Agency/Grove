import SwiftUI
import GroveCore

/// Shared sheet frame: badge, title, subtitle, content, then right-aligned buttons.
struct SheetFrame<Content: View, Buttons: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    var monospacedSubtitle = false
    var width: CGFloat = 460
    @ViewBuilder let content: Content
    @ViewBuilder let buttons: Buttons
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 17, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(monospacedSubtitle ? .system(size: 12, design: .monospaced) : .system(size: 12))
                            .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                    }
                }
            }
            content
            HStack(spacing: 8) { Spacer(); buttons }.padding(.top, 2)
        }
        .padding(22)
        .frame(width: width)
        .tint(.grove)
    }
}

/// A labeled value box. Values are selectable so long names can be checked.
struct ValueBox: View {
    let rows: [(String, String, Bool)]
    var tint: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.0).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    Text(row.1)
                        .font(row.2 ? .system(size: 12.5, design: .monospaced) : .system(size: 13))
                        .lineLimit(8).fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder((tint ?? Color.hairline).opacity(tint == nil ? 0.7 : 0.45)))
    }
}

struct FinePrint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct ConsentView: View {
    @Bindable var store: Store
    let item: Consent
    var body: some View {
        SheetFrame(symbol: symbol, tint: tint, title: title, subtitle: subtitle) {
            content
        } buttons: {
            Button("Cancel") { store.consent = nil }.keyboardShortcut(.cancelAction)
            Button(confirmTitle) { store.confirmConsent(item) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .disabled(store.busy)
        }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .refresh:
            Text("Grove reads your account, organizations and repository details with your GitHub CLI sign-in. Nothing on GitHub changes.")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .open(let repo):
            ValueBox(rows: [("Opens in your browser", repo.webURL?.absoluteString ?? repo.full_name, true)])
        case .url(let url):
            ValueBox(rows: [("Opens in your browser", url.absoluteString, true)])
            if url.path.contains("/settings/") {
                FinePrint("Organization names and profiles are changed on GitHub.")
            }
        case .copy(let text):
            ValueBox(rows: [("Clipboard", text, true)])
        case .ownerVisibility(let login, let hidden):
            let count = store.counts.count(owner: login)
            Text(hidden
                 ? "\(login) and its \(countLabel(count, "repository", "repositories")) leave your Grove library on this Mac. Nothing changes on GitHub. Restore it any time from Hidden in the sidebar."
                 : "\(login) and its \(countLabel(count, "repository", "repositories")) return to your Grove library on this Mac.")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .assistant(let prompt, let repo, let context):
            ValueBox(rows: [("Question", prompt, false), ("About", subject(repo: repo, context: context), repo != nil)])
            FinePrint(repo != nil
                      ? "Grove reads this repository's README from GitHub, then answers on this Mac with Apple Intelligence. A suggested change opens its own review."
                      : "Answers run on this Mac with Apple Intelligence. A suggested change opens its own review.")
        }
    }

    private func subject(repo: Repository?, context: Inventory?) -> String {
        if let repo { return repo.full_name }
        let count = context?.repositories.count ?? 0
        let name = store.assistantOwner ?? store.assistantScope.rawValue
        let sample = count > 35 ? ". Answers consider the 35 most recently pushed." : ""
        return "\(name) · \(countLabel(count, "repository", "repositories"))\(sample)"
    }
    private var symbol: String {
        switch item.kind {
        case .refresh: "arrow.clockwise"
        case .open, .url: "arrow.up.right.square"
        case .copy: "doc.on.doc"
        case .ownerVisibility(_, let hidden): hidden ? "eye.slash" : "eye"
        case .assistant: "text.bubble"
        }
    }
    private var tint: Color {
        if case .assistant = item.kind { return .intelligence }
        return .grove
    }
    private var title: String {
        switch item.kind {
        case .refresh: store.inventory == nil ? "Connect to GitHub?" : "Refresh repositories?"
        case .open: "Open on GitHub?"
        case .url(let url): url.path.contains("/settings/") ? "Open organization settings?" : "Open on GitHub?"
        case .copy(let text):
            text.hasPrefix("git clone ") ? "Copy clone command?" : text.hasPrefix("https://") ? "Copy GitHub link?" : "Copy name?"
        case .ownerVisibility(let login, let hidden): hidden ? "Hide \(login)?" : "Show \(login)?"
        case .assistant: "Ask Apple Intelligence?"
        }
    }
    private var subtitle: String? {
        switch item.kind {
        case .open(let repo): repo.full_name
        case .copy: "Puts this text on your clipboard."
        case .ownerVisibility: "Only changes this Mac."
        case .refresh: store.inventory.map { "Last updated \(GroveDates.named($0.fetchedAt))" }
        default: nil
        }
    }
    private var confirmTitle: String {
        switch item.kind {
        case .refresh: store.inventory == nil ? "Connect" : "Refresh"
        case .open, .url: "Open"
        case .copy: "Copy"
        case .ownerVisibility(_, let hidden): hidden ? "Hide" : "Show"
        case .assistant: "Ask"
        }
    }
}

struct EditorView: View {
    @Bindable var store: Store
    let request: EditorRequest
    @State private var value = ""
    @FocusState private var focused: Bool
    private var repo: Repository { request.repo }
    var body: some View {
        SheetFrame(symbol: symbol, tint: .grove, title: title, subtitle: repo.full_name, monospacedSubtitle: true) {
            switch request.kind {
            case .rename: renameFields
            case .description: descriptionFields
            case .transfer: transferFields
            }
        } buttons: {
            Button("Cancel") { store.editor = nil }.keyboardShortcut(.cancelAction)
            Button(reviewTitle) {
                store.editor = nil
                Task { await store.prepare(request.repo, action: action) }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!valid)
        }
        .onAppear {
            value = request.kind == .rename ? repo.name : request.kind == .description ? (repo.description ?? "") : ""
            focused = true
        }
    }

    @ViewBuilder private var renameFields: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("New Name").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField("Repository name", text: $value).textFieldStyle(.roundedBorder).autocorrectionDisabled().focused($focused)
        }
        ValueBox(rows: [("Will Become", "\(repo.owner.login)/\(value.isEmpty ? "…" : value)", true)])
        validationNote ?? FinePrint("Letters, numbers, dots, hyphens and underscores. GitHub redirects the old address.")
    }
    @ViewBuilder private var descriptionFields: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Description").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField("Describe the project in a sentence", text: $value, axis: .vertical)
                .lineLimit(3...6).textFieldStyle(.roundedBorder).focused($focused)
        }
        HStack {
            FinePrint(value.isEmpty ? "Leave empty to remove the description." : "Shown on GitHub and in search.")
            Spacer()
            Text("\(value.count) / 350").font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(value.count > 350 ? AnyShapeStyle(Color.danger) : AnyShapeStyle(.secondary))
        }
    }
    @ViewBuilder private var transferFields: some View {
        let choices = store.destinations.filter { $0.lowercased() != repo.owner.login.lowercased() }
        if choices.isEmpty {
            Text("None of your connected organizations can receive this repository.")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            Picker("To organization", selection: $value) {
                Text("Choose…").tag("")
                ForEach(choices, id: \.self) { Text($0).tag($0) }
            }
            ValueBox(rows: [("From", repo.full_name, true), ("To", value.isEmpty ? "Choose an organization" : "\(value)/\(repo.name)", true)])
            FinePrint("The next step shows the full review and asks for the exact name. GitHub applies the organization's rules.")
        }
    }
    private var validationNote: FinePrint? {
        guard request.kind == .rename, value != repo.name, !value.isEmpty else { return nil }
        do { try action.validate(for: repo, destinations: store.destinations); return nil }
        catch { return FinePrint((error as? LocalizedError)?.errorDescription ?? "Enter a different name.") }
    }
    private var symbol: String { switch request.kind { case .rename: "pencil"; case .description: "text.alignleft"; case .transfer: "arrow.right.arrow.left" } }
    private var title: String { switch request.kind { case .rename: "Rename Repository"; case .description: "Edit Description"; case .transfer: "Transfer to an Organization" } }
    private var reviewTitle: String { switch request.kind { case .rename: "Review Rename…"; case .description: "Review Description…"; case .transfer: "Review Transfer…" } }
    private var action: RepositoryAction { switch request.kind { case .rename: .rename(value); case .description: .describe(value); case .transfer: .transfer(value) } }
    private var valid: Bool { (try? action.validate(for: request.repo, destinations: store.destinations)) != nil }
}

struct ConfirmationView: View {
    @Bindable var store: Store
    let preview: ActionPreview
    @State private var typedName = ""
    private var deleting: Bool { preview.action == .delete }
    private var repo: Repository { preview.repository }
    private var matches: Bool { !preview.action.requiresTyping || typedName == repo.full_name }
    var body: some View {
        SheetFrame(symbol: symbol, tint: deleting ? .danger : .grove, title: preview.action.displayTitle + "?",
                   subtitle: "Signed in as \(preview.account)", width: 520) {
            ValueBox(rows: rows, tint: deleting ? Color.danger : nil)
            if let consequence {
                Text(consequence).font(.system(size: 12.5))
                    .foregroundStyle(deleting ? AnyShapeStyle(Color.danger) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if preview.action.requiresTyping {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        (Text("Type ") + Text(repo.full_name).font(.system(size: 12, design: .monospaced)) + Text(" to Confirm"))
                            .font(.system(size: 12, weight: .medium)).lineLimit(2).truncationMode(.middle)
                        Spacer(minLength: 8)
                        CopyButton(text: repo.full_name, title: "Copy Name")
                    }
                    // No onSubmit: Return never confirms a typed-name review.
                    TextField("Full repository name", text: $typedName)
                        .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        .font(.system(size: 13, design: .monospaced))
                        .accessibilityLabel("Type \(repo.full_name) to confirm")
                    if !typedName.isEmpty && !matches {
                        Text("Doesn't match yet.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            FinePrint("This review expires after five minutes. Grove checks the live repository before applying it.")
        } buttons: {
            Button("Cancel") { store.cancelPreview() }.keyboardShortcut(.cancelAction)
            Button(confirmTitle, role: deleting ? .destructive : nil) {
                store.confirmPreview(preview, typedName: typedName)
            }
            .buttonStyle(.borderedProminent)
            .tint(deleting ? .danger : .grove)
            .disabled(store.busy || store.operationInFlight || !matches)
        }
    }
    private var rows: [(String, String, Bool)] {
        switch preview.action {
        case .rename: [("From", repo.full_name, true), ("To", preview.destination, true)]
        case .describe: [("Repository", repo.full_name, true), ("Current", repo.hasDescription ? (repo.description ?? "") : "No description", false), ("New", preview.destination, false)]
        case .transfer: [("From", repo.full_name, true), ("To", preview.destination, true)]
        case .archive: [("Repository", repo.full_name, true), ("Result", preview.destination, false)]
        case .delete: [("Repository", repo.full_name, true), ("Result", preview.destination, false)]
        }
    }
    private var consequence: String? {
        switch preview.action {
        case .rename: "GitHub redirects the old address. Update local clone remotes when convenient."
        case .describe: nil
        case .transfer: "The owner and address change. Access, integrations and organization rules may change too. GitHub finishes transfers in the background."
        case .archive(let archive): archive ? "The repository becomes read-only. You can unarchive it later." : "The repository becomes writable again."
        case .delete: "Code, issues, pull requests and settings are deleted. Grove cannot undo this. Local clones are not affected."
        }
    }
    private var symbol: String {
        switch preview.action {
        case .rename: "pencil"
        case .describe: "text.alignleft"
        case .transfer: "arrow.right.arrow.left"
        case .archive: "archivebox"
        case .delete: "trash"
        }
    }
    private var confirmTitle: String {
        switch preview.action {
        case .rename: "Rename"
        case .describe: "Update Description"
        case .transfer: "Transfer"
        case .archive(let archive): archive ? "Archive" : "Unarchive"
        case .delete: "Delete Repository"
        }
    }
}
