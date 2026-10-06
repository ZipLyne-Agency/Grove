import SwiftUI
import GroveCore

struct InspectorView: View {
    @Bindable var store: Store
    var body: some View {
        Group {
            if let repo = store.selected {
                ScrollView { details(repo).padding(20) }
                    .contextMenu { RepositoryMenu(store: store, repo: repo) }
            } else if store.inventory == nil {
                ContentUnavailableView("No Details Yet", systemImage: "sidebar.right",
                                       description: Text("Connect GitHub to see repository details here."))
            } else {
                ContentUnavailableView("No Selection", systemImage: "sidebar.right",
                                       description: Text("Select a repository to see its details and actions."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.inspector)
    }

    private func details(_ repo: Repository) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            header(repo)
            quickActions(repo)
            about(repo)
            facts(repo)
            manage(repo)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ repo: Repository) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                RepositoryGlyph(repo: repo, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(repo.name).font(.system(size: 18, weight: .semibold))
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Text(repo.full_name).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }
            }
            FlowLayout(spacing: 6) {
                GroveTag(text: repo.visibilityLabel, symbol: repo.visibilitySymbol)
                if repo.archived { GroveTag(text: "Archived", symbol: "archivebox", tint: .caution) }
                if repo.fork { GroveTag(text: "Fork", symbol: "arrow.triangle.branch") }
                GroveTag(text: repo.canAdminister ? "Admin" : "No admin access", symbol: repo.canAdminister ? "checkmark.shield" : "shield.slash")
            }
        }
    }

    private func quickActions(_ repo: Repository) -> some View {
        HStack(spacing: 8) {
            Button { store.requestOpen(repo) } label: { Label("Open", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity) }
                .help("Open \(repo.full_name) on GitHub")
            Button { if let url = repo.webURL { store.requestCopy(url.absoluteString) } } label: {
                Label("Copy Link", systemImage: "link").frame(maxWidth: .infinity)
            }.help("Copy the GitHub link")
            Button {
                store.selectedID = repo.id; store.assistantFocus = .repository; store.assistantOwner = nil; store.showAssistant = true
            } label: { Label("Ask", systemImage: "sparkles").frame(maxWidth: .infinity) }
                .tint(.intelligence)
                .help("Ask Grove about this repository")
                .disabled(!Intelligence.available)
        }
        .controlSize(.regular)
        .disabled(!store.canStartReview)
    }

    private func about(_ repo: Repository) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("About")
            if repo.hasDescription {
                Text(repo.description ?? "").font(.system(size: 13)).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            } else {
                Text("No description").font(.system(size: 13)).foregroundStyle(.secondary)
                if repo.canAdminister {
                    Button("Add a Description…") { store.requestEdit(repo, kind: .description) }
                        .buttonStyle(.link).font(.system(size: 12))
                        .disabled(!store.canStartReview || store.needsRefresh)
                }
            }
            if let topics = repo.topics, !topics.isEmpty {
                FlowLayout(spacing: 5) { ForEach(topics, id: \.self) { GroveTag(text: $0, tint: .grove) } }
                    .padding(.top, 2)
            }
        }
    }

    private func facts(_ repo: Repository) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Details")
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 7) {
                fact("Language") {
                    if let language = repo.language { HStack(spacing: 5) { LanguageDot(language: language); Text(language) } }
                    else { Text("Not detected").foregroundStyle(.secondary) }
                }
                fact("Default branch") { Text(repo.default_branch).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle) }
                fact("Stars") { Text(repo.stargazers_count.formatted()).monospacedDigit() }
                fact("Open issues & PRs") { Text(repo.open_issues_count.formatted()).monospacedDigit() }
                fact("Last pushed") {
                    let pushed = GroveDates.pushed(repo)
                    Text(GroveDates.named(pushed)).help(GroveDates.exact(pushed))
                }
            }
            .font(.system(size: 12))
        }
    }
    private func fact<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            value().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func manage(_ repo: Repository) -> some View {
        let reason = manageBlockedReason(repo)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Manage")
            if let reason {
                Label(reason, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GroupedRows {
                Button { store.requestEdit(repo, kind: .rename) } label: { manageLabel("Rename…", "pencil") }
                Button { store.requestEdit(repo, kind: .description) } label: { manageLabel("Edit Description…", "text.alignleft") }
                Button { store.requestEdit(repo, kind: .transfer) } label: { manageLabel("Transfer to Organization…", "arrow.right.arrow.left") }
                Button { Task { await store.prepare(repo, action: .archive(!repo.archived)) } } label: {
                    manageLabel(repo.archived ? "Unarchive…" : "Archive…", "archivebox")
                }
            }
            .buttonStyle(RowButtonStyle())
            GroupedRows {
                Button { Task { await store.prepare(repo, action: .delete) } } label: { manageLabel("Delete Repository…", "trash") }
                    .buttonStyle(RowButtonStyle(destructive: true))
            }
            .padding(.top, 6)
            Text("Each change opens a review before anything is sent to GitHub. Transfer and deletion ask for the full name.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .disabled(reason != nil)
    }
    private func manageLabel(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).frame(width: 15).accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 0)
        }
    }
    private func manageBlockedReason(_ repo: Repository) -> String? {
        if !repo.canAdminister { return "You need admin access to change this repository." }
        if store.needsRefresh { return "Refresh first so Grove can confirm GitHub's current state." }
        if !store.canStartReview { return "Finish the current task first." }
        return nil
    }
}

struct AssistantView: View {
    @Bindable var store: Store
    @FocusState private var composerFocused: Bool
    private var available: Bool { Intelligence.available }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        targetPicker
                        if !available { unavailableCard }
                        conversation
                        if showPresets { presets }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(16)
                }
                .onChange(of: store.assistantAnswer) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: store.suggestion?.repo.id) { proxy.scrollTo("end", anchor: .bottom) }
            }
            Divider()
            composer.padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.inspector)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(Color.intelligence).accessibilityHidden(true)
            Text("Ask Grove").font(.system(size: 14, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Spacer()
            Button { store.showAssistant = false } label: { Label("Close Assistant", systemImage: "xmark") }
                .buttonStyle(IconButtonStyle(size: 24))
                .help("Close and show details")
        }
        .padding(.horizontal, 16).frame(height: 44)
    }

    // MARK: Target

    private var focus: Binding<AssistantFocus> {
        Binding(get: { store.assistantFocus }, set: { next in
            store.assistantFocus = next
            switch next {
            case .repository: store.assistantOwner = nil
            case .owner: store.assistantOwner = store.owner ?? store.selected?.owner.login ?? store.assistantOwner
            case .library: store.assistantOwner = nil; store.assistantScope = store.owner == nil ? store.scope : .all
            }
        })
    }
    private var targetRepo: Repository? { store.assistantFocus == .repository ? store.selected : nil }
    private var targetReady: Bool {
        switch store.assistantFocus {
        case .repository: store.selected != nil
        case .owner: store.assistantOwner != nil
        case .library: true
        }
    }
    private var targetCount: Int {
        switch store.assistantFocus {
        case .repository: 1
        case .owner: store.assistantOwner.map { store.counts.count(owner: $0) } ?? 0
        case .library: store.counts.count(store.assistantScope)
        }
    }
    private var targetDescription: String {
        switch store.assistantFocus {
        case .repository: store.selected?.full_name ?? "Select a repository in the list."
        case .owner: store.assistantOwner.map { "\($0) · \(countLabel(targetCount, "repository", "repositories"))" } ?? "Choose an owner in the sidebar."
        case .library: "\(store.assistantScope.rawValue) · \(countLabel(targetCount, "repository", "repositories"))"
        }
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("Asking about")
            Picker("Asking about", selection: focus) {
                ForEach(AssistantFocus.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .disabled(store.assistantBusy)
            Text(targetDescription)
                .font(store.assistantFocus == .repository && targetReady ? .system(size: 12, design: .monospaced) : .system(size: 12))
                .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            if store.assistantFocus != .repository && targetCount > 35 {
                Text("Answers consider the 35 most recently pushed.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Apple Intelligence isn't available", systemImage: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.caution)
            Text("Turn it on in System Settings › Apple Intelligence & Siri on a supported Mac. Your library still works without it.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.caution.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: Conversation

    private var showPresets: Bool { available && !store.assistantBusy && store.assistantAnswer.isEmpty && store.suggestion == nil }

    @ViewBuilder private var conversation: some View {
        if let question = store.assistantQuestion {
            VStack(alignment: .trailing, spacing: 3) {
                Text(question).font(.system(size: 12.5)).textSelection(.enabled)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(Color.intelligence.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                if let subject = store.assistantSubject {
                    Text("About \(subject)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 30)
        }
        if store.assistantBusy {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("Thinking on this Mac…").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Stop") { store.assistantTask?.cancel() }.controlSize(.small)
            }
        } else if let error = store.assistantError {
            Label {
                Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(Color.caution) }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.caution.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else if !store.assistantAnswer.isEmpty {
            Text(store.assistantAnswer).font(.system(size: 12.5)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.hairline.opacity(0.6)))
        } else if store.assistantQuestion != nil {
            Text("Stopped before an answer.").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        if let suggestion = store.suggestion, !store.assistantBusy { proposal(suggestion) }
    }

    private func proposal(_ suggestion: AssistantSuggestion) -> some View {
        let deleting = suggestion.action == .delete
        let blocked = !store.canStartReview || store.needsRefresh || !suggestion.repo.canAdminister
        return VStack(alignment: .leading, spacing: 8) {
            Text("Suggested change").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.intelligence)
            Text(suggestion.action.title).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(deleting ? AnyShapeStyle(Color.danger) : AnyShapeStyle(.primary))
            Text(suggestion.repo.full_name).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.middle)
            if let detail = proposalDetail(suggestion) {
                Text(detail).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            HStack(spacing: 8) {
                Button("Dismiss") { store.suggestion = nil }
                Spacer()
                Button("Review Change…") { store.reviewSuggestion() }
                    .buttonStyle(.borderedProminent).tint(deleting ? .danger : .intelligence)
                    .disabled(blocked)
            }
            .controlSize(.small).padding(.top, 2)
            Text(blocked && store.needsRefresh ? "Refresh first so Grove can confirm GitHub's current state."
                 : !suggestion.repo.canAdminister ? "You need admin access to apply this change."
                 : "Nothing changes until you confirm in the review.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.intelligence.opacity(0.45)))
    }
    private func proposalDetail(_ suggestion: AssistantSuggestion) -> String? {
        switch suggestion.action {
        case .rename(let name): "New name: \(name)"
        case .describe(let text): text.isEmpty ? "Remove the description." : "“\(text)”"
        case .transfer(let owner): "To \(owner)/\(suggestion.repo.name)"
        case .archive(let archive): archive ? "Make the repository read-only." : "Make the repository writable again."
        case .delete: "Permanently remove it from GitHub. The review asks for the full name."
        }
    }

    // MARK: Presets and composer

    private var presetList: [AssistantPreset] {
        if store.assistantFocus == .repository, let repo = store.selected { return AssistantPresets.repository(repo, includeDeletion: false) }
        return AssistantPresets.collection
    }
    private var presets: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Suggestions")
            GroupedRows {
                ForEach(presetList) { preset in
                    Button { ask(preset.prompt) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: preset.symbol).frame(width: 15).foregroundStyle(Color.intelligence).accessibilityHidden(true)
                            Text(preset.title)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .buttonStyle(RowButtonStyle())
            .disabled(!canAsk(presetPrompt: true))
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $store.assistantPrompt, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 12.5))
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .disabled(!available || store.assistantBusy)
                    .accessibilityLabel("Question")
                Button { ask(store.assistantPrompt) } label: { Label("Ask", systemImage: "arrow.up") }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent).tint(.intelligence)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Ask (⌘↩)")
                    .disabled(!canAsk(presetPrompt: false))
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(composerFocused ? Color.intelligence.opacity(0.7) : Color.hairline, lineWidth: composerFocused ? 1.5 : 1))
            Text("Runs on this Mac. You approve each question, and a suggested change opens its own review.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var placeholder: String {
        switch store.assistantFocus {
        case .repository: "Ask about this repository"
        case .owner: "Ask about this owner's repositories"
        case .library: "Ask about your library"
        }
    }
    private func canAsk(presetPrompt: Bool) -> Bool {
        available && !store.assistantBusy && store.canStartReview && targetReady && store.inventory != nil &&
            (presetPrompt || !store.assistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    private func ask(_ prompt: String) {
        switch store.assistantFocus {
        case .repository: store.requestAssistant(prompt, repo: store.selected)
        case .owner: store.requestAssistant(prompt, owner: store.assistantOwner)
        case .library: store.requestAssistant(prompt, libraryScope: store.assistantScope)
        }
    }
}
