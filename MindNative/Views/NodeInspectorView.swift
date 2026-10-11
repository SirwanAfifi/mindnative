import AppKit
import SwiftUI

struct NodeInspectorView: View {
    @ObservedObject var viewModel: CanvasViewModel

    private var selectedNode: IdeaNode? {
        guard viewModel.selectedNodeIDs.count == 1,
              let id = viewModel.selectedNodeIDs.first else {
            return nil
        }
        return viewModel.getNode(by: id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Idea Details", systemImage: "info.circle")
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.isInspectorPresented = false
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.plain)
                .help("Hide inspector")
                .accessibilityLabel("Hide inspector")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if let selectedNode {
                NodeInspectorEditor(
                    node: selectedNode,
                    parentOptions: viewModel.nodes.filter { $0.id != selectedNode.id },
                    onSave: { viewModel.updateNode($0) },
                    onReparent: { viewModel.reparentNode(selectedNode.id, to: $0) },
                    onOpenLink: openLink,
                    onAddReminder: {
                        Task { await viewModel.addSelectedIdeaToReminders() }
                    },
                    onAddCalendarEvent: {
                        Task { await viewModel.addSelectedIdeaToCalendar() }
                    },
                    onAIAction: { action in
                        Task { await viewModel.runAIAction(action, nodeID: selectedNode.id) }
                    }
                )
                .id(selectedNode.id)
            } else {
                VStack(spacing: 12) {
                    Image(
                        systemName: viewModel.selectedNodeIDs.isEmpty
                            ? "cursorarrow.click"
                            : "square.stack.3d.up"
                    )
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)

                    Text(
                        viewModel.selectedNodeIDs.isEmpty
                            ? "Select an Idea"
                            : "Multiple Ideas Selected"
                    )
                    .font(.headline)

                    Text(
                        viewModel.selectedNodeIDs.isEmpty
                            ? "Choose one idea to edit its notes, tags, task state, link, icon, and color."
                            : "Select a single idea to edit its details."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 230)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
        .background(.regularMaterial)
        .accessibilityIdentifier("idea-inspector")
        .onAppear {
            viewModel.editingNodeID = nil
        }
    }

    private func openLink(_ text: String) {
        guard let url = URL(string: text), url.scheme != nil else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct NodeInspectorEditor: View {
    let node: IdeaNode
    let parentOptions: [IdeaNode]
    let onSave: (IdeaNode) -> Void
    let onReparent: (UUID?) -> Void
    let onOpenLink: (String) -> Void
    let onAddReminder: () -> Void
    let onAddCalendarEvent: () -> Void
    let onAIAction: (AIMapAction) -> Void

    @State private var draft: IdeaNode
    @State private var tagsText: String
    @State private var selectedParentID: UUID?

    init(
        node: IdeaNode,
        parentOptions: [IdeaNode],
        onSave: @escaping (IdeaNode) -> Void,
        onReparent: @escaping (UUID?) -> Void,
        onOpenLink: @escaping (String) -> Void,
        onAddReminder: @escaping () -> Void,
        onAddCalendarEvent: @escaping () -> Void,
        onAIAction: @escaping (AIMapAction) -> Void
    ) {
        self.node = node
        self.parentOptions = parentOptions
        self.onSave = onSave
        self.onReparent = onReparent
        self.onOpenLink = onOpenLink
        self.onAddReminder = onAddReminder
        self.onAddCalendarEvent = onAddCalendarEvent
        self.onAIAction = onAIAction
        _draft = State(initialValue: node)
        _tagsText = State(initialValue: node.tags.joined(separator: ", "))
        _selectedParentID = State(initialValue: node.parentID)
    }

    private var hasChanges: Bool {
        var candidate = draft
        candidate.parentID = selectedParentID
        candidate.tags = IdeaNode.normalizedTags(tagsText.components(separatedBy: ","))
        return candidate != node
    }

    var body: some View {
        Form {
            Section("Content") {
                TextField("Title", text: $draft.title)
                    .accessibilityIdentifier("inspector-title")

                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(4...10)

                TextField("Tags", text: $tagsText, prompt: Text("research, urgent"))

                TextField("Link", text: Binding(
                    get: { draft.linkURL ?? "" },
                    set: { draft.linkURL = $0.isEmpty ? nil : $0 }
                ))

                if let link = draft.linkURL, URL(string: link)?.scheme != nil {
                    HStack {
                        Button("Open Link") {
                            onOpenLink(link)
                        }

                        Button("Fetch Preview") {
                            fetchLinkPreview(link)
                        }
                    }

                    if let title = draft.linkTitle {
                        LabeledContent("Preview", value: title)
                    }
                    if let summary = draft.linkSummary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Attachments") {
                if draft.attachments.isEmpty {
                    Text("Attach images, PDFs, notes, or supporting files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(draft.attachments) { attachment in
                        HStack {
                            Label(attachment.name, systemImage: attachment.systemImageName)
                                .lineLimit(1)

                            Spacer()

                            Button {
                                try? AttachmentService.open(attachment)
                            } label: {
                                Image(systemName: "arrow.up.forward.app")
                            }
                            .buttonStyle(.plain)
                            .help("Open attachment")

                            Button(role: .destructive) {
                                draft.attachments.removeAll { $0.id == attachment.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .help("Remove attachment")
                        }
                    }
                }

                Button("Attach Files…") {
                    do {
                        draft.attachments.append(
                            contentsOf: try AttachmentService.chooseAttachments()
                        )
                    } catch {
                        Diagnostics.record(
                            error,
                            logger: Diagnostics.integrations,
                            operation: "Attach files from inspector"
                        )
                        NSApp.presentError(error)
                    }
                }
            }

            Section("Appearance") {
                ColorPicker("Branch color", selection: $draft.color)

                Picker("Icon", selection: Binding(
                    get: { draft.iconName ?? "" },
                    set: { draft.iconName = $0.isEmpty ? nil : $0 }
                )) {
                    Label("None", systemImage: "minus").tag("")
                    Label("Idea", systemImage: "lightbulb").tag("lightbulb")
                    Label("Flag", systemImage: "flag").tag("flag")
                    Label("Person", systemImage: "person").tag("person")
                    Label("Calendar", systemImage: "calendar").tag("calendar")
                    Label("Document", systemImage: "doc.text").tag("doc.text")
                    Label("Question", systemImage: "questionmark.circle").tag("questionmark.circle")
                }
            }

            Section("Structure") {
                Picker("Parent", selection: $selectedParentID) {
                    Text("Main idea").tag(UUID?.none)
                    ForEach(parentOptions) { option in
                        Text(option.title.isEmpty ? "Untitled idea" : option.title)
                            .tag(UUID?.some(option.id))
                    }
                }

                Toggle("Task", isOn: $draft.isTask)
                if draft.isTask {
                    Toggle("Completed", isOn: $draft.isCompleted)
                }

                if !draft.isTask {
                    Text("Turn this idea into a checkable action.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Actions") {
                Menu("Analyze with MindNative") {
                    ForEach(AIMapAction.allCases) { action in
                        Button(action.title) {
                            onAIAction(action)
                        }
                    }
                }

                Button("Add to Reminders") {
                    onAddReminder()
                }

                Button("Add to Calendar") {
                    onAddCalendarEvent()
                }
            }

            HStack {
                Button("Revert") {
                    draft = node
                    tagsText = node.tags.joined(separator: ", ")
                    selectedParentID = node.parentID
                }
                .disabled(!hasChanges)

                Spacer()

                Button("Apply") {
                    var updated = draft
                    updated.parentID = node.parentID
                    updated.tags = IdeaNode.normalizedTags(
                        tagsText.components(separatedBy: ",")
                    )
                    if !updated.isTask {
                        updated.isCompleted = false
                    }
                    onSave(updated)
                    if selectedParentID != node.parentID {
                        onReparent(selectedParentID)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges)
                .accessibilityIdentifier("inspector-apply")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func fetchLinkPreview(_ text: String) {
        guard let url = URL(string: text) else { return }
        Task {
            do {
                let preview = try await LinkPreviewService.fetch(for: url)
                draft.linkTitle = preview.title
                draft.linkSummary = preview.summary
            } catch {
                Diagnostics.record(
                    error,
                    logger: Diagnostics.integrations,
                    operation: "Load link preview from inspector"
                )
                NSApp.presentError(error)
            }
        }
    }
}
