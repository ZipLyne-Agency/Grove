import SwiftUI
import GroveCore

/// Ask Grove: on-device answers about a repository, owner, library scope, or project, with their sources.
struct AssistantView: View {
    @Bindable var store: Store
    @FocusState private var composerFocused: Bool
    private var available: Bool { Intelligence.available }
    private var project: GroveProject? { store.workspace.projects.first { $0.id == store.assistantProjectID } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        targetPicker
                        if !available { unavailable }
                        conversation
                        if showPresets { presets }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(16)
                }
                .scrollIndicators(.never)
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
            GroveMark(size: 18, thinking: store.assistantBusy, available: available)
            Text("Ask Grove").font(.system(size: 14, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Spacer()
            Button { store.showAssistant = false } label: { Label("Close Ask Grove", systemImage: "xmark") }
                .buttonStyle(IconButtonStyle(size: 24))
                .help("Close Ask Grove (⇧⌘A)")
        }
        .padding(.horizontal, 16).frame(height: 44)
    }

    // MARK: Target

    private var focus: Binding<AssistantFocus> {
        Binding(get: { store.assistantFocus }, set: { next in
            store.assistantProjectID = nil
            store.assistantFocus = next
            switch next {
            case .repository: store.assistantOwner = nil
            case .owner: store.assistantOwner = store.owner ?? store.selected?.owner.login ?? store.assistantOwner
            case .library: store.assistantOwner = nil; store.assistantScope = store.owner == nil ? store.scope : .all
            }
        })
    }
    private var targetReady: Bool {
        if project != nil { return true }
        switch store.assistantFocus {
        case .repository: return store.selected != nil
        case .owner: return store.assistantOwner != nil
        case .library: return true
        }
    }
    private var targetCount: Int {
        if let project { return project.repositoryIDs.count }
        switch store.assistantFocus {
        case .repository: return 1
        case .owner: return store.assistantOwner.map { store.counts.count(owner: $0) } ?? 0
        case .library: return store.counts.count(store.assistantScope)
        }
    }
    private var targetDescription: String {
        if let project {
            return "Project \(project.name) · \(countLabel(project.repositoryIDs.count, "repository", "repositories")) · \(countLabel(store.workspace.connections(for: project).count, "service", "services"))"
        }
        switch store.assistantFocus {
        case .repository: return store.selected?.full_name ?? "Select a repository in the list."
        case .owner: return store.assistantOwner.map { "\($0) · \(countLabel(targetCount, "repository", "repositories"))" } ?? "Choose an owner in the sidebar."
        case .library: return "\(store.assistantScope.title) · \(countLabel(targetCount, "repository", "repositories"))"
        }
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("Asking About")
            Picker("Asking About", selection: focus) {
                ForEach(AssistantFocus.allCases, id: \.self) { item in
                    Text(item == .library && project != nil ? "Project" : item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented).labelsHidden()
            .disabled(store.assistantBusy)
            HStack(spacing: 6) {
                if let project { ProjectTile(project: project, size: 14) }
                Text(targetDescription)
                    .font(store.assistantFocus == .repository && project == nil && targetReady ? .system(size: 12, design: .monospaced) : .system(size: 12))
                    .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            }
            if project == nil && store.assistantFocus != .repository && targetCount > 35 {
                Text("Answers consider the 35 most recently pushed.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var unavailable: some View {
        VStack(alignment: .center, spacing: 8) {
            GroveMark(size: 32, available: false)
            Text("Apple Intelligence Isn't Available").font(.system(size: 13, weight: .semibold))
            Text("Ask Grove runs on this Mac with Apple Intelligence. Turn it on in System Settings on a supported Mac. Projects, services, and repositories all work without it.")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 18).padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }

    // MARK: Conversation

    private var showPresets: Bool { available && !store.assistantBusy && store.assistantAnswer.isEmpty && store.suggestion == nil && store.assistantError == nil }

    @ViewBuilder private var conversation: some View {
        if let question = store.assistantQuestion {
            VStack(alignment: .trailing, spacing: 3) {
                Text(question).font(.system(size: 12.5)).textSelection(.enabled)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(Color.ember.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                if let subject = store.assistantSubject {
                    Text("About \(subject)").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 30)
        }
        if store.assistantBusy {
            HStack(spacing: 9) {
                GroveMark(size: 18, thinking: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Thinking on This Mac…").font(.system(size: 12, weight: .semibold))
                    if !store.assistantServices.isEmpty {
                        Text("Reading \(countLabel(store.assistantServices.count, "service record", "service records"))").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Stop") { store.assistantTask?.cancel() }.controlSize(.small)
            }
        } else if let error = store.assistantError {
            VStack(alignment: .leading, spacing: 5) {
                Label("Grove Could Not Answer", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.caution)
                Text(error).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text("Nothing was changed.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.caution.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else if !store.assistantAnswer.isEmpty {
            Text(store.assistantAnswer).font(.system(size: 12.5)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if store.assistantQuestion != nil {
            Text("Stopped Before an Answer.").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        if !store.assistantBusy {
            if !store.assistantOpenServices.isEmpty { openServices }
            if let suggestion = store.suggestion { AssistantProposal(store: store, suggestion: suggestion) }
            if store.assistantQuestion != nil && !store.assistantServices.isEmpty { sources }
        }
    }

    private var openServices: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.assistantOpenServices) { connection in
                Button { store.workspace.open(connection) } label: {
                    HStack(spacing: 9) {
                        ProviderTile(provider: connection.provider, size: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Open \(connection.provider.title) · \(connection.name)").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text(connection.dashboardURL).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.right").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    .padding(.horizontal, 10).frame(minHeight: 40)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.hairline))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!connection.canOpen)
                .help(connection.dashboardURL)
            }
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader("Sources")
                Spacer()
                Text("Captured When Asked").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            TableBox {
                ForEach(store.assistantServices) { connection in
                    HStack(spacing: 8) {
                        ProviderTile(provider: connection.provider, size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(connection.provider.title) · \(connection.name)").font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                            Text(connection.dashboardURL)
                                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9).frame(minHeight: 34)
                }
            }
        }
    }

    // MARK: Presets and composer

    private var presetList: [AssistantPreset] {
        if project != nil { return AssistantPresets.project }
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
                            Image(systemName: preset.symbol).frame(width: 15).foregroundStyle(Color.ember).accessibilityHidden(true)
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
                    .buttonStyle(.borderedProminent).tint(.ember)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Ask (⌘↩)")
                    .disabled(!canAsk(presetPrompt: false))
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(composerFocused ? Color.ember.opacity(0.75) : Color.hairline, lineWidth: composerFocused ? 1.5 : 1))
            .opacity(available ? 1 : 0.45)
            Text("Runs on this Mac. Grove opens only dashboards you saved, and any change opens a review first.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var placeholder: String {
        if project != nil { return "Ask About This Project" }
        switch store.assistantFocus {
        case .repository: return "Ask About This Repository"
        case .owner: return "Ask About This Owner's Repositories"
        case .library: return "Ask About Your Library"
        }
    }
    private func canAsk(presetPrompt: Bool) -> Bool {
        available && !store.assistantBusy && store.canStartReview && targetReady && store.inventory != nil &&
            (presetPrompt || !store.assistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    private func ask(_ prompt: String) {
        if let project { store.requestProjectAssistant(prompt, project: project); return }
        switch store.assistantFocus {
        case .repository: store.requestAssistant(prompt, repo: store.selected)
        case .owner: store.requestAssistant(prompt, owner: store.assistantOwner)
        case .library: store.requestAssistant(prompt, libraryScope: store.assistantScope)
        }
    }
}

/// A repository change the assistant suggested. It never runs from here; it opens the normal review.
struct AssistantProposal: View {
    let store: Store
    let suggestion: AssistantSuggestion
    var body: some View {
        let deleting = suggestion.action == .delete
        let blocked = !store.canStartReview || store.needsRefresh || !suggestion.repo.canAdminister
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested Change").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ember)
            Text(suggestion.action.displayTitle).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(deleting ? AnyShapeStyle(Color.danger) : AnyShapeStyle(.primary))
            Text(suggestion.repo.full_name).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.middle)
            Text(detail).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            HStack(spacing: 8) {
                Button("Dismiss") { store.suggestion = nil }
                Spacer()
                Button("Review Change…") { store.reviewSuggestion() }
                    .buttonStyle(.borderedProminent).tint(deleting ? .danger : .grove)
                    .disabled(blocked)
            }
            .controlSize(.small).padding(.top, 2)
            Text(store.needsRefresh ? "Changes are paused while Grove confirms GitHub's current state."
                 : !suggestion.repo.canAdminister ? "You need admin access to apply this change."
                 : "Nothing changes until you confirm in the review.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.ember.opacity(0.55)))
    }
    private var detail: String {
        switch suggestion.action {
        case .rename(let name): "New name: \(name)"
        case .describe(let text): text.isEmpty ? "Remove the description." : "“\(text)”"
        case .transfer(let owner): "To \(owner)/\(suggestion.repo.name)"
        case .archive(let archive): archive ? "Make the repository read-only." : "Make the repository writable again."
        case .delete: "Permanently remove it from GitHub. The review asks for the full name."
        }
    }
}
