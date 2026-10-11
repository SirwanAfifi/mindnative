import SwiftUI
import AppKit

/// Custom commands for the MindNative app menu bar
struct AppCommands: Commands {
    @FocusedValue(\.canvasViewModel) var viewModel: CanvasViewModel?
    @FocusedValue(\.undoService) var undoService: UndoService?

    private var canvasAcceptsCommands: Bool {
        guard let viewModel else { return false }
        return viewModel.editingNodeID == nil &&
            !viewModel.isGeneratingIdeas &&
            !viewModel.isKeyboardHelpPresented
    }

    private var hasSelection: Bool {
        canvasAcceptsCommands && !(viewModel?.selectedNodeIDs.isEmpty ?? true)
    }

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Share Map…") {
                viewModel?.shareMap()
            }
            .disabled(viewModel?.nodes.isEmpty ?? true)

            Menu("Import") {
                ForEach(MindMapImportFormat.allCases) { format in
                    Button(format.title) {
                        viewModel?.importMap(from: format)
                    }
                }
            }
            .disabled(viewModel == nil)

            Menu("Export") {
                ForEach(MindMapExportFormat.allCases) { format in
                    Button(format.title) {
                        viewModel?.exportMap(as: format)
                    }
                }
            }
            .disabled(viewModel?.nodes.isEmpty ?? true)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print Map…") {
                viewModel?.printMap()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(viewModel?.nodes.isEmpty ?? true)
        }

        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                if canvasAcceptsCommands {
                    undoService?.undo()
                } else {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(canvasAcceptsCommands && !(undoService?.canUndo ?? false))

            Button("Redo") {
                if canvasAcceptsCommands {
                    undoService?.redo()
                } else {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(canvasAcceptsCommands && !(undoService?.canRedo ?? false))
        }

        // Replace default Edit menu items
        CommandGroup(after: .undoRedo) {
            Divider()

            Button("Select All") {
                viewModel?.selectAllNodes()
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(!canvasAcceptsCommands)

            Button("Deselect All") {
                viewModel?.clearSelection()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(!hasSelection)

            Divider()

            Button("Copy") {
                viewModel?.copySelectedNodes()
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(!hasSelection)

            Menu("Copy As") {
                ForEach(MindMapExportFormat.allCases) { format in
                    Button(format.title) {
                        viewModel?.copySelectedNodes(as: format)
                    }
                }
            }
            .disabled(!hasSelection)

            Button("Cut") {
                viewModel?.cutSelectedNodes()
            }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(!hasSelection)

            Button("Paste") {
                viewModel?.pasteNodes()
            }
            .keyboardShortcut("v", modifiers: .command)
            .disabled(!canvasAcceptsCommands || !(viewModel?.canPasteIdeas ?? false))

            Button("Duplicate") {
                viewModel?.duplicateSelectedNodes()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!hasSelection)
        }

        // Canvas menu
        CommandMenu("Canvas") {
            Button("Zoom In") {
                viewModel?.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(!canvasAcceptsCommands)

            Button("Zoom Out") {
                viewModel?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(!canvasAcceptsCommands)

            Button("Actual Size") {
                viewModel?.zoomScale = 1.0
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(!canvasAcceptsCommands)

            Divider()

            Button("Fit to Content") {
                viewModel?.fitToContent()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .disabled(!canvasAcceptsCommands)

            Button("Reset View") {
                viewModel?.resetView()
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            .disabled(!canvasAcceptsCommands)

            Divider()

            Menu("Layout") {
                ForEach(MindMapLayout.allCases) { style in
                    Button {
                        viewModel?.applyAutoLayout(style: style)
                    } label: {
                        Label(style.title, systemImage: style.systemImage)
                    }
                }
            }
            .disabled(viewModel?.nodes.isEmpty ?? true)

            Button(viewModel?.isPresentationMode == true ? "End Presentation" : "Start Presentation") {
                if viewModel?.isPresentationMode == true {
                    viewModel?.endPresentation()
                } else {
                    viewModel?.startPresentation()
                }
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(viewModel?.nodes.isEmpty ?? true)

            Divider()

            Button("Keyboard Shortcuts…") {
                viewModel?.isKeyboardHelpPresented = true
            }
            .keyboardShortcut("/", modifiers: .command)
            .disabled(!canvasAcceptsCommands)

            Divider()

            Button("Toggle Navigator") {
                viewModel?.isNavigatorPresented.toggle()
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            .disabled(viewModel == nil)

            Button("Toggle Inspector") {
                viewModel?.editingNodeID = nil
                viewModel?.isInspectorPresented.toggle()
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
            .disabled(viewModel == nil)
        }

        // Idea menu
        CommandMenu("Idea") {
            Button("Add Main Idea") {
                viewModel?.addRootNode()
            }
            .keyboardShortcut(.return, modifiers: .option)
            .disabled(!canvasAcceptsCommands)

            Button("Add Child Idea") {
                viewModel?.addChildToFocusedNode()
            }
            .keyboardShortcut(.tab, modifiers: [])
            .disabled(!canvasAcceptsCommands)

            Button("Add Sibling Idea") {
                viewModel?.addSiblingToFocusedNode()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!canvasAcceptsCommands)

            Button("Rename Idea") {
                viewModel?.startEditingFocusedNode()
            }
            .disabled(!canvasAcceptsCommands || viewModel?.focusedNodeID == nil)

            Divider()

            Button("Generate Ideas...") {
                viewModel?.startIdeaGeneration()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(!canvasAcceptsCommands)

            Menu("Analyze Map") {
                ForEach(AIMapAction.allCases) { action in
                    Button(action.title) {
                        Task {
                            await viewModel?.runAIAction(action)
                        }
                    }
                }
            }
            .disabled(!canvasAcceptsCommands || viewModel?.nodes.isEmpty == true)

            Button("Auto Layout") {
                viewModel?.applyAutoLayout()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(!canvasAcceptsCommands)

            Divider()

            Button("Connect to Another Idea") {
                if let nodeID = viewModel?.focusedNodeID {
                    viewModel?.beginAssociation(from: nodeID)
                }
            }
            .disabled(!canvasAcceptsCommands || viewModel?.focusedNodeID == nil)

            Button("Promote to Main Idea") {
                if let nodeID = viewModel?.focusedNodeID {
                    viewModel?.promoteToRoot(nodeID)
                }
            }
            .disabled(
                !canvasAcceptsCommands ||
                viewModel?.focusedNodeID.flatMap { viewModel?.getNode(by: $0)?.parentID } == nil
            )

            Button("Collapse or Expand Branch") {
                if let nodeID = viewModel?.focusedNodeID {
                    viewModel?.toggleCollapsed(nodeID: nodeID)
                }
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!canvasAcceptsCommands || viewModel?.focusedNodeID == nil)

            Button("Focus on Branch") {
                if let nodeID = viewModel?.focusedNodeID {
                    viewModel?.focusOnBranch(nodeID)
                }
            }
            .disabled(!canvasAcceptsCommands || viewModel?.focusedNodeID == nil)

            Button("Show Entire Map") {
                viewModel?.clearBranchFocus()
            }
            .disabled(!canvasAcceptsCommands || viewModel?.focusedBranchRootID == nil)

            Divider()

            Button("Attach Files…") {
                if let nodeID = viewModel?.selectedNodeID {
                    viewModel?.addAttachments(to: nodeID)
                }
            }
            .disabled(!canvasAcceptsCommands || viewModel?.selectedNodeID == nil)

            Button("Add to Reminders") {
                Task {
                    await viewModel?.addSelectedIdeaToReminders()
                }
            }
            .disabled(!canvasAcceptsCommands || viewModel?.selectedNodeID == nil)

            Button("Add to Calendar") {
                Task {
                    await viewModel?.addSelectedIdeaToCalendar()
                }
            }
            .disabled(!canvasAcceptsCommands || viewModel?.selectedNodeID == nil)

            Divider()

            Button("Delete Ideas") {
                viewModel?.deleteSelectedNodes()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(!hasSelection)
        }
    }
}

// MARK: - Focused Values

struct CanvasViewModelKey: FocusedValueKey {
    typealias Value = CanvasViewModel
}

struct UndoServiceKey: FocusedValueKey {
    typealias Value = UndoService
}

extension FocusedValues {
    var canvasViewModel: CanvasViewModel? {
        get { self[CanvasViewModelKey.self] }
        set { self[CanvasViewModelKey.self] = newValue }
    }

    var undoService: UndoService? {
        get { self[UndoServiceKey.self] }
        set { self[UndoServiceKey.self] = newValue }
    }
}
