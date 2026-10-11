import Foundation
import SwiftUI

/// Service for managing undo/redo operations in the canvas
final class UndoService: ObservableObject {
    private let undoManager: UndoManager

    init(undoManager: UndoManager = UndoManager()) {
        self.undoManager = undoManager
    }

    var canUndo: Bool {
        undoManager.canUndo
    }

    var canRedo: Bool {
        undoManager.canRedo
    }

    func undo() {
        undoManager.undo()
        objectWillChange.send()
    }

    func redo() {
        undoManager.redo()
        objectWillChange.send()
    }

    func registerCanvasChange(
        actionName: String,
        fromNodes: [IdeaNode],
        fromConnections: [Connection],
        toNodes: [IdeaNode],
        toConnections: [Connection],
        viewModel: CanvasViewModel
    ) {
        guard fromNodes != toNodes || fromConnections != toConnections else { return }

        undoManager.registerUndo(withTarget: viewModel) { vm in
            vm.restoreCanvas(nodes: fromNodes, connections: fromConnections)
            self.registerCanvasChange(
                actionName: actionName,
                fromNodes: toNodes,
                fromConnections: toConnections,
                toNodes: fromNodes,
                toConnections: fromConnections,
                viewModel: vm
            )
        }
        undoManager.setActionName(actionName)
        objectWillChange.send()
    }

    // MARK: - Node Operations

    func registerNodeAddition(
        nodeID: UUID,
        node: IdeaNode,
        connections: [Connection],
        viewModel: CanvasViewModel
    ) {
        undoManager.registerUndo(withTarget: viewModel) { vm in
            vm.removeNode(nodeID: nodeID, registeringUndo: true)
        }
        undoManager.setActionName("Add Node")
    }

    func registerNodeDeletion(
        node: IdeaNode,
        connections: [Connection],
        children: [IdeaNode],
        viewModel: CanvasViewModel
    ) {
        undoManager.registerUndo(withTarget: viewModel) { vm in
            vm.restoreNode(node: node, connections: connections, children: children, registeringUndo: true)
        }
        undoManager.setActionName("Delete Node")
    }

    func registerNodeMove(
        nodeID: UUID,
        fromPosition: CGPoint,
        toPosition: CGPoint,
        viewModel: CanvasViewModel
    ) {
        undoManager.registerUndo(withTarget: viewModel) { vm in
            vm.moveNodeWithoutUndo(nodeID: nodeID, to: fromPosition)
            self.registerNodeMove(nodeID: nodeID, fromPosition: toPosition, toPosition: fromPosition, viewModel: vm)
        }
        undoManager.setActionName("Move Node")
    }

    func registerBatchNodeMove(
        moves: [(nodeID: UUID, from: CGPoint, to: CGPoint)],
        viewModel: CanvasViewModel
    ) {
        undoManager.registerUndo(withTarget: viewModel) { vm in
            let reverseMoves = moves.map { (nodeID: $0.nodeID, from: $0.to, to: $0.from) }
            for move in moves {
                vm.moveNodeWithoutUndo(nodeID: move.nodeID, to: move.from)
            }
            self.registerBatchNodeMove(moves: reverseMoves, viewModel: vm)
        }
        undoManager.setActionName("Move Nodes")
    }

    func registerNodeTitleChange(
        nodeID: UUID,
        oldTitle: String,
        newTitle: String,
        viewModel: CanvasViewModel
    ) {
        undoManager.registerUndo(withTarget: viewModel) { vm in
            vm.updateNodeTitleWithoutUndo(nodeID: nodeID, newTitle: oldTitle)
            self.registerNodeTitleChange(nodeID: nodeID, oldTitle: newTitle, newTitle: oldTitle, viewModel: vm)
        }
        undoManager.setActionName("Edit Node")
    }

    func beginUndoGrouping() {
        undoManager.beginUndoGrouping()
    }

    func endUndoGrouping() {
        undoManager.endUndoGrouping()
    }

    func removeAllActions() {
        undoManager.removeAllActions()
    }
}
