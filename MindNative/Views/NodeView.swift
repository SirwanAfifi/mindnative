import SwiftUI
import AppKit

struct NodeView: View, Equatable {
    let node: IdeaNode
    let viewModel: CanvasViewModel
    let isEditing: Bool
    let isSelected: Bool
    let isFocused: Bool
    let isConnectionSource: Bool
    let dragOffset: CGSize
    @State private var isDragging = false
    @State private var editingText = ""
    @State private var isHovering = false
    @AppStorage("snapToGrid") private var snapToGrid = false
    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("gridSize") private var gridSize = 24.0

    private var isRootNode: Bool {
        node.parentID == nil
    }

    static func == (lhs: NodeView, rhs: NodeView) -> Bool {
        lhs.node == rhs.node &&
        imagesAreIdentical(lhs.node.image, rhs.node.image) &&
        lhs.viewModel === rhs.viewModel &&
        lhs.isEditing == rhs.isEditing &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isFocused == rhs.isFocused &&
        lhs.isConnectionSource == rhs.isConnectionSource &&
        lhs.dragOffset == rhs.dragOffset &&
        // Styling is derived from depth, so a re-parented node has to redraw
        // even when the node value itself is unchanged.
        lhs.elevation == rhs.elevation
    }

    private static func imagesAreIdentical(_ lhs: NSImage?, _ rhs: NSImage?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs === rhs
        default:
            return false
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Auto-select if not already selected
                if !isDragging {
                    isDragging = true
                    if !isSelected {
                        viewModel.toggleNodeSelection(node.id, addToSelection: false)
                    }
                }
                // Update drag offsets for all selected nodes (works for single or multi-selection)
                viewModel.updateDragOffsets(viewModel.selectedNodeIDs, offset: value.translation)
            }
            .onEnded { value in
                // Move all selected nodes and clear their drag offsets
                viewModel.moveSelectedNodes(
                    by: value.translation,
                    snapToGrid: showGrid && snapToGrid,
                    gridSize: CGFloat(gridSize)
                )
                viewModel.clearDragOffsets(viewModel.selectedNodeIDs)

                isDragging = false
            }
    }

    public var body: some View {
        HStack(spacing: 0) {
            nodeCard

            // The add affordance grows out of the card as a stub of the edge it
            // will create, tinted with the branch hue the new child will inherit.
            HStack(spacing: 5) {
                Capsule()
                    .fill(
                        isHovering && !isEditing
                            ? node.color.opacity(0.55)
                            : Color.clear
                    )
                    .frame(width: 14, height: 2)

                if isHovering && !isEditing {
                    HStack(spacing: 5) {
                        Button {
                            viewModel.addChildNode(to: node)
                        } label: {
                            nodeAffordanceIcon("plus")
                        }
                        .buttonStyle(.plain)
                        .help("Add a connected child idea")
                        .accessibilityLabel("Add child idea")

                        Button {
                            viewModel.beginAssociation(from: node.id)
                        } label: {
                            nodeAffordanceIcon("point.3.connected.trianglepath.dotted")
                        }
                        .buttonStyle(.plain)
                        .help("Connect this idea to another idea, or drag to a target")
                        .accessibilityLabel("Connect idea")
                        .gesture(
                            DragGesture(
                                minimumDistance: 3,
                                coordinateSpace: .named("mindnative.canvas")
                            )
                            .onEnded { value in
                                viewModel.connectNode(node.id, toNodeNear: value.location)
                            }
                        )
                    }
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    Color.clear
                        .frame(width: 49, height: 22)
                }
            }
            .animation(Motion.hover, value: isHovering)
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button("Add Child Node") {
                viewModel.addChildNode(to: node)
            }

            Button("Connect to Another Idea") {
                viewModel.beginAssociation(from: node.id)
            }

            if !viewModel.children(of: node.id).isEmpty {
                Button(node.isCollapsed ? "Expand Branch" : "Collapse Branch") {
                    viewModel.toggleCollapsed(nodeID: node.id)
                }
            }

            Button("Focus on Branch") {
                viewModel.focusOnBranch(node.id)
            }

            if node.parentID != nil {
                Button("Promote to Main Idea") {
                    viewModel.promoteToRoot(node.id)
                }
            }

            if !node.title.isEmpty {
                Button("Generate...") {
                    viewModel.startIdeaGeneration(for: node.id)
                }
            }

            Menu("Analyze") {
                ForEach(AIMapAction.allCases) { action in
                    Button(action.title) {
                        Task { await viewModel.runAIAction(action, nodeID: node.id) }
                    }
                }
            }

            Button("Present from Here") {
                viewModel.startPresentation(from: node.id)
            }

            Divider()

            Button("Show Details") {
                viewModel.editingNodeID = nil
                viewModel.toggleNodeSelection(node.id, addToSelection: false)
                viewModel.isInspectorPresented = true
            }

            if let link = node.link {
                Button("Open Link") {
                    NSWorkspace.shared.open(link)
                }
            }

            Button("Attach Files…") {
                viewModel.addAttachments(to: node.id)
            }

            Button("Add to Reminders") {
                Task {
                    viewModel.toggleNodeSelection(node.id, addToSelection: false)
                    await viewModel.addSelectedIdeaToReminders()
                }
            }

            Button("Add to Calendar") {
                Task {
                    viewModel.toggleNodeSelection(node.id, addToSelection: false)
                    await viewModel.addSelectedIdeaToCalendar()
                }
            }

            if node.isTask {
                Button(node.isCompleted ? "Mark Incomplete" : "Mark Complete") {
                    viewModel.toggleTaskCompletion(nodeID: node.id)
                }
            }

            Menu("Move") {
                Button("Earlier") {
                    viewModel.moveSibling(node.id, by: -1)
                }
                Button("Later") {
                    viewModel.moveSibling(node.id, by: 1)
                }
            }

            Divider()

            Button("Cut") {
                prepareSelectionForContextAction()
                viewModel.cutSelectedNodes()
            }

            Button("Copy") {
                prepareSelectionForContextAction()
                viewModel.copySelectedNodes()
            }

            Menu("Copy As") {
                ForEach(MindMapExportFormat.allCases) { format in
                    Button(format.title) {
                        prepareSelectionForContextAction()
                        viewModel.copySelectedNodes(as: format)
                    }
                }
            }

            Button("Paste") {
                viewModel.pasteNodes(at: node.position)
            }

            Button("Duplicate") {
                prepareSelectionForContextAction()
                viewModel.duplicateSelectedNodes()
            }

            Divider()

            Button("Delete", role: .destructive) {
                viewModel.deleteNode(nodeID: node.id)
            }
        }
        .position(
            x: node.position.x + dragOffset.width,
            y: node.position.y + dragOffset.height
        )
        .gesture(dragGesture)
        .accessibilityElement(children: isEditing ? .contain : .ignore)
        .accessibilityLabel(node.title.isEmpty ? "Untitled idea" : node.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(
            isConnectionSource
                ? "Choose another idea to finish connecting."
                : "Double-click to edit. Drag to move."
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Edit") { startEditing() }
        .accessibilityAction(named: "Add child") { viewModel.addChildNode(to: node) }
        .accessibilityAction(named: "Connect") { viewModel.beginAssociation(from: node.id) }
        .accessibilityAction(named: "Delete") { viewModel.deleteNode(nodeID: node.id) }
        .accessibilityAction(named: node.isCollapsed ? "Expand branch" : "Collapse branch") {
            viewModel.toggleCollapsed(nodeID: node.id)
        }
        .accessibilityIdentifier("idea-\(node.id.uuidString)")
        .onAppear {
            if isEditing {
                prepareForEditing()
            }
        }
        .onChange(of: isEditing) { editing in
            if editing {
                prepareForEditing()
            }
        }
    }

    private var nodeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = node.image, isRootNode {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 220, maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(ColorTheme.borderSubtle, lineWidth: 1)
                    }
            }

            HStack(alignment: .center, spacing: 11) {
                // The rail is the node's hue at full strength — the one place the
                // branch color reads as itself rather than as a wash.
                Capsule()
                    .fill(node.color)
                    .frame(width: isRootNode ? 4 : 3, height: elevation.railHeight)

                if node.isTask && !isEditing {
                    Button {
                        viewModel.toggleTaskCompletion(nodeID: node.id)
                    } label: {
                        Image(systemName: node.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(node.isCompleted ? Color.green : node.color)
                    }
                    .buttonStyle(.plain)
                    .help(node.isCompleted ? "Mark incomplete" : "Mark complete")
                } else if let iconName = node.iconName, !isEditing {
                    Image(systemName: iconName)
                        .foregroundStyle(node.color)
                        .frame(width: 16)
                }

                if isEditing {
                    NodeTitleEditor(
                        text: $editingText,
                        fontSize: elevation.fontSize,
                        onSubmit: commitEditAndAddSibling,
                        onTab: commitEditAndAddChild,
                        onCancel: cancelEdit
                    )
                    .frame(
                        minWidth: isRootNode ? 96 : 72,
                        maxWidth: elevation.maxTextWidth,
                        minHeight: elevation.fontSize + 6
                    )
                } else {
                    Text(node.title.isEmpty ? "Untitled idea" : node.title)
                        .font(
                            .system(
                                size: elevation.fontSize,
                                weight: elevation.fontWeight,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            node.title.isEmpty
                                ? ColorTheme.textMuted
                                : ColorTheme.textPrimary
                        )
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        // A plain maxWidth frame would make the text claim the
                        // whole width even for a two-letter title, which padded
                        // short ideas into empty slabs. Measuring the string and
                        // taking the smaller of (its width, the ceiling) lets the
                        // card hug its content and still wrap long titles.
                        .frame(width: titleWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .strikethrough(node.isTask && node.isCompleted)
                }
            }

            if !isEditing && (
                !node.notes.isEmpty ||
                !node.tags.isEmpty ||
                node.link != nil ||
                !node.attachments.isEmpty
            ) {
                HStack(spacing: 8) {
                    if !node.notes.isEmpty {
                        Image(systemName: "note.text")
                            .help("Has notes")
                    }
                    if node.link != nil {
                        Image(systemName: "link")
                            .help("Has link")
                    }
                    if !node.tags.isEmpty {
                        Label("\(node.tags.count)", systemImage: "tag")
                            .labelStyle(.titleAndIcon)
                    }
                    if !node.attachments.isEmpty {
                        Label("\(node.attachments.count)", systemImage: "paperclip")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption)
                .foregroundStyle(ColorTheme.textMuted)
                .padding(.leading, isRootNode ? 15 : 14)
            }
        }
        .padding(.horizontal, elevation.horizontalPadding)
        .padding(.vertical, elevation.verticalPadding)
        .frame(minWidth: elevation.minWidth, alignment: .leading)
        .background(cardFill)
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(strokeColor, lineWidth: isSelected ? 2 : elevation.strokeWidth)
        }
        .overlay { focusRing }
        // Two shadows: a tight contact shadow that keeps the card anchored, and a
        // wide ambient one that carries the elevation. Splitting them is what
        // makes a root read as genuinely closer rather than just darker.
        .shadow(
            color: ColorTheme.shadow.opacity(isDragging ? 0.9 : elevation.shadowOpacity * 0.5),
            radius: isDragging ? 3 : 1.5,
            y: 1
        )
        .shadow(
            color: (isDragging ? ColorTheme.shadowLifted : ColorTheme.shadow)
                .opacity(isDragging ? 1 : elevation.shadowOpacity),
            radius: isDragging ? elevation.shadowRadius * 1.6 : elevation.shadowRadius,
            y: isDragging ? elevation.shadowOffsetY * 1.8 : elevation.shadowOffsetY
        )
        // Selection reads as a tight halo hugging the card. A wider glow made a
        // selected leaf out-shout its own root and inverted the hierarchy.
        .shadow(
            color: isSelected ? node.color.opacity(0.5) : .clear,
            radius: 5
        )
        .scaleEffect(cardScale)
        .animation(Motion.hover, value: isHovering)
        .animation(Motion.settle, value: isDragging)
        .animation(Motion.hover, value: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .onTapGesture(count: 2) {
            guard !isEditing else { return }
            startEditing()
        }
        .onTapGesture {
            guard !isEditing else { return }
            let cmdPressed = NSEvent.modifierFlags.contains(.command)
            handleNodeClick(cmdPressed)
        }
    }

    /// A wash of the node's hue over the card surface, strongest at the root.
    /// The gradient runs top-left to bottom-right so cards catch the same light
    /// as their shadows imply.
    private var cardFill: some View {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            .fill(ColorTheme.bgCard)
            .overlay {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                node.color.opacity(tintStrength),
                                node.color.opacity(tintStrength * 0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
    }

    private var tintStrength: Double {
        let base = elevation.tintOpacity
        if isSelected { return base * 1.8 }
        if isHovering { return base * 1.35 }
        return base
    }

    private var strokeColor: Color {
        if isSelected { return node.color }
        return node.color.opacity(
            isHovering ? elevation.strokeOpacity * 1.5 : elevation.strokeOpacity
        )
    }

    @ViewBuilder
    private var focusRing: some View {
        if (isFocused || isConnectionSource) && !isEditing && (!isSelected || isConnectionSource) {
            RoundedRectangle(cornerRadius: cardCornerRadius + 3, style: .continuous)
                .stroke(
                    isConnectionSource
                        ? ColorTheme.accentAI.opacity(0.9)
                        : ColorTheme.accentPrimary.opacity(0.5),
                    style: StrokeStyle(
                        lineWidth: 2,
                        dash: isConnectionSource ? [5, 3] : []
                    )
                )
                .padding(-4)
        }
    }

    private var cardScale: CGFloat {
        if isDragging { return 1.04 }
        if isHovering && !isEditing { return 1.015 }
        return 1
    }

    /// Width of the rendered title, capped at the wrap ceiling for this depth.
    private var titleWidth: CGFloat {
        let text = node.title.isEmpty ? "Untitled idea" : node.title
        let font = NSFont.systemFont(ofSize: elevation.fontSize, weight: .semibold)
        let rounded = font.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: elevation.fontSize) } ?? font
        let measured = (text as NSString)
            .size(withAttributes: [.font: rounded])
            .width
        // A single trailing point avoids the last glyph clipping on rounding.
        return min(ceil(measured) + 1, elevation.maxTextWidth)
    }

    private var elevation: NodeElevation {
        viewModel.elevation(of: node.id)
    }

    private var cardCornerRadius: CGFloat {
        elevation.cornerRadius
    }

    private func startEditing() {
        viewModel.editingNodeID = node.id
        prepareForEditing()
    }

    private func prepareForEditing() {
        editingText = node.title
    }

    private func commitEdit() {
        let trimmedText = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Update title (even if empty)
        viewModel.updateNodeTitle(nodeID: node.id, newTitle: trimmedText)
        viewModel.editingNodeID = nil
    }

    private func commitEditAndAddSibling() {
        commitEdit()
        viewModel.addSiblingToFocusedNode()
    }

    private func commitEditAndAddChild() {
        commitEdit()
        viewModel.addChildToFocusedNode()
    }

    private func cancelEdit() {
        editingText = node.title
        viewModel.editingNodeID = nil
    }

    private func handleNodeClick(_ cmdPressed: Bool) {
        if viewModel.connectionSourceNodeID != nil && !isConnectionSource {
            viewModel.completeAssociation(to: node.id)
        } else {
            viewModel.toggleNodeSelection(node.id, addToSelection: cmdPressed)
        }
    }

    private func prepareSelectionForContextAction() {
        if !viewModel.isNodeSelected(node.id) {
            viewModel.toggleNodeSelection(node.id, addToSelection: false)
        }
    }

    private func nodeAffordanceIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(node.color)
            .frame(width: 22, height: 22)
            .background(ColorTheme.bgCard, in: Circle())
            .overlay { Circle().fill(node.color.opacity(0.14)) }
            .overlay { Circle().stroke(node.color.opacity(0.45), lineWidth: 1) }
            .shadow(color: ColorTheme.shadow.opacity(0.6), radius: 4, y: 2)
    }

    private var accessibilityValue: String {
        var details: [String] = []
        if node.isTask {
            details.append(node.isCompleted ? "completed task" : "incomplete task")
        }
        if !node.notes.isEmpty { details.append("has notes") }
        if !node.tags.isEmpty { details.append("\(node.tags.count) tags") }
        if !node.attachments.isEmpty {
            details.append("\(node.attachments.count) attachments")
        }
        if node.isCollapsed { details.append("branch collapsed") }
        return details.isEmpty ? "idea" : details.joined(separator: ", ")
    }
}

/// A native single-line editor that keeps node creation under the user's hands.
///
/// NSTextField's command delegate lets Tab create a child instead of moving focus
/// away from the canvas, while Return commits and immediately starts a sibling.
private struct NodeTitleEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let onSubmit: () -> Void
    let onTab: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> AutoFocusTextField {
        let textField = AutoFocusTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = "Untitled idea"
        textField.stringValue = text
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.alignment = .left
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.textColor = .labelColor
        textField.font = Self.roundedFont(size: fontSize)

        return textField
    }

    func updateNSView(_ textField: AutoFocusTextField, context: Context) {
        context.coordinator.parent = self
        textField.font = Self.roundedFont(size: fontSize)
        if textField.stringValue != text {
            textField.stringValue = text
        }
    }

    private static func roundedFont(size: CGFloat) -> NSFont {
        let baseFont = NSFont.systemFont(ofSize: size, weight: .semibold)
        guard let descriptor = baseFont.fontDescriptor.withDesign(.rounded),
              let roundedFont = NSFont(descriptor: descriptor, size: size) else {
            return baseFont
        }
        return roundedFont
    }

    final class AutoFocusTextField: NSTextField {
        private var hasRequestedFocus = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !hasRequestedFocus else { return }
            hasRequestedFocus = true

            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
                self.selectText(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NodeTitleEditor

        init(_ parent: NodeTitleEditor) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                syncText(from: control)
                parent.onSubmit()
                return true
            case #selector(NSResponder.insertTab(_:)):
                syncText(from: control)
                parent.onTab()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        private func syncText(from control: NSControl) {
            guard let textField = control as? NSTextField else { return }
            parent.text = textField.stringValue
        }
    }
}
