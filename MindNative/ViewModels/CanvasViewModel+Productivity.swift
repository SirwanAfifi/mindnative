import AppKit
import Foundation

enum AIMapAction: String, CaseIterable, Identifiable {
    case summarizeBranch
    case findDuplicates
    case suggestConnections
    case notesToTasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summarizeBranch: "Summarize Branch"
        case .findDuplicates: "Find Duplicate Ideas"
        case .suggestConnections: "Suggest Cross-Links"
        case .notesToTasks: "Turn Notes into Tasks"
        }
    }

    var systemImage: String {
        switch self {
        case .summarizeBranch: "text.quote"
        case .findDuplicates: "rectangle.on.rectangle"
        case .suggestConnections: "link.badge.plus"
        case .notesToTasks: "checklist"
        }
    }
}

extension CanvasViewModel {
    var currentPresentationNode: IdeaNode? {
        guard presentationNodeIDs.indices.contains(presentationIndex) else { return nil }
        return getNode(by: presentationNodeIDs[presentationIndex])
    }

    func startPresentation(from nodeID: UUID? = nil) {
        presentationNodeIDs = presentationOrder()
        guard !presentationNodeIDs.isEmpty else { return }
        if let nodeID,
           let index = presentationNodeIDs.firstIndex(of: nodeID) {
            presentationIndex = index
        } else if let selectedNodeID,
                  let index = presentationNodeIDs.firstIndex(of: selectedNodeID) {
            presentationIndex = index
        } else {
            presentationIndex = 0
        }
        isPresentationMode = true
        showCurrentPresentationNode()
    }

    func endPresentation() {
        isPresentationMode = false
        presentationNodeIDs = []
        presentationIndex = 0
    }

    func advancePresentation() {
        guard !presentationNodeIDs.isEmpty else { return }
        presentationIndex = min(presentationIndex + 1, presentationNodeIDs.count - 1)
        showCurrentPresentationNode()
    }

    func retreatPresentation() {
        guard !presentationNodeIDs.isEmpty else { return }
        presentationIndex = max(presentationIndex - 1, 0)
        showCurrentPresentationNode()
    }

    @MainActor
    func addAttachments(to nodeID: UUID) {
        do {
            let attachments = try AttachmentService.chooseAttachments()
            guard !attachments.isEmpty, var node = getNode(by: nodeID) else { return }
            node.attachments.append(contentsOf: attachments)
            updateNode(node, actionName: "Attach Files")
        } catch {
            presentIntegrationError(error, title: "Could not attach files")
        }
    }

    func addAttachments(_ attachments: [IdeaAttachment], to nodeID: UUID) {
        guard !attachments.isEmpty, var node = getNode(by: nodeID) else { return }
        node.attachments.append(contentsOf: attachments)
        updateNode(node, actionName: "Attach Files")
    }

    func removeAttachment(_ attachmentID: UUID, from nodeID: UUID) {
        guard var node = getNode(by: nodeID) else { return }
        node.attachments.removeAll { $0.id == attachmentID }
        updateNode(node, actionName: "Remove Attachment")
    }

    @MainActor
    func openAttachment(_ attachment: IdeaAttachment) {
        do {
            try AttachmentService.open(attachment)
        } catch {
            presentIntegrationError(error, title: "Could not open attachment")
        }
    }

    @MainActor
    func refreshLinkPreview(for nodeID: UUID) async {
        guard var node = getNode(by: nodeID), let url = node.link else { return }
        do {
            let preview = try await LinkPreviewService.fetch(for: url)
            try Task.checkCancellation()
            node.linkTitle = preview.title
            node.linkSummary = preview.summary
            updateNode(node, actionName: "Update Link Preview")
        } catch is CancellationError {
            return
        } catch {
            presentIntegrationError(error, title: "Could not load link preview")
        }
    }

    @MainActor
    func addSelectedIdeaToReminders() async {
        guard let selectedNodeID, let node = getNode(by: selectedNodeID) else { return }
        do {
            try await SystemIntegrationService.addReminder(for: node)
            notice = EditorNotice(
                kind: .success,
                title: "Reminder created",
                message: "“\(node.title)” was added to Reminders."
            )
        } catch {
            presentIntegrationError(error, title: "Could not create reminder")
        }
    }

    @MainActor
    func addSelectedIdeaToCalendar() async {
        guard let selectedNodeID, let node = getNode(by: selectedNodeID) else { return }
        do {
            try await SystemIntegrationService.addCalendarEvent(for: node)
            notice = EditorNotice(
                kind: .success,
                title: "Calendar event created",
                message: "“\(node.title)” was scheduled for tomorrow at 9:00."
            )
        } catch {
            presentIntegrationError(error, title: "Could not create event")
        }
    }

    @MainActor
    func shareMap() {
        do {
            try SystemIntegrationService.shareMap(nodes: nodes, connections: connections)
        } catch {
            presentIntegrationError(error, title: "Could not share map")
        }
    }

    @MainActor
    func printMap() {
        do {
            try SystemIntegrationService.printMap(nodes: nodes, connections: connections)
        } catch {
            presentIntegrationError(error, title: "Could not print map")
        }
    }

    @MainActor
    func runAIAction(_ action: AIMapAction, nodeID: UUID? = nil) async {
        guard !isRunningAIAction else { return }
        isRunningAIAction = true
        defer { isRunningAIAction = false }

        switch action {
        case .summarizeBranch:
            await summarizeBranch(nodeID: nodeID ?? selectedNodeID)
        case .findDuplicates:
            findDuplicateIdeas()
        case .suggestConnections:
            suggestCrossLinks()
        case .notesToTasks:
            turnNotesIntoTasks(nodeID: nodeID ?? selectedNodeID)
        }
    }

    private func presentationOrder() -> [UUID] {
        var result: [UUID] = []
        var visited = Set<UUID>()

        func append(_ node: IdeaNode) {
            guard visited.insert(node.id).inserted else { return }
            result.append(node.id)
            for child in children(of: node.id) {
                append(child)
            }
        }

        for root in nodes where root.parentID == nil {
            append(root)
        }
        return result
    }

    private func showCurrentPresentationNode() {
        guard let node = currentPresentationNode else { return }
        selectedNodeIDs = [node.id]
        focusedNodeID = node.id
        editingNodeID = nil
        canvasOffset = CGSize(
            width: viewportSize.width / 2 - node.position.x * zoomScale,
            height: viewportSize.height / 2 - node.position.y * zoomScale
        )
    }

    @MainActor
    private func summarizeBranch(nodeID: UUID?) async {
        guard let nodeID, var node = getNode(by: nodeID) else {
            notice = EditorNotice(
                kind: .warning,
                title: "Select a branch",
                message: "Choose an idea before creating a summary."
            )
            return
        }

        let branch = branchNodes(startingAt: nodeID)
        let outline = branch.dropFirst().map(\.title).filter { !$0.isEmpty }
        let summary: String
        do {
            summary = try await AIService().summarizeBranch(
                title: node.title,
                outline: Array(outline)
            )
        } catch {
            let visibleTitles = outline.prefix(6).joined(separator: ", ")
            summary = visibleTitles.isEmpty
                ? "This branch currently contains only “\(node.title)”."
                : "This branch develops \(node.title) through \(visibleTitles)."
        }

        let prefix = node.notes.isEmpty ? "" : "\(node.notes)\n\n"
        node.notes = "\(prefix)Summary: \(summary)"
        updateNode(node, actionName: "Summarize Branch")
        notice = EditorNotice(
            kind: .success,
            title: "Branch summarized",
            message: "The summary was added to the idea’s notes."
        )
    }

    private func findDuplicateIdeas() {
        var duplicateIDs = Set<UUID>()
        for (index, lhs) in nodes.enumerated() {
            for rhs in nodes.dropFirst(index + 1) {
                let lhsWords = normalizedWords(lhs.title)
                let rhsWords = normalizedWords(rhs.title)
                guard !lhsWords.isEmpty, similarity(lhsWords, rhsWords) >= 0.8 else {
                    continue
                }
                duplicateIDs.insert(lhs.id)
                duplicateIDs.insert(rhs.id)
            }
        }

        selectedNodeIDs = duplicateIDs
        notice = EditorNotice(
            kind: duplicateIDs.isEmpty ? .success : .warning,
            title: duplicateIDs.isEmpty ? "No duplicates found" : "Possible duplicates selected",
            message: duplicateIDs.isEmpty
                ? "Idea titles are distinct."
                : "Review the \(duplicateIDs.count) selected ideas and merge or rename them."
        )
    }

    private func suggestCrossLinks() {
        let beforeNodes = nodes
        let beforeConnections = connections
        var candidates: [(Double, IdeaNode, IdeaNode)] = []

        for (index, lhs) in nodes.enumerated() {
            for rhs in nodes.dropFirst(index + 1) {
                guard lhs.parentID != rhs.id,
                      rhs.parentID != lhs.id,
                      !connections.contains(where: {
                          Set([$0.fromNodeID, $0.toNodeID]) == Set([lhs.id, rhs.id])
                      }) else {
                    continue
                }
                let score = similarity(normalizedWords(lhs.searchableText), normalizedWords(rhs.searchableText))
                if score >= 0.22 {
                    candidates.append((score, lhs, rhs))
                }
            }
        }

        let suggestions = candidates.sorted { $0.0 > $1.0 }.prefix(3)
        for (_, lhs, rhs) in suggestions {
            connections.append(
                Connection(
                    from: lhs.id,
                    to: rhs.id,
                    color: lhs.color,
                    kind: .association
                )
            )
        }

        guard !suggestions.isEmpty else {
            notice = EditorNotice(
                kind: .info,
                title: "No strong links found",
                message: "Add more notes or shared tags and try again."
            )
            return
        }
        registerChange(
            "Suggest Cross-Links",
            fromNodes: beforeNodes,
            fromConnections: beforeConnections
        )
        notice = EditorNotice(
            kind: .success,
            title: "Cross-links added",
            message: "MindNative added \(suggestions.count) relationships based on shared content."
        )
    }

    private func turnNotesIntoTasks(nodeID: UUID?) {
        let beforeNodes = nodes
        let beforeConnections = connections
        let allowedIDs = nodeID.map { Set(branchNodes(startingAt: $0).map(\.id)) }
        var changed = 0

        for index in nodes.indices where
            (allowedIDs?.contains(nodes[index].id) ?? true) &&
            !nodes[index].notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !nodes[index].isTask {
            nodes[index].isTask = true
            nodes[index].isCompleted = false
            changed += 1
        }

        guard changed > 0 else {
            notice = EditorNotice(
                kind: .info,
                title: "No tasks created",
                message: "Add notes to non-task ideas and try again."
            )
            return
        }
        registerChange(
            "Turn Notes into Tasks",
            fromNodes: beforeNodes,
            fromConnections: beforeConnections
        )
        notice = EditorNotice(
            kind: .success,
            title: "Tasks created",
            message: "\(changed) ideas with notes are now checkable tasks."
        )
    }

    private func branchNodes(startingAt nodeID: UUID) -> [IdeaNode] {
        guard let root = getNode(by: nodeID) else { return [] }
        var result: [IdeaNode] = []
        var pending = [root]
        while let node = pending.popLast() {
            result.append(node)
            pending.append(contentsOf: children(of: node.id).reversed())
        }
        return result
    }

    private func normalizedWords(_ value: String) -> Set<String> {
        Set(
            value.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
        )
    }

    private func similarity(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(lhs.union(rhs).count)
    }

    private func presentIntegrationError(_ error: Error, title: String) {
        Diagnostics.record(
            error,
            logger: Diagnostics.integrations,
            operation: title
        )
        notice = EditorNotice(
            kind: .error,
            title: title,
            message: error.localizedDescription
        )
    }
}

private extension IdeaNode {
    var searchableText: String {
        ([title, notes, linkTitle, linkSummary, linkURL].compactMap(\.self) + tags)
            .joined(separator: " ")
    }
}
