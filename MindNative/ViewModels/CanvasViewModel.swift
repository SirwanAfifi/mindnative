import SwiftUI
import Foundation
import FoundationModels

final class CanvasViewModel: ObservableObject {
    @Published var nodes: [IdeaNode] {
        didSet {
            mutationRevision &+= 1
            rebuildNodeIndexes()
        }
    }
    @Published var connections: [Connection] {
        didSet {
            mutationRevision &+= 1
        }
    }
    @Published var dragOffsets: [UUID: CGSize] = [:]
    @Published var editingNodeID: UUID? = nil
    @Published var selectedNodeIDs: Set<UUID> = []
    @Published var selectionRect: CGRect? = nil
    @Published var focusedNodeID: UUID? = nil // Separate from selection for keyboard navigation

    var selectedNodeID: UUID? {
        selectedNodeIDs.count == 1 ? selectedNodeIDs.first : nil
    }
    @Published var zoomScale: CGFloat = 1.0
    @Published var canvasOffset: CGSize = .zero
    @Published var isGeneratingIdeas: Bool = false
    @Published var generationPrompt: String = ""
    @Published var generationParentNodeID: UUID? = nil
    @Published var isAutoLayoutEnabled: Bool = true
    @Published var viewportSize: CGSize = .zero
    @Published var isKeyboardHelpPresented: Bool = false
    @Published var isNavigatorPresented: Bool = false
    @Published var isInspectorPresented: Bool = false
    @Published var focusedBranchRootID: UUID?
    @Published var connectionSourceNodeID: UUID?
    @Published var notice: EditorNotice?
    @Published var aiGenerationPhase: AIGenerationPhase = .idle
    @Published var layoutStyle: MindMapLayout {
        didSet {
            UserDefaults.standard.set(layoutStyle.rawValue, forKey: "preferredMapLayout")
        }
    }
    @Published var isPresentationMode = false
    @Published var presentationNodeIDs: [UUID] = []
    @Published var presentationIndex = 0
    @Published var isRunningAIAction = false

    private let colors: [Color] = ColorTheme.nodePalette
    var undoService: UndoService?

    private var nodeIndexByID: [UUID: Int] = [:]
    private var childIDsByParentID: [UUID: [UUID]] = [:]
    private var mutationRevision: UInt = 0
    private var layoutTask: Task<Void, Never>?
    private var layoutGeneration = UUID()
    private let pasteboard: NSPasteboard
    private var spatialIndex = CanvasSpatialIndex()

    private var visibleCanvasCenter: CGPoint {
        let width = viewportSize.width > 0 ? viewportSize.width : 800
        let height = viewportSize.height > 0 ? viewportSize.height : 600
        return CGPoint(
            x: max(240, (width / 2 - canvasOffset.width) / zoomScale),
            y: max(180, (height / 2 - canvasOffset.height) / zoomScale)
        )
    }

    init(
        nodes: [IdeaNode] = [],
        connections: [Connection] = [],
        pasteboard: NSPasteboard = .general
    ) {
        self.nodes = nodes
        self.connections = connections
        self.pasteboard = pasteboard
        self.layoutStyle = MindMapLayout(
            rawValue: UserDefaults.standard.string(forKey: "preferredMapLayout") ?? ""
        ) ?? .horizontal
        rebuildNodeIndexes()
    }

    deinit {
        layoutTask?.cancel()
    }

    // MARK: - Visual hierarchy

    /// Generations between this node and its root. Roots are depth 0.
    ///
    /// The walk is bounded by the node count so a corrupted document with a
    /// parent cycle degrades to a wrong-looking depth instead of hanging.
    func depth(of nodeID: UUID) -> Int {
        var depth = 0
        var currentID: UUID? = nodeID
        var guardCount = 0

        while let id = currentID,
              let node = getNode(by: id),
              let parentID = node.parentID,
              guardCount < nodes.count {
            depth += 1
            guardCount += 1
            currentID = parentID
        }
        return depth
    }

    func elevation(of nodeID: UUID) -> NodeElevation {
        NodeElevation(depth: depth(of: nodeID))
    }

    var visibleNodes: [IdeaNode] {
        let visibleIDs = visibleNodeIDs()
        return nodes.filter { visibleIDs.contains($0.id) }
    }

    var visibleConnections: [Connection] {
        let visibleIDs = visibleNodeIDs()
        return connections.filter {
            visibleIDs.contains($0.fromNodeID) && visibleIDs.contains($0.toNodeID)
        }
    }

    var canPasteIdeas: Bool {
        CanvasClipboard.containsIdeas(in: pasteboard)
    }

    func renderedNodes(in canvasRect: CGRect) -> [IdeaNode] {
        let visible = visibleNodeIDs()
        guard visible.count > 250 else {
            return nodes.filter { visible.contains($0.id) }
        }

        var renderIDs = spatialIndex.identifiers(in: canvasRect)
        renderIDs.formUnion(selectedNodeIDs)
        if let focusedNodeID { renderIDs.insert(focusedNodeID) }
        return nodes.filter { visible.contains($0.id) && renderIDs.contains($0.id) }
    }

    func renderedConnections(in canvasRect: CGRect) -> [Connection] {
        let renderedIDs = Set(renderedNodes(in: canvasRect).map(\.id))
        let visible = visibleNodeIDs()
        return connections.filter {
            visible.contains($0.fromNodeID) &&
            visible.contains($0.toNodeID) &&
            (renderedIDs.contains($0.fromNodeID) || renderedIDs.contains($0.toNodeID))
        }
    }

    func children(of nodeID: UUID) -> [IdeaNode] {
        (childIDsByParentID[nodeID] ?? []).compactMap(getNode)
    }

    func searchResults(for query: String) -> [IdeaNode] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return visibleNodes }

        return nodes.filter { node in
            node.title.localizedStandardContains(cleanQuery) ||
            node.notes.localizedStandardContains(cleanQuery) ||
            node.tags.contains { $0.localizedStandardContains(cleanQuery) } ||
            (node.linkURL?.localizedStandardContains(cleanQuery) ?? false)
        }
    }

    private func visibleNodeIDs() -> Set<UUID> {
        var result: Set<UUID>
        if let focusedBranchRootID, nodeIndexByID[focusedBranchRootID] != nil {
            result = descendantIDs(
                of: [focusedBranchRootID],
                includingRoots: true
            )
        } else {
            result = Set(nodes.map(\.id))
        }

        for node in nodes where node.isCollapsed && result.contains(node.id) {
            result.subtract(
                descendantIDs(of: [node.id], includingRoots: false)
            )
        }
        return result
    }

    /// The hue a new child should take.
    ///
    /// Children inherit their parent's color so each branch reads as one family
    /// and the map shows structure rather than confetti. Only roots introduce a
    /// new hue, cycling the palette so consecutive roots stay distinguishable.
    private func branchColor(forChildOf parentID: UUID) -> Color {
        getNode(by: parentID)?.color ?? colors.first ?? .blue
    }

    private func nextRootColor() -> Color {
        guard !colors.isEmpty else { return .blue }
        let rootCount = nodes.filter { $0.parentID == nil }.count
        return colors[rootCount % colors.count]
    }

    // MARK: - Helper Methods

    func registerChange(
        _ actionName: String,
        fromNodes: [IdeaNode],
        fromConnections: [Connection]
    ) {
        undoService?.registerCanvasChange(
            actionName: actionName,
            fromNodes: fromNodes,
            fromConnections: fromConnections,
            toNodes: nodes,
            toConnections: connections,
            viewModel: self
        )
    }

    private func rebuildNodeIndexes() {
        var newNodeIndexByID: [UUID: Int] = [:]
        var newChildIDsByParentID: [UUID: [UUID]] = [:]
        newNodeIndexByID.reserveCapacity(nodes.count)
        newChildIDsByParentID.reserveCapacity(nodes.count)

        for (index, node) in nodes.enumerated() {
            newNodeIndexByID[node.id] = index
            if let parentID = node.parentID {
                newChildIDsByParentID[parentID, default: []].append(node.id)
            }
        }

        nodeIndexByID = newNodeIndexByID
        childIDsByParentID = newChildIDsByParentID
        spatialIndex.rebuild(nodes: nodes)
    }

    private func descendantIDs(of rootIDs: Set<UUID>, includingRoots: Bool) -> Set<UUID> {
        var result = includingRoots ? rootIDs : []
        var visited = Set<UUID>()
        var pending = Array(rootIDs)

        while let nodeID = pending.popLast() {
            guard visited.insert(nodeID).inserted else { continue }
            for childID in childIDsByParentID[nodeID] ?? [] {
                result.insert(childID)
                pending.append(childID)
            }
        }

        return result
    }

    private func removeNodes(withIDs nodeIDs: Set<UUID>) {
        guard !nodeIDs.isEmpty else { return }

        nodes.removeAll { nodeIDs.contains($0.id) }
        connections.removeAll {
            nodeIDs.contains($0.fromNodeID) || nodeIDs.contains($0.toNodeID)
        }
        selectedNodeIDs.subtract(nodeIDs)

        if let editingNodeID, nodeIDs.contains(editingNodeID) {
            self.editingNodeID = nil
        }
        if let focusedNodeID, nodeIDs.contains(focusedNodeID) {
            self.focusedNodeID = nodes.first?.id
        }

        if !dragOffsets.isEmpty {
            var updatedOffsets = dragOffsets
            for nodeID in nodeIDs {
                updatedOffsets.removeValue(forKey: nodeID)
            }
            dragOffsets = updatedOffsets
        }
    }

    func restoreCanvas(nodes: [IdeaNode], connections: [Connection]) {
        self.nodes = nodes
        self.connections = connections
        selectedNodeIDs.formIntersection(nodeIndexByID.keys)
        if let focusedNodeID, nodeIndexByID[focusedNodeID] == nil {
            self.focusedNodeID = nodes.first?.id
        }
        editingNodeID = nil
        dragOffsets.removeAll()
    }

    private func calculateChildPosition(
        parent: IdeaNode,
        index: Int,
        totalChildren: Int
    ) -> CGPoint {
        let baseVerticalOffset: CGFloat = -CGFloat(totalChildren - 1) * (LayoutConstants.verticalSpacing / 2)
        return CGPoint(
            x: parent.position.x + LayoutConstants.horizontalOffset,
            y: parent.position.y + baseVerticalOffset + CGFloat(index) * LayoutConstants.verticalSpacing
        )
    }

    private func calculateCircularPosition(
        center: CGPoint,
        index: Int,
        total: Int,
        radius: CGFloat = LayoutConstants.circularRadius
    ) -> CGPoint {
        let angle = (Double(index) / Double(total)) * 2 * Double.pi
        return CGPoint(
            x: center.x + CGFloat(Foundation.cos(angle)) * radius,
            y: center.y + CGFloat(Foundation.sin(angle)) * radius
        )
    }

    private func createChildNode(
        title: String,
        position: CGPoint,
        parentID: UUID
    ) {
        let inherited = branchColor(forChildOf: parentID)
        let childNode = IdeaNode(
            title: title,
            position: position,
            color: inherited,
            parentID: parentID
        )
        nodes.append(childNode)
        connections.append(Connection(
            from: parentID,
            to: childNode.id,
            color: inherited
        ))
    }

    func addChildNode(to parent: IdeaNode) {
        let beforeNodes = nodes
        let beforeConnections = connections

        let existingChildIDs = childIDsByParentID[parent.id] ?? []
        let inherited = parent.color
        let child = IdeaNode(title: "", position: .zero, color: inherited, parentID: parent.id)

        nodes.append(child)
        connections.append(Connection(from: parent.id, to: child.id, color: inherited))

        // Re-centre the whole sibling column on the parent. Placing only the new
        // child left the stack drifting downward: the old offset combined to
        // count * (spacing / 2), which is half the intended gap, so cards
        // overlapped and the column never stayed centred.
        layOutChildren(of: parent.id, childIDs: existingChildIDs + [child.id])
        editingNodeID = child.id
        selectedNodeIDs = [child.id]
        focusedNodeID = child.id
        registerChange("Add Connected Idea", fromNodes: beforeNodes, fromConnections: beforeConnections)
    }

    func move(nodeID: UUID, to position: CGPoint) {
        guard let index = nodeIndexByID[nodeID] else { return }

        // Calculate the offset
        let oldPosition = nodes[index].position
        let offset = CGSize(
            width: position.x - oldPosition.x,
            height: position.y - oldPosition.y
        )

        let nodesToMove = descendantIDs(of: [nodeID], includingRoots: true)
        var updatedNodes = nodes
        for movedNodeID in nodesToMove {
            guard let movedIndex = nodeIndexByID[movedNodeID] else { continue }
            if movedNodeID == nodeID {
                updatedNodes[movedIndex].position = position
            } else {
                updatedNodes[movedIndex].position = CGPoint(
                    x: updatedNodes[movedIndex].position.x + offset.width,
                    y: updatedNodes[movedIndex].position.y + offset.height
                )
            }
        }
        nodes = updatedNodes
    }

    func addRootNode(title: String = "", at position: CGPoint? = nil, image: NSImage? = nil) {
        let beforeNodes = nodes
        let beforeConnections = connections
        let newPosition = freePosition(near: position ?? visibleCanvasCenter)
        let rootColor = nextRootColor()
        let newNode = IdeaNode(
            title: title,
            position: newPosition,
            color: rootColor,
            parentID: nil,
            image: image
        )
        nodes.append(newNode)
        editingNodeID = image == nil && title.isEmpty ? newNode.id : nil
        selectedNodeIDs = [newNode.id]
        focusedNodeID = newNode.id
        registerChange("Add Main Idea", fromNodes: beforeNodes, fromConnections: beforeConnections)
    }

    /// Stacks `childIDs` in a column to the right of their parent, centred on it.
    ///
    /// Each child keeps its own subtree: moving a child by some delta moves
    /// everything beneath it by the same amount, so re-centring a column never
    /// tears a branch apart.
    private func layOutChildren(of parentID: UUID, childIDs: [UUID]) {
        guard let parent = getNode(by: parentID), !childIDs.isEmpty else { return }

        let spacing = LayoutConstants.verticalSpacing
        let columnHeight = CGFloat(childIDs.count - 1) * spacing
        let startY = parent.position.y - columnHeight / 2
        let x = parent.position.x + LayoutConstants.horizontalOffset

        var updatedNodes = nodes
        for (index, childID) in childIDs.enumerated() {
            guard let childIndex = nodeIndexByID[childID] else { continue }
            let target = CGPoint(x: x, y: startY + CGFloat(index) * spacing)
            let current = updatedNodes[childIndex].position
            let delta = CGSize(
                width: target.x - current.x,
                height: target.y - current.y
            )

            updatedNodes[childIndex].position = target

            // Carry the child's descendants along with it.
            for descendantID in descendantIDs(of: [childID], includingRoots: false) {
                guard let descendantIndex = nodeIndexByID[descendantID] else { continue }
                updatedNodes[descendantIndex].position = CGPoint(
                    x: updatedNodes[descendantIndex].position.x + delta.width,
                    y: updatedNodes[descendantIndex].position.y + delta.height
                )
            }
        }
        nodes = updatedNodes
    }

    /// Finds an empty spot at or below `target`.
    ///
    /// New roots used to be dropped at a fixed point regardless of what was
    /// already there, so repeatedly adding a main idea stacked every one of them
    /// on the same pixel. Stepping straight down keeps the result predictable —
    /// a new root appears under the last one rather than somewhere arbitrary.
    private func freePosition(near target: CGPoint) -> CGPoint {
        let step = LayoutConstants.verticalSpacing
        let clearance = LayoutConstants.minNodeDistance
        var candidate = target

        for _ in 0..<200 {
            let collides = nodes.contains { node in
                abs(node.position.x - candidate.x) < clearance &&
                abs(node.position.y - candidate.y) < step
            }
            if !collides { return candidate }
            candidate.y += step
        }
        return candidate
    }

    func getNode(by id: UUID) -> IdeaNode? {
        guard let index = nodeIndexByID[id] else { return nil }
        return nodes[index]
    }

    func updateDragOffset(for nodeID: UUID, offset: CGSize) {
        dragOffsets[nodeID] = offset
    }

    func updateDragOffsets(_ nodeIDs: Set<UUID>, offset: CGSize) {
        var updatedOffsets = dragOffsets
        for nodeID in nodeIDs {
            updatedOffsets[nodeID] = offset
        }
        dragOffsets = updatedOffsets
    }

    func clearDragOffset(for nodeID: UUID) {
        dragOffsets.removeValue(forKey: nodeID)
    }

    func clearDragOffsets(_ nodeIDs: Set<UUID>) {
        var updatedOffsets = dragOffsets
        for nodeID in nodeIDs {
            updatedOffsets.removeValue(forKey: nodeID)
        }
        dragOffsets = updatedOffsets
    }

    func getRealTimePosition(for nodeID: UUID, basePosition: CGPoint) -> CGPoint {
        guard let offset = dragOffsets[nodeID] else {
            return basePosition
        }
        return CGPoint(
            x: basePosition.x + offset.width,
            y: basePosition.y + offset.height
        )
    }

    func updateNodeTitle(nodeID: UUID, newTitle: String) {
        guard let index = nodeIndexByID[nodeID] else { return }
        guard nodes[index].title != newTitle else { return }
        let beforeNodes = nodes
        let beforeConnections = connections
        nodes[index].title = newTitle
        registerChange("Rename Idea", fromNodes: beforeNodes, fromConnections: beforeConnections)
    }

    func updateNode(_ updatedNode: IdeaNode, actionName: String = "Edit Idea") {
        guard let index = nodeIndexByID[updatedNode.id],
              nodes[index] != updatedNode else {
            return
        }
        let beforeNodes = nodes
        let beforeConnections = connections
        nodes[index] = updatedNode

        if let parentID = updatedNode.parentID,
           let connectionIndex = connections.firstIndex(where: {
               $0.kind == .hierarchy &&
               $0.fromNodeID == parentID &&
               $0.toNodeID == updatedNode.id
           }) {
            connections[connectionIndex].color = updatedNode.color
        }

        registerChange(
            actionName,
            fromNodes: beforeNodes,
            fromConnections: beforeConnections
        )
    }

    func toggleTaskCompletion(nodeID: UUID) {
        guard var node = getNode(by: nodeID), node.isTask else { return }
        node.isCompleted.toggle()
        updateNode(node, actionName: node.isCompleted ? "Complete Idea" : "Reopen Idea")
    }

    func toggleCollapsed(nodeID: UUID) {
        guard var node = getNode(by: nodeID), !children(of: nodeID).isEmpty else {
            return
        }
        node.isCollapsed.toggle()
        updateNode(node, actionName: node.isCollapsed ? "Collapse Branch" : "Expand Branch")
    }

    func focusOnBranch(_ nodeID: UUID) {
        guard nodeIndexByID[nodeID] != nil else { return }
        focusedBranchRootID = nodeID
        selectedNodeIDs = [nodeID]
        focusedNodeID = nodeID
        fitToContent()
    }

    func clearBranchFocus() {
        focusedBranchRootID = nil
        fitToContent()
    }

    func promoteToRoot(_ nodeID: UUID) {
        reparentNode(nodeID, to: nil)
    }

    func reparentNode(_ nodeID: UUID, to newParentID: UUID?) {
        guard let index = nodeIndexByID[nodeID] else { return }
        if let newParentID {
            guard nodeIndexByID[newParentID] != nil,
                  nodeID != newParentID,
                  !descendantIDs(of: [nodeID], includingRoots: false).contains(newParentID) else {
                notice = EditorNotice(
                    kind: .error,
                    title: "Cannot move branch",
                    message: "An idea cannot be moved beneath itself or one of its descendants."
                )
                return
            }
        }
        guard nodes[index].parentID != newParentID else { return }

        let beforeNodes = nodes
        let beforeConnections = connections
        nodes[index].parentID = newParentID
        connections.removeAll {
            $0.kind == .hierarchy && $0.toNodeID == nodeID
        }

        if let newParentID, let parent = getNode(by: newParentID) {
            nodes[index].color = parent.color
            connections.append(
                Connection(
                    from: newParentID,
                    to: nodeID,
                    color: parent.color
                )
            )
            let siblingIDs = childIDsByParentID[newParentID] ?? []
            layOutChildren(of: newParentID, childIDs: siblingIDs)
        }

        registerChange(
            newParentID == nil ? "Promote Idea" : "Move Branch",
            fromNodes: beforeNodes,
            fromConnections: beforeConnections
        )
    }

    func moveSibling(_ nodeID: UUID, by offset: Int) {
        guard offset != 0,
              let node = getNode(by: nodeID),
              let nodeIndex = nodeIndexByID[nodeID] else {
            return
        }

        let siblingIDs: [UUID]
        if let parentID = node.parentID {
            siblingIDs = childIDsByParentID[parentID] ?? []
        } else {
            siblingIDs = nodes.filter { $0.parentID == nil }.map(\.id)
        }
        guard let siblingIndex = siblingIDs.firstIndex(of: nodeID) else { return }
        let destination = min(max(siblingIndex + offset, 0), siblingIDs.count - 1)
        guard destination != siblingIndex,
              let destinationNodeIndex = nodeIndexByID[siblingIDs[destination]] else {
            return
        }

        let beforeNodes = nodes
        let beforeConnections = connections
        nodes.swapAt(nodeIndex, destinationNodeIndex)
        if let parentID = node.parentID {
            layOutChildren(of: parentID, childIDs: children(of: parentID).map(\.id))
        }
        registerChange(
            offset < 0 ? "Move Idea Earlier" : "Move Idea Later",
            fromNodes: beforeNodes,
            fromConnections: beforeConnections
        )
    }

    func beginAssociation(from nodeID: UUID) {
        guard nodeIndexByID[nodeID] != nil else { return }
        connectionSourceNodeID = nodeID
        selectedNodeIDs = [nodeID]
        notice = EditorNotice(
            kind: .info,
            title: "Connect ideas",
            message: "Choose another idea to create a cross-link."
        )
    }

    func completeAssociation(to targetNodeID: UUID) {
        guard let sourceNodeID = connectionSourceNodeID else { return }
        connectionSourceNodeID = nil
        createAssociation(from: sourceNodeID, to: targetNodeID)
    }

    func createAssociation(from sourceNodeID: UUID, to targetNodeID: UUID) {
        guard sourceNodeID != targetNodeID,
              let source = getNode(by: sourceNodeID),
              nodeIndexByID[targetNodeID] != nil,
              !connections.contains(where: {
                  $0.kind == .association &&
                  $0.fromNodeID == sourceNodeID &&
                  $0.toNodeID == targetNodeID
              }) else {
            return
        }

        let beforeNodes = nodes
        let beforeConnections = connections
        connections.append(
            Connection(
                from: sourceNodeID,
                to: targetNodeID,
                color: source.color,
                kind: .association
            )
        )
        registerChange(
            "Connect Ideas",
            fromNodes: beforeNodes,
            fromConnections: beforeConnections
        )
    }

    func connectNode(_ sourceNodeID: UUID, toNodeNear position: CGPoint) {
        let candidates = visibleNodes.filter { $0.id != sourceNodeID }
        guard let target = candidates.min(by: {
            hypot($0.position.x - position.x, $0.position.y - position.y) <
            hypot($1.position.x - position.x, $1.position.y - position.y)
        }) else {
            return
        }

        let distance = hypot(
            target.position.x - position.x,
            target.position.y - position.y
        )
        guard distance <= LayoutConstants.minNodeDistance else { return }
        createAssociation(from: sourceNodeID, to: target.id)
    }

    func deleteConnection(_ connectionID: UUID) {
        guard let connection = connections.first(where: { $0.id == connectionID }),
              connection.kind == .association else {
            return
        }
        let beforeNodes = nodes
        let beforeConnections = connections
        connections.removeAll { $0.id == connectionID }
        registerChange(
            "Remove Connection",
            fromNodes: beforeNodes,
            fromConnections: beforeConnections
        )
    }

    func deleteNode(nodeID: UUID) {
        guard nodeIndexByID[nodeID] != nil else { return }
        let beforeNodes = nodes
        let beforeConnections = connections
        removeNodes(withIDs: descendantIDs(of: [nodeID], includingRoots: true))
        registerChange("Delete Idea", fromNodes: beforeNodes, fromConnections: beforeConnections)
    }

    func deleteSelectedNodes() {
        guard !selectedNodeIDs.isEmpty else { return }
        let beforeNodes = nodes
        let beforeConnections = connections
        let selectedIDs = selectedNodeIDs.filter { nodeIndexByID[$0] != nil }
        let nodeIDsToDelete = descendantIDs(of: Set(selectedIDs), includingRoots: true)
        removeNodes(withIDs: nodeIDsToDelete)
        selectedNodeIDs = []
        registerChange("Delete Ideas", fromNodes: beforeNodes, fromConnections: beforeConnections)
    }

    func selectNodesInRect(_ rect: CGRect) {
        selectedNodeIDs = Set(
            visibleNodes.lazy.filter { rect.contains($0.position) }.map(\.id)
        )
    }

    func toggleNodeSelection(_ nodeID: UUID, addToSelection: Bool) {
        if connectionSourceNodeID != nil {
            completeAssociation(to: nodeID)
            return
        }
        if addToSelection {
            var updatedSelection = selectedNodeIDs
            if updatedSelection.contains(nodeID) {
                updatedSelection.remove(nodeID)
            } else {
                updatedSelection.insert(nodeID)
            }
            selectedNodeIDs = updatedSelection
        } else {
            selectedNodeIDs = [nodeID]
        }
    }

    func clearSelection() {
        selectedNodeIDs.removeAll()
    }

    func moveSelectedNodes(
        by offset: CGSize,
        snapToGrid: Bool = false,
        gridSize: CGFloat = 20
    ) {
        guard !selectedNodeIDs.isEmpty else { return }
        let beforeNodes = nodes
        let beforeConnections = connections

        let nodesToMove = descendantIDs(of: selectedNodeIDs, includingRoots: true)

        var updatedNodes = nodes
        for nodeID in nodesToMove {
            guard let index = nodeIndexByID[nodeID] else { continue }
            let currentPos = updatedNodes[index].position
            var newPosition = CGPoint(
                x: currentPos.x + offset.width,
                y: currentPos.y + offset.height
            )
            if snapToGrid, gridSize > 0 {
                newPosition.x = (newPosition.x / gridSize).rounded() * gridSize
                newPosition.y = (newPosition.y / gridSize).rounded() * gridSize
            }
            updatedNodes[index].position = newPosition
        }
        nodes = updatedNodes
        registerChange(
            selectedNodeIDs.count == 1 ? "Move Idea" : "Move Ideas",
            fromNodes: beforeNodes,
            fromConnections: beforeConnections
        )
    }

    func isNodeSelected(_ nodeID: UUID) -> Bool {
        return selectedNodeIDs.contains(nodeID)
    }

    func startIdeaGeneration(for nodeID: UUID? = nil) {
        if let nodeID = nodeID, let node = getNode(by: nodeID) {
            generationPrompt = node.title
            generationParentNodeID = nodeID
        } else {
            generationPrompt = ""
            generationParentNodeID = nil
        }
        isGeneratingIdeas = true
    }

    func cancelIdeaGeneration() {
        isGeneratingIdeas = false
        generationPrompt = ""
        generationParentNodeID = nil
        aiGenerationPhase = .idle
    }

    private let aiService = AIService()

    @MainActor
    func generateIdeas(prompt: String, parentNodeID: UUID? = nil) async {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }
        let beforeNodes = nodes
        let beforeConnections = connections
        aiGenerationPhase = .generating

        defer {
            isGeneratingIdeas = false
            generationPrompt = ""
            generationParentNodeID = nil
        }

        do {
            // Build context from parent chain if exists
            let context = buildContextChain(for: parentNodeID)

            // Use Apple's Foundation Models API for on-device AI generation
            let generatedIdeas = try await aiService.generateIdeas(topic: cleanPrompt, context: context)
            try Task.checkCancellation()

            if let parentID = parentNodeID, let parentNode = getNode(by: parentID) {
                // Generate child nodes for existing parent
                let existingChildrenCount = childIDsByParentID[parentID]?.count ?? 0

                for (index, idea) in generatedIdeas.enumerated() {
                    let position = calculateChildPosition(
                        parent: parentNode,
                        index: existingChildrenCount + index,
                        totalChildren: existingChildrenCount + generatedIdeas.count
                    )
                    createChildNode(title: idea, position: position, parentID: parentID)
                }
            } else {
                // Create the center node (original behavior)
                let centerNode = IdeaNode(
                    title: cleanPrompt,
                    position: visibleCanvasCenter,
                    color: nextRootColor()
                )
                nodes.append(centerNode)

                // Create child nodes from AI-generated ideas
                for (index, idea) in generatedIdeas.enumerated() {
                    let position = calculateCircularPosition(
                        center: centerNode.position,
                        index: index,
                        total: generatedIdeas.count
                    )
                    createChildNode(title: idea, position: position, parentID: centerNode.id)
                }
            }
            aiGenerationPhase = .generatedOnDevice
            notice = EditorNotice(
                kind: .success,
                title: "Generated on-device",
                message: "Apple Intelligence created editable branches without sending your topic anywhere."
            )
        } catch is CancellationError {
            aiGenerationPhase = .idle
            return
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ??
                "On-device generation could not be completed."
            aiGenerationPhase = .usedFallback(message)
            await generateFallbackIdeas(prompt: cleanPrompt, parentNodeID: parentNodeID)
            notice = EditorNotice(
                kind: .warning,
                title: "Starter framework used",
                message: "\(message) MindNative created a generic editable framework instead."
            )
        }

        guard !Task.isCancelled else { return }

        registerChange(
            "Generate Ideas",
            fromNodes: beforeNodes,
            fromConnections: beforeConnections
        )

        if isAutoLayoutEnabled {
            applyAutoLayout(actionName: "Arrange Generated Ideas")
        }
    }

    private func buildContextChain(for nodeID: UUID?) -> [String] {
        guard let nodeID = nodeID else { return [] }

        var context: [String] = []
        var currentNodeID: UUID? = nodeID

        // Walk up the parent chain to build context
        while let currentID = currentNodeID, let node = getNode(by: currentID) {
            if !node.title.isEmpty {
                context.insert(node.title, at: 0)
            }
            currentNodeID = node.parentID
        }

        return context
    }

    @MainActor
    func applyAutoLayout(
        actionName: String = "Auto Layout",
        style: MindMapLayout? = nil,
        undoBaselineNodes: [IdeaNode]? = nil,
        undoBaselineConnections: [Connection]? = nil
    ) {
        layoutTask?.cancel()
        layoutGeneration = UUID()
        let generation = layoutGeneration
        let currentNodes = nodes
        let beforeNodes = undoBaselineNodes ?? currentNodes
        let beforeConnections = undoBaselineConnections ?? connections
        let startingRevision = mutationRevision
        let selectedStyle = style ?? layoutStyle
        layoutStyle = selectedStyle

        layoutTask = Task { @MainActor [weak self, currentNodes] in
            let separatedPositions = await Task.detached { [currentNodes, selectedStyle] in
                let treePositions = LayoutEngine.computeLayout(
                    nodes: currentNodes,
                    style: selectedStyle
                )
                guard !Task.isCancelled else { return [UUID: CGPoint]() }
                let laidOut = currentNodes.map { node -> IdeaNode in
                    var updatedNode = node
                    if let position = treePositions[node.id] {
                        updatedNode.position = position
                    }
                    return updatedNode
                }
                return LayoutEngine.separateOverlaps(nodes: laidOut)
            }.value

            guard !Task.isCancelled, let self else { return }
            guard self.layoutGeneration == generation,
                  self.mutationRevision == startingRevision else {
                return
            }
            let updatedNodes = self.nodes.map { node -> IdeaNode in
                var updatedNode = node
                if let position = separatedPositions[node.id] {
                    updatedNode.position = position
                }
                return updatedNode
            }
            self.nodes = updatedNodes
            self.registerChange(
                actionName,
                fromNodes: beforeNodes,
                fromConnections: beforeConnections
            )
        }
    }

    @MainActor
    private func generateFallbackIdeas(prompt: String, parentNodeID: UUID?) async {
        let fallbackIdeas = [
            "Key Benefits",
            "Challenges",
            "Implementation Steps",
            "Related Topics",
            "Future Opportunities"
        ]

        if let parentNodeID, let parentNode = getNode(by: parentNodeID) {
            let existingChildrenCount = childIDsByParentID[parentNodeID]?.count ?? 0
            for (index, idea) in fallbackIdeas.enumerated() {
                let position = calculateChildPosition(
                    parent: parentNode,
                    index: existingChildrenCount + index,
                    totalChildren: existingChildrenCount + fallbackIdeas.count
                )
                createChildNode(title: idea, position: position, parentID: parentNodeID)
            }
        } else {
            let centerNode = IdeaNode(
                title: prompt,
                position: visibleCanvasCenter,
                color: nextRootColor()
            )
            nodes.append(centerNode)

            for (index, idea) in fallbackIdeas.enumerated() {
                let position = calculateCircularPosition(
                    center: centerNode.position,
                    index: index,
                    total: fallbackIdeas.count
                )
                createChildNode(title: idea, position: position, parentID: centerNode.id)
            }
        }
    }

    // MARK: - Canvas Navigation

    func zoomIn() {
        zoomScale = min(zoomScale + 0.1, 3)
    }

    func zoomOut() {
        zoomScale = max(zoomScale - 0.1, 0.5)
    }

    func resetView() {
        zoomScale = 1
        canvasOffset = .zero
    }

    func fitToContent() {
        let fittedNodes = visibleNodes
        guard !fittedNodes.isEmpty, viewportSize.width > 0, viewportSize.height > 0 else {
            resetView()
            return
        }

        let padding: CGFloat = 96
        var minX = fittedNodes[0].position.x
        var maxX = minX
        var minY = fittedNodes[0].position.y
        var maxY = minY
        for node in fittedNodes.dropFirst() {
            minX = min(minX, node.position.x)
            maxX = max(maxX, node.position.x)
            minY = min(minY, node.position.y)
            maxY = max(maxY, node.position.y)
        }
        let bounds = CGRect(
            x: minX - 120,
            y: minY - 80,
            width: max(maxX - minX + 240, 240),
            height: max(maxY - minY + 160, 160)
        )
        let availableWidth = max(viewportSize.width - padding * 2, 1)
        let availableHeight = max(viewportSize.height - padding * 2, 1)
        let scale = min(availableWidth / bounds.width, availableHeight / bounds.height)

        zoomScale = min(max(scale, 0.5), 2)
        canvasOffset = CGSize(
            width: (viewportSize.width - bounds.width * zoomScale) / 2 - bounds.minX * zoomScale,
            height: (viewportSize.height - bounds.height * zoomScale) / 2 - bounds.minY * zoomScale
        )
    }

    // MARK: - Undo/Redo Support

    func moveNodeWithoutUndo(nodeID: UUID, to position: CGPoint) {
        guard let index = nodeIndexByID[nodeID] else { return }
        nodes[index].position = position
    }

    func updateNodeTitleWithoutUndo(nodeID: UUID, newTitle: String) {
        guard let index = nodeIndexByID[nodeID] else { return }
        nodes[index].title = newTitle
    }

    func removeNode(nodeID: UUID, registeringUndo: Bool) {
        if registeringUndo, let undoService = undoService {
            guard let node = getNode(by: nodeID) else { return }
            let relatedConnections = connections.filter { $0.fromNodeID == nodeID || $0.toNodeID == nodeID }
            let children = (childIDsByParentID[nodeID] ?? []).compactMap(getNode)
            undoService.registerNodeDeletion(node: node, connections: relatedConnections, children: children, viewModel: self)
        }
        deleteNode(nodeID: nodeID)
    }

    func restoreNode(node: IdeaNode, connections: [Connection], children: [IdeaNode], registeringUndo: Bool) {
        nodes.append(contentsOf: [node] + children)
        self.connections.append(contentsOf: connections)
        if registeringUndo, let undoService = undoService {
            undoService.registerNodeAddition(nodeID: node.id, node: node, connections: connections, viewModel: self)
        }
    }

    // MARK: - Copy/Paste/Cut

    func copySelectedNodes() {
        guard let content = selectedBranchContent() else { return }

        do {
            try CanvasClipboard.write(
                nodes: content.nodes,
                connections: content.connections,
                to: pasteboard
            )
        } catch {
            notice = EditorNotice(
                kind: .error,
                title: "Could not copy ideas",
                message: error.localizedDescription
            )
        }
    }

    func copySelectedNodes(as format: MindMapExportFormat) {
        guard let content = selectedBranchContent() else { return }
        let copiedIDs = Set(content.nodes.map(\.id))
        let exportNodes = content.nodes.map { node in
            guard let parentID = node.parentID,
                  !copiedIDs.contains(parentID) else {
                return node
            }
            var root = node
            root.parentID = nil
            return root
        }

        do {
            let data = try InterchangeService.exportData(
                format: format,
                nodes: exportNodes,
                connections: content.connections
            )
            try CanvasClipboard.write(
                exportData: data,
                format: format,
                to: pasteboard
            )
            notice = EditorNotice(
                kind: .success,
                title: "Copied \(format.title)",
                message: "The selected ideas are ready to paste."
            )
        } catch {
            notice = EditorNotice(
                kind: .error,
                title: "Could not copy as \(format.title)",
                message: error.localizedDescription
            )
        }
    }

    func cutSelectedNodes() {
        guard let content = selectedBranchContent() else { return }

        do {
            try CanvasClipboard.write(
                nodes: content.nodes,
                connections: content.connections,
                to: pasteboard
            )
        } catch {
            notice = EditorNotice(
                kind: .error,
                title: "Could not cut ideas",
                message: error.localizedDescription
            )
            return
        }
        deleteSelectedNodes()
    }

    private func selectedBranchContent() -> (
        nodes: [IdeaNode],
        connections: [Connection]
    )? {
        let copiedIDs = descendantIDs(
            of: selectedNodeIDs,
            includingRoots: true
        )
        let copiedNodes = nodes.filter { copiedIDs.contains($0.id) }
        guard !copiedNodes.isEmpty else { return nil }

        let copiedConnections = connections.filter {
            copiedIDs.contains($0.fromNodeID) &&
            copiedIDs.contains($0.toNodeID)
        }
        return (copiedNodes, copiedConnections)
    }

    func pasteNodes(at position: CGPoint? = nil) {
        let payload: CanvasClipboardPayload
        do {
            guard let decoded = try CanvasClipboard.read(from: pasteboard) else { return }
            payload = decoded
        } catch {
            notice = EditorNotice(
                kind: .error,
                title: "Could not paste ideas",
                message: "The clipboard does not contain a valid MindNative branch."
            )
            return
        }

        let clipboardNodes = payload.nodes
        guard !clipboardNodes.isEmpty else { return }
        let beforeNodes = nodes
        let beforeConnections = connections

        var idMapping: [UUID: UUID] = [:]
        var pastedNodes: [IdeaNode] = []

        let firstNode = clipboardNodes[0]
        let targetPosition = position ?? CGPoint(
            x: firstNode.position.x + 50,
            y: firstNode.position.y + 50
        )
        let offset = CGSize(
            width: targetPosition.x - firstNode.position.x,
            height: targetPosition.y - firstNode.position.y
        )

        for node in clipboardNodes {
            let newID = UUID()
            idMapping[node.id] = newID

            var newNode = node
            newNode.id = newID
            newNode.position = CGPoint(
                x: node.position.x + offset.width,
                y: node.position.y + offset.height
            )
            newNode.parentID = nil
            pastedNodes.append(newNode)
        }

        for i in 0..<pastedNodes.count {
            if let oldParentID = clipboardNodes[i].parentID,
               let newParentID = idMapping[oldParentID] {
                pastedNodes[i].parentID = newParentID
            }
        }

        nodes.append(contentsOf: pastedNodes)

        let pastedConnections = payload.connections.compactMap { connection -> Connection? in
            guard let newFromID = idMapping[connection.fromNodeID],
                  let newToID = idMapping[connection.toNodeID] else {
                return nil
            }
            return Connection(
                from: newFromID,
                to: newToID,
                color: connection.color,
                kind: connection.kind,
                label: connection.label
            )
        }
        connections.append(contentsOf: pastedConnections)

        // Select pasted nodes
        selectedNodeIDs = Set(pastedNodes.map { $0.id })
        focusedNodeID = pastedNodes.first?.id
        registerChange("Paste Ideas", fromNodes: beforeNodes, fromConnections: beforeConnections)
    }

    func duplicateSelectedNodes() {
        copySelectedNodes()
        pasteNodes()
    }

    func selectAllNodes() {
        selectedNodeIDs = Set(visibleNodes.map(\.id))
    }

    // MARK: - Templates

    @MainActor
    func insertTemplate(_ template: MindMapTemplate) {
        let beforeNodes = nodes
        let beforeConnections = connections
        let center = freePosition(near: visibleCanvasCenter)
        let root = IdeaNode(
            title: template.rootTitle,
            position: center,
            color: nextRootColor()
        )
        nodes.append(root)

        for (index, branch) in template.branches.enumerated() {
            let child = IdeaNode(
                title: branch.title,
                position: calculateChildPosition(
                    parent: root,
                    index: index,
                    totalChildren: template.branches.count
                ),
                color: root.color,
                parentID: root.id,
                notes: branch.notes,
                tags: branch.tags,
                isTask: branch.isTask,
                iconName: branch.iconName
            )
            nodes.append(child)
            connections.append(
                Connection(from: root.id, to: child.id, color: root.color)
            )
        }

        selectedNodeIDs = [root.id]
        focusedNodeID = root.id
        registerChange(
            "Insert \(template.title) Template",
            fromNodes: beforeNodes,
            fromConnections: beforeConnections
        )
        applyAutoLayout()
    }

    func dismissNotice() {
        notice = nil
    }

    func cancelAssociation() {
        connectionSourceNodeID = nil
    }

    // MARK: - Import and Export

    @MainActor
    func exportMap(as format: MindMapExportFormat) {
        do {
            let suggestedName = nodes.first(where: { $0.parentID == nil })?.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let didExport = try InterchangeService.export(
                format: format,
                nodes: visibleNodes,
                connections: visibleConnections,
                suggestedName: suggestedName?.isEmpty == false ? suggestedName! : "Mind Map"
            )
            if didExport {
                notice = EditorNotice(
                    kind: .success,
                    title: "Export complete",
                    message: "The visible map was exported as \(format.title)."
                )
            }
        } catch {
            notice = EditorNotice(
                kind: .error,
                title: "Export failed",
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    func importMap(from format: MindMapImportFormat) {
        do {
            guard let document = try InterchangeService.importDocument(format: format) else {
                return
            }
            mergeImportedDocument(document, title: format.title)
        } catch {
            notice = EditorNotice(
                kind: .error,
                title: "Import failed",
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func mergeImportedDocument(
        _ document: MindDocumentData,
        title: String
    ) {
        guard !document.nodes.isEmpty else { return }
        let beforeNodes = nodes
        let beforeConnections = connections
        var idMapping: [UUID: UUID] = [:]
        let firstPosition = document.nodes[0].position
        let target = freePosition(near: visibleCanvasCenter)
        let offset = CGSize(
            width: target.x - firstPosition.x,
            height: target.y - firstPosition.y
        )

        var importedNodes = document.nodes.map { node -> IdeaNode in
            var imported = node
            let newID = UUID()
            idMapping[node.id] = newID
            imported.id = newID
            imported.position = CGPoint(
                x: node.position.x + offset.width,
                y: node.position.y + offset.height
            )
            return imported
        }

        for index in importedNodes.indices {
            if let oldParentID = document.nodes[index].parentID {
                importedNodes[index].parentID = idMapping[oldParentID]
            }
        }

        let importedConnections = document.connections.compactMap {
            connection -> Connection? in
            guard let from = idMapping[connection.fromNodeID],
                  let to = idMapping[connection.toNodeID] else {
                return nil
            }
            return Connection(
                from: from,
                to: to,
                color: connection.color,
                kind: connection.kind,
                label: connection.label
            )
        }

        nodes.append(contentsOf: importedNodes)
        connections.append(contentsOf: importedConnections)
        selectedNodeIDs = Set(importedNodes.map(\.id))
        focusedNodeID = importedNodes.first?.id
        registerChange(
            "Import \(title)",
            fromNodes: beforeNodes,
            fromConnections: beforeConnections
        )
        notice = EditorNotice(
            kind: .success,
            title: "Import complete",
            message: "\(importedNodes.count) ideas were added to this map."
        )
        applyAutoLayout(actionName: "Arrange Imported Ideas")
    }

    // MARK: - Keyboard Navigation

    private func updateKeyboardFocus(to nodeID: UUID, extendingSelection: Bool) {
        guard visibleNodeIDs().contains(nodeID) else { return }
        focusedNodeID = nodeID
        if extendingSelection {
            var updatedSelection = selectedNodeIDs
            updatedSelection.insert(nodeID)
            selectedNodeIDs = updatedSelection
        } else {
            selectedNodeIDs = [nodeID]
        }
    }

    func moveFocusToNextNode(extendingSelection: Bool = false) {
        let navigableNodes = visibleNodes
        guard !navigableNodes.isEmpty else { return }

        if let currentFocusID = focusedNodeID,
           let currentIndex = navigableNodes.firstIndex(where: { $0.id == currentFocusID }) {
            let nextIndex = (currentIndex + 1) % navigableNodes.count
            updateKeyboardFocus(to: navigableNodes[nextIndex].id, extendingSelection: extendingSelection)
        } else {
            updateKeyboardFocus(to: navigableNodes[0].id, extendingSelection: extendingSelection)
        }
    }

    func moveFocusToPreviousNode(extendingSelection: Bool = false) {
        let navigableNodes = visibleNodes
        guard !navigableNodes.isEmpty else { return }

        if let currentFocusID = focusedNodeID,
           let currentIndex = navigableNodes.firstIndex(where: { $0.id == currentFocusID }) {
            let previousIndex = currentIndex == 0 ? navigableNodes.count - 1 : currentIndex - 1
            updateKeyboardFocus(to: navigableNodes[previousIndex].id, extendingSelection: extendingSelection)
        } else {
            updateKeyboardFocus(
                to: navigableNodes[navigableNodes.count - 1].id,
                extendingSelection: extendingSelection
            )
        }
    }

    func moveFocusInDirection(_ direction: MovementDirection, extendingSelection: Bool = false) {
        guard let currentFocusID = focusedNodeID,
              let currentNode = getNode(by: currentFocusID) else {
            if let firstNodeID = visibleNodes.first?.id {
                updateKeyboardFocus(to: firstNodeID, extendingSelection: extendingSelection)
            }
            return
        }

        let currentPos = currentNode.position
        var closestNode: IdeaNode?
        var closestDistance: CGFloat = .infinity

        for node in visibleNodes where node.id != currentFocusID {
            let isInDirection: Bool
            switch direction {
            case .up:
                isInDirection = node.position.y < currentPos.y
            case .down:
                isInDirection = node.position.y > currentPos.y
            case .left:
                isInDirection = node.position.x < currentPos.x
            case .right:
                isInDirection = node.position.x > currentPos.x
            }

            if isInDirection {
                let distance = hypot(node.position.x - currentPos.x, node.position.y - currentPos.y)
                if distance < closestDistance {
                    closestDistance = distance
                    closestNode = node
                }
            }
        }

        if let nextNode = closestNode {
            updateKeyboardFocus(to: nextNode.id, extendingSelection: extendingSelection)
        }
    }

    func focusFirstNode(extendingSelection: Bool = false) {
        guard let firstNodeID = visibleNodes.first?.id else { return }
        updateKeyboardFocus(to: firstNodeID, extendingSelection: extendingSelection)
    }

    func focusLastNode(extendingSelection: Bool = false) {
        guard let lastNodeID = visibleNodes.last?.id else { return }
        updateKeyboardFocus(to: lastNodeID, extendingSelection: extendingSelection)
    }

    func toggleFocusedNodeSelection() {
        guard let focusedID = focusedNodeID else { return }
        toggleNodeSelection(focusedID, addToSelection: true)
    }

    func addChildToFocusedNode() {
        guard let focusedNodeID,
              let focusedNode = getNode(by: focusedNodeID) else {
            addRootNode()
            return
        }
        addChildNode(to: focusedNode)
    }

    func addSiblingToFocusedNode() {
        guard let focusedNodeID,
              let focusedNode = getNode(by: focusedNodeID) else {
            addRootNode()
            return
        }

        if let parentID = focusedNode.parentID,
           let parentNode = getNode(by: parentID) {
            addChildNode(to: parentNode)
        } else {
            addRootNode(at: CGPoint(
                x: focusedNode.position.x,
                y: focusedNode.position.y + LayoutConstants.verticalSpacing
            ))
        }
    }

    func nudgeFocusedSelection(in direction: MovementDirection, distance: CGFloat) {
        guard distance > 0 else { return }
        if selectedNodeIDs.isEmpty, let focusedNodeID {
            selectedNodeIDs = [focusedNodeID]
        }
        guard !selectedNodeIDs.isEmpty else { return }

        let offset: CGSize
        switch direction {
        case .up:
            offset = CGSize(width: 0, height: -distance)
        case .down:
            offset = CGSize(width: 0, height: distance)
        case .left:
            offset = CGSize(width: -distance, height: 0)
        case .right:
            offset = CGSize(width: distance, height: 0)
        }
        moveSelectedNodes(by: offset)
    }

    func startEditingFocusedNode() {
        guard let focusedID = focusedNodeID else {
            addRootNode()
            return
        }
        selectedNodeIDs = [focusedID]
        editingNodeID = focusedID
    }

    enum MovementDirection {
        case up, down, left, right
    }
}

enum AIGenerationPhase: Equatable {
    case idle
    case generating
    case generatedOnDevice
    case usedFallback(String)
}

struct EditorNotice: Identifiable, Equatable {
    enum Kind {
        case info
        case success
        case warning
        case error
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let message: String
}

struct TemplateBranch {
    let title: String
    var notes: String = ""
    var tags: [String] = []
    var isTask = false
    var iconName: String?
}

enum MindMapTemplate: String, CaseIterable, Identifiable {
    case projectPlan
    case learningPlan
    case decision
    case meeting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projectPlan: return "Project Plan"
        case .learningPlan: return "Learning Plan"
        case .decision: return "Decision"
        case .meeting: return "Meeting"
        }
    }

    var rootTitle: String {
        switch self {
        case .projectPlan: return "New Project"
        case .learningPlan: return "Learning Goal"
        case .decision: return "Decision"
        case .meeting: return "Meeting Notes"
        }
    }

    var branches: [TemplateBranch] {
        switch self {
        case .projectPlan:
            return [
                TemplateBranch(title: "Goals", iconName: "target"),
                TemplateBranch(title: "Milestones", isTask: true, iconName: "flag"),
                TemplateBranch(title: "Tasks", isTask: true, iconName: "checklist"),
                TemplateBranch(title: "Risks", tags: ["risk"], iconName: "exclamationmark.triangle"),
                TemplateBranch(title: "Resources", iconName: "person.2")
            ]
        case .learningPlan:
            return [
                TemplateBranch(title: "Core Concepts", iconName: "book"),
                TemplateBranch(title: "Practice", isTask: true, iconName: "hammer"),
                TemplateBranch(title: "Resources", iconName: "link"),
                TemplateBranch(title: "Questions", iconName: "questionmark.circle"),
                TemplateBranch(title: "Review", isTask: true, iconName: "arrow.clockwise")
            ]
        case .decision:
            return [
                TemplateBranch(title: "Options", iconName: "square.grid.2x2"),
                TemplateBranch(title: "Benefits", tags: ["pros"], iconName: "plus.circle"),
                TemplateBranch(title: "Tradeoffs", tags: ["cons"], iconName: "minus.circle"),
                TemplateBranch(title: "Evidence", iconName: "doc.text.magnifyingglass"),
                TemplateBranch(title: "Next Step", isTask: true, iconName: "arrow.right.circle")
            ]
        case .meeting:
            return [
                TemplateBranch(title: "Agenda", iconName: "list.bullet"),
                TemplateBranch(title: "Discussion", iconName: "bubble.left.and.bubble.right"),
                TemplateBranch(title: "Decisions", iconName: "checkmark.seal"),
                TemplateBranch(title: "Action Items", isTask: true, iconName: "checklist"),
                TemplateBranch(title: "Follow Up", isTask: true, iconName: "calendar")
            ]
        }
    }
}
