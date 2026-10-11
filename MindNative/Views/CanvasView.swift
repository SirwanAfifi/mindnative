import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CanvasView: View {
    @Binding var document: MindDocument
    let fileURL: URL?
    @StateObject private var viewModel: CanvasViewModel
    @StateObject private var undoService = UndoService()
    @StateObject private var documentLifecycle = DocumentLifecycleService()
    @State private var clickLocation: CGPoint = .zero
    @FocusState private var canvasFocused: Bool
    @State private var selectionStart: CGPoint? = nil
    @State private var selectionCurrent: CGPoint? = nil
    @State private var isDraggingOnCanvas = false
    @State private var panStartOffset: CGSize? = nil
    @State private var zoomGestureStartScale: CGFloat? = nil
    @State private var isSpaceBarPressed = false
    @State private var didApplyInitialPreferences = false
    @AppStorage("defaultZoomLevel") private var defaultZoomLevel = 1.0
    @AppStorage("autoLayoutEnabled") private var autoLayoutEnabled = true
    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("gridSize") private var gridSize = 24.0

    init(document: Binding<MindDocument>, fileURL: URL? = nil) {
        self._document = document
        self.fileURL = fileURL
        self._viewModel = StateObject(wrappedValue: CanvasViewModel(
            nodes: document.wrappedValue.nodes,
            connections: document.wrappedValue.connections
        ))
    }

    var body: some View {
        editorWorkspace
            .navigationTitle("MindNative")
            .navigationSubtitle(documentSummary)
            .focusable()
            .focused($canvasFocused)
            .focusedSceneValue(\.canvasViewModel, viewModel)
            .focusedSceneValue(\.undoService, undoService)
            .onChange(of: viewModel.nodes) { newNodes in
                document.nodes = newNodes
                documentLifecycle.scheduleRecovery(
                    nodes: newNodes,
                    connections: viewModel.connections
                )
            }
            .onChange(of: viewModel.connections) { newConnections in
                document.connections = newConnections
                documentLifecycle.scheduleRecovery(
                    nodes: viewModel.nodes,
                    connections: newConnections
                )
            }
            .onAppear {
                canvasFocused = true
                viewModel.undoService = undoService
                viewModel.isAutoLayoutEnabled = autoLayoutEnabled
                if !didApplyInitialPreferences {
                    viewModel.zoomScale = CGFloat(defaultZoomLevel)
                    didApplyInitialPreferences = true
                }
                if viewModel.focusedNodeID == nil, !viewModel.nodes.isEmpty {
                    viewModel.focusFirstNode()
                }
                documentLifecycle.setDocumentURL(fileURL)
            }
            .onChange(of: fileURL) { documentLifecycle.setDocumentURL($0) }
            .onChange(of: autoLayoutEnabled) { newValue in
                viewModel.isAutoLayoutEnabled = newValue
            }
            .onChange(of: defaultZoomLevel) { newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.zoomScale = CGFloat(newValue)
                }
            }
            .onPasteCommand(of: [.image]) { providers in
                handleImagePaste(providers: providers)
            }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
                handleFileDrop(providers)
            }
            .onReceive(AppIntentRouter.shared.$pendingBrainstormPrompt.compactMap { $0 }) { prompt in
                AppIntentRouter.shared.pendingBrainstormPrompt = nil
                viewModel.generationPrompt = prompt
                viewModel.generationParentNodeID = nil
                viewModel.isGeneratingIdeas = true
            }
            .onDeleteCommand {
                guard viewModel.editingNodeID == nil,
                      !viewModel.isGeneratingIdeas else {
                    return
                }
                if !viewModel.selectedNodeIDs.isEmpty {
                    viewModel.deleteSelectedNodes()
                }
            }
            .onMoveCommand { direction in
                guard viewModel.editingNodeID == nil,
                      !viewModel.isGeneratingIdeas else {
                    return
                }
                switch direction {
                case .up:
                    viewModel.moveFocusInDirection(.up)
                case .down:
                    viewModel.moveFocusInDirection(.down)
                case .left:
                    viewModel.moveFocusInDirection(.left)
                case .right:
                    viewModel.moveFocusInDirection(.right)
                @unknown default:
                    break
                }
            }
            .toolbar {
                toolbarButtons
            }
    }

    private var editorWorkspace: some View {
        HStack(spacing: 0) {
            if viewModel.isNavigatorPresented {
                MapNavigatorView(viewModel: viewModel)
                Divider()
            }

            canvasContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if viewModel.isInspectorPresented {
                Divider()
                NodeInspectorView(viewModel: viewModel)
            }
        }
    }

    private var documentSummary: String {
        switch (viewModel.nodes.count, viewModel.connections.count) {
        case (0, _):
            return "Ready for your first idea"
        case (1, 0):
            return "1 idea"
        default:
            return "\(viewModel.nodes.count) ideas · \(viewModel.connections.count) connections"
        }
    }

    private var canvasContent: some View {
        GeometryReader { proxy in
            ZStack {
                KeyEventHandlingView(
                    isActive: viewModel.editingNodeID == nil && !viewModel.isGeneratingIdeas,
                    onKeyDown: handleKeyEvent,
                    onKeyUp: handleKeyUp
                )
                .frame(width: 0, height: 0)

                CanvasBackdrop(
                    showGrid: showGrid,
                    gridSize: CGFloat(gridSize),
                    zoomScale: viewModel.zoomScale,
                    canvasOffset: viewModel.canvasOffset
                )

                ZStack(alignment: .topLeading) {
                    canvasHitTarget
                    edgeLayer(viewportSize: proxy.size)
                    nodeLayer(viewportSize: proxy.size)
                }
                .coordinateSpace(name: "mindnative.canvas")
                .scaleEffect(viewModel.zoomScale, anchor: .topLeading)
                .offset(viewModel.canvasOffset)

                if let rect = viewModel.selectionRect {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(ColorTheme.accentPrimary.opacity(0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(
                                    ColorTheme.accentPrimary.opacity(0.85),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                                )
                        }
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                if viewModel.nodes.isEmpty {
                    CanvasWelcomeView(
                        onAddIdea: { viewModel.addRootNode() },
                        onBrainstorm: { viewModel.startIdeaGeneration() },
                        onTemplate: { viewModel.insertTemplate($0) }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if viewModel.isKeyboardHelpPresented {
                    KeyboardShortcutsOverlay {
                        viewModel.isKeyboardHelpPresented = false
                    }
                    .zIndex(20)
                }

                floatingControls
                    .allowsHitTesting(!viewModel.isGeneratingIdeas)

                if let notice = viewModel.notice {
                    VStack {
                        EditorNoticeBanner(notice: notice) {
                            viewModel.dismissNotice()
                        }
                        Spacer()
                    }
                    .padding(.top, 16)
                    .zIndex(15)
                }

                if viewModel.isGeneratingIdeas {
                    AIGenerationOverlay(viewModel: viewModel)
                        .zIndex(10)
                }

                if !documentLifecycle.conflicts.isEmpty {
                    VStack {
                        DocumentConflictBanner(
                            conflictCount: documentLifecycle.conflicts.count,
                            onUseNewest: resolveUsingNewestConflict,
                            onKeepCurrent: documentLifecycle.resolveKeepingCurrent
                        )
                        Spacer()
                    }
                    .padding(18)
                    .zIndex(30)
                }

                if viewModel.isPresentationMode,
                   let node = viewModel.currentPresentationNode {
                    PresentationOverlay(
                        node: node,
                        index: viewModel.presentationIndex,
                        total: viewModel.presentationNodeIDs.count,
                        onPrevious: viewModel.retreatPresentation,
                        onNext: viewModel.advancePresentation,
                        onClose: viewModel.endPresentation
                    )
                    .background(Color.black.opacity(0.28))
                    .zIndex(40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onAppear {
                viewModel.viewportSize = proxy.size
            }
            .onChange(of: proxy.size) { newSize in
                viewModel.viewportSize = newSize
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        if zoomGestureStartScale == nil {
                            zoomGestureStartScale = viewModel.zoomScale
                        }
                        let startScale = zoomGestureStartScale ?? viewModel.zoomScale
                        viewModel.zoomScale = min(max(startScale * value, 0.5), 3)
                    }
                    .onEnded { _ in
                        zoomGestureStartScale = nil
                    }
            )
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .modifiers(.option)
                    .onChanged { value in
                        updateCanvasPan(translation: value.translation)
                    }
                    .onEnded { _ in
                        panStartOffset = nil
                    }
            )
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        if isSpaceBarPressed {
                            updateCanvasPan(translation: value.translation)
                            return
                        }

                        if !isDraggingOnCanvas {
                            isDraggingOnCanvas = true
                            selectionStart = value.startLocation
                        }
                        selectionCurrent = value.location
                        updateSelectionRect()
                    }
                    .onEnded { _ in
                        if isSpaceBarPressed {
                            panStartOffset = nil
                        } else if let rect = viewModel.selectionRect {
                            let canvasRect = screenToCanvasRect(rect)
                            viewModel.selectNodesInRect(canvasRect)
                        }

                        isDraggingOnCanvas = false
                        selectionStart = nil
                        selectionCurrent = nil
                        viewModel.selectionRect = nil
                    }
            )
        }
    }

    /// Empty canvas area: clears selection on click and hosts the canvas menu.
    private var canvasHitTarget: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(
                    count: 2,
                    coordinateSpace: .named("mindnative.canvas")
                )
                .exclusively(
                    before: SpatialTapGesture(
                        count: 1,
                        coordinateSpace: .named("mindnative.canvas")
                    )
                )
                .onEnded { value in
                    switch value {
                    case .first(let doubleClick):
                        viewModel.addRootNode(at: doubleClick.location)
                    case .second:
                        viewModel.editingNodeID = nil
                        viewModel.clearSelection()
                    }
                }
            )
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    clickLocation = location
                }
            }
            .contextMenu {
                Button("New Main Idea") {
                    viewModel.addRootNode(at: clickLocation)
                }

                Button("Brainstorm with AI…") {
                    viewModel.startIdeaGeneration()
                }

                Button("Paste Here") {
                    viewModel.pasteNodes(at: clickLocation)
                }

                Divider()

                Button("Select All") {
                    viewModel.selectAllNodes()
                }

                Button("Auto Layout") {
                    viewModel.applyAutoLayout()
                }

                Button("Fit to Content") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.fitToContent()
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Mind map canvas")
            .accessibilityHint("Double-click an empty area to create a new idea.")
            .accessibilityIdentifier("mind-map-canvas")
    }

    private func edgeLayer(viewportSize: CGSize) -> some View {
        ForEach(viewModel.renderedConnections(in: visibleCanvasRect(viewportSize))) { connection in
            if let fromNode = viewModel.getNode(by: connection.fromNodeID),
               let toNode = viewModel.getNode(by: connection.toNodeID) {
                EdgeView(
                    from: viewModel.getRealTimePosition(
                        for: fromNode.id,
                        basePosition: fromNode.position
                    ),
                    to: viewModel.getRealTimePosition(
                        for: toNode.id,
                        basePosition: toNode.position
                    ),
                    color: connection.color,
                    elevation: viewModel.elevation(of: fromNode.id),
                    kind: connection.kind,
                    isHighlighted: viewModel.selectedNodeIDs.contains(fromNode.id)
                        || viewModel.selectedNodeIDs.contains(toNode.id)
                )
            }
        }
    }

    private func nodeLayer(viewportSize: CGSize) -> some View {
        ForEach(viewModel.renderedNodes(in: visibleCanvasRect(viewportSize))) { node in
            NodeView(
                node: node,
                viewModel: viewModel,
                isEditing: viewModel.editingNodeID == node.id,
                isSelected: viewModel.selectedNodeIDs.contains(node.id),
                isFocused: viewModel.focusedNodeID == node.id,
                isConnectionSource: viewModel.connectionSourceNodeID == node.id,
                dragOffset: viewModel.dragOffsets[node.id] ?? .zero
            )
            .equatable()
        }
    }

    /// Status and zoom controls pinned to the bottom of the canvas.
    private var floatingControls: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 12) {
                CanvasStatusPill(
                    nodeCount: viewModel.nodes.count,
                    selectedCount: viewModel.selectedNodeIDs.count,
                    onShowShortcuts: {
                        viewModel.isKeyboardHelpPresented = true
                    }
                )

                Spacer()

                if !viewModel.nodes.isEmpty {
                    MinimapView(viewModel: viewModel)
                }

                CanvasZoomControls(
                    zoomScale: viewModel.zoomScale,
                    onZoomOut: {
                        withAnimation(.easeOut(duration: 0.15)) { viewModel.zoomOut() }
                    },
                    onReset: {
                        withAnimation(.easeInOut(duration: 0.22)) { viewModel.fitToContent() }
                    },
                    onZoomIn: {
                        withAnimation(.easeOut(duration: 0.15)) { viewModel.zoomIn() }
                    }
                )
            }
            .padding(18)
        }
    }

    @ToolbarContentBuilder
    private var toolbarButtons: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                viewModel.isNavigatorPresented.toggle()
            } label: {
                Label("Navigator", systemImage: "sidebar.left")
            }
            .help("Show or hide the searchable map navigator")

            Button {
                viewModel.addRootNode()
            } label: {
                Label("New idea", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(ColorTheme.accentPrimary)
            .help("Add a main idea (N or ⌥↩)")

            Button {
                viewModel.startIdeaGeneration()
            } label: {
                Label("Brainstorm", systemImage: "sparkles")
            }
            .tint(ColorTheme.accentAI)
            .help("Brainstorm with on-device AI (⇧⌘G)")

            Menu {
                Menu("Start from Template") {
                    ForEach(MindMapTemplate.allCases) { template in
                        Button(template.title) {
                            viewModel.insertTemplate(template)
                        }
                    }
                }

                Divider()

                Button("Auto Layout") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.applyAutoLayout()
                    }
                }

                Menu("Layout") {
                    ForEach(MindMapLayout.allCases) { style in
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                viewModel.applyAutoLayout(style: style)
                            }
                        } label: {
                            Label(style.title, systemImage: style.systemImage)
                        }
                    }
                }

                Button("Start Presentation") {
                    viewModel.startPresentation()
                }

                Button("Fit to Content") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.fitToContent()
                    }
                }

                Divider()

                Toggle("Show Grid", isOn: $showGrid)
                Toggle("Show Inspector", isOn: $viewModel.isInspectorPresented)

                Divider()

                Button("Save Recovery Snapshot") {
                    documentLifecycle.saveRecovery(
                        nodes: viewModel.nodes,
                        connections: viewModel.connections
                    )
                }

                Button("Restore Latest Snapshot") {
                    restoreLatestRecovery()
                }
                .disabled(documentLifecycle.latestRecoveryDate == nil)
            } label: {
                Label("Canvas Options", systemImage: "slider.horizontal.3")
            }
            .help("Canvas options")

            Button {
                viewModel.editingNodeID = nil
                viewModel.isInspectorPresented.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Show or hide idea details")
        }
    }

    private func handleImagePaste(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        // Try loading as NSImage
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { image, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.viewModel.notice = EditorNotice(
                            kind: .error,
                            title: "Could not paste image",
                            message: error.localizedDescription
                        )
                        return
                    }

                    if let image = image as? NSImage {
                        let pastePosition = self.clickLocation.x > 0 && self.clickLocation.y > 0
                            ? self.clickLocation
                            : CGPoint(x: 400, y: 300)
                        self.viewModel.addRootNode(at: pastePosition, image: image)
                    }
                }
            }
        }
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        let providers = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !providers.isEmpty else { return false }

        for provider in providers {
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, error in
                guard error == nil else { return }
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }

                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                do {
                    let attachment = try IdeaAttachment(contentsOf: url)
                    DispatchQueue.main.async {
                        if let nodeID = viewModel.selectedNodeID {
                            viewModel.addAttachments([attachment], to: nodeID)
                        } else {
                            viewModel.addRootNode(
                                title: url.deletingPathExtension().lastPathComponent,
                                at: clickLocation
                            )
                            if let nodeID = viewModel.selectedNodeID {
                                viewModel.addAttachments([attachment], to: nodeID)
                            }
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        viewModel.notice = EditorNotice(
                            kind: .error,
                            title: "Could not attach file",
                            message: error.localizedDescription
                        )
                    }
                }
            }
        }
        return true
    }

    private func updateSelectionRect() {
        guard let start = selectionStart, let current = selectionCurrent else {
            viewModel.selectionRect = nil
            return
        }

        let minX = min(start.x, current.x)
        let minY = min(start.y, current.y)
        let maxX = max(start.x, current.x)
        let maxY = max(start.y, current.y)

        viewModel.selectionRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private func screenToCanvasRect(_ screenRect: CGRect) -> CGRect {
        // Transform screen coordinates to canvas coordinates
        // Account for zoom scale and pan offset
        let scale = viewModel.zoomScale
        let offset = viewModel.canvasOffset

        return CGRect(
            x: (screenRect.origin.x - offset.width) / scale,
            y: (screenRect.origin.y - offset.height) / scale,
            width: screenRect.width / scale,
            height: screenRect.height / scale
        )
    }

    private func visibleCanvasRect(_ viewportSize: CGSize) -> CGRect {
        screenToCanvasRect(CGRect(origin: .zero, size: viewportSize))
    }

    private func resolveUsingNewestConflict() {
        do {
            let beforeNodes = viewModel.nodes
            let beforeConnections = viewModel.connections
            let recovered = try documentLifecycle.resolveUsingNewest()
            viewModel.restoreCanvas(
                nodes: recovered.nodes,
                connections: recovered.connections
            )
            viewModel.registerChange(
                "Resolve Document Conflict",
                fromNodes: beforeNodes,
                fromConnections: beforeConnections
            )
        } catch {
            viewModel.notice = EditorNotice(
                kind: .error,
                title: "Could not resolve conflict",
                message: error.localizedDescription
            )
        }
    }

    private func restoreLatestRecovery() {
        do {
            let beforeNodes = viewModel.nodes
            let beforeConnections = viewModel.connections
            let recovered = try documentLifecycle.restoreLatestRecovery()
            viewModel.restoreCanvas(
                nodes: recovered.nodes,
                connections: recovered.connections
            )
            viewModel.registerChange(
                "Restore Recovery Snapshot",
                fromNodes: beforeNodes,
                fromConnections: beforeConnections
            )
            viewModel.notice = EditorNotice(
                kind: .success,
                title: "Snapshot restored",
                message: "The latest recovery snapshot is now open and can be undone."
            )
        } catch {
            viewModel.notice = EditorNotice(
                kind: .error,
                title: "Could not restore snapshot",
                message: error.localizedDescription
            )
        }
    }

    private func updateCanvasPan(translation: CGSize) {
        if panStartOffset == nil {
            panStartOffset = viewModel.canvasOffset
        }
        let startOffset = panStartOffset ?? viewModel.canvasOffset
        viewModel.canvasOffset = CGSize(
            width: startOffset.width + translation.width,
            height: startOffset.height + translation.height
        )
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
        let modifiers = event.modifierFlags.intersection(relevantModifiers)
        let keyCode = event.keyCode

        let isShortcutHelpKey = keyCode == 44 && (
            modifiers == .command ||
            modifiers == .shift ||
            modifiers == [.command, .shift]
        )
        if isShortcutHelpKey {
            viewModel.isKeyboardHelpPresented.toggle()
            return true
        }

        if viewModel.isKeyboardHelpPresented {
            if keyCode == 53 {
                viewModel.isKeyboardHelpPresented = false
            }
            return true
        }

        if viewModel.isPresentationMode {
            switch keyCode {
            case 53:
                viewModel.endPresentation()
            case 123, 126:
                viewModel.retreatPresentation()
            case 124, 125, 49:
                viewModel.advancePresentation()
            default:
                return false
            }
            return true
        }

        // Hold Space while dragging to pan the canvas.
        if keyCode == 49 && modifiers.isEmpty {
            isSpaceBarPressed = true
            NSCursor.openHand.set()
            return true
        }

        // Text fields and the AI prompt own their keyboard events.
        guard viewModel.editingNodeID == nil else { return false }

        switch keyCode {
        case 48: // Tab adds a child; Shift-Tab keeps backward navigation available.
            guard !modifiers.contains(.command),
                  !modifiers.contains(.control),
                  !modifiers.contains(.option) else {
                return false
            }
            if modifiers == .shift {
                viewModel.moveFocusToPreviousNode()
            } else {
                viewModel.addChildToFocusedNode()
            }
            return true

        case 36, 76: // Return / keypad Enter
            if modifiers.isEmpty {
                viewModel.addSiblingToFocusedNode()
            } else if modifiers == .command {
                viewModel.addChildToFocusedNode()
            } else if modifiers == .shift {
                viewModel.addSiblingToFocusedNode()
            } else if modifiers == .option {
                viewModel.addRootNode()
            } else {
                return false
            }
            return true

        case 120: // F2
            guard modifiers.isEmpty else { return false }
            viewModel.startEditingFocusedNode()
            return true

        case 51, 117: // Backspace / forward delete
            guard modifiers.isEmpty else { return false }
            if viewModel.selectedNodeIDs.isEmpty,
               let focusedNodeID = viewModel.focusedNodeID {
                viewModel.toggleNodeSelection(focusedNodeID, addToSelection: false)
            }
            viewModel.deleteSelectedNodes()
            return true

        case 53: // Escape
            viewModel.clearSelection()
            return true

        case 45: // N creates a main idea while the canvas owns focus.
            guard modifiers.isEmpty else { return false }
            viewModel.addRootNode()
            return true

        case 115: // Home
            guard modifiers == [] || modifiers == .shift else { return false }
            viewModel.focusFirstNode(extendingSelection: modifiers == .shift)
            return true

        case 119: // End
            guard modifiers == [] || modifiers == .shift else { return false }
            viewModel.focusLastNode(extendingSelection: modifiers == .shift)
            return true

        case 123, 124, 125, 126: // Arrow keys
            guard !modifiers.contains(.command),
                  !modifiers.contains(.control) else {
                return false
            }

            let direction: CanvasViewModel.MovementDirection
            switch keyCode {
            case 123:
                direction = .left
            case 124:
                direction = .right
            case 125:
                direction = .down
            default:
                direction = .up
            }

            if modifiers.contains(.option) {
                let distance = modifiers.contains(.shift)
                    ? max(CGFloat(gridSize), 1)
                    : 1
                viewModel.nudgeFocusedSelection(in: direction, distance: distance)
            } else {
                viewModel.moveFocusInDirection(
                    direction,
                    extendingSelection: modifiers.contains(.shift)
                )
            }
            return true

        default:
            return false
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        if event.keyCode == 49 {
            isSpaceBarPressed = false
            panStartOffset = nil
            NSCursor.arrow.set()
        }
    }
}

private struct CanvasBackdrop: View {
    let showGrid: Bool
    let gridSize: CGFloat
    let zoomScale: CGFloat
    let canvasOffset: CGSize

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ColorTheme.bgPage

                // A soft pool of light near the top of the canvas. It gives the
                // surface a direction to be lit from, which is what makes the
                // cards' shadows read as depth instead of decoration.
                RadialGradient(
                    colors: [
                        ColorTheme.accentPrimary.opacity(0.07),
                        Color.clear
                    ],
                    center: .init(x: 0.5, y: 0.28),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.75
                )

                if showGrid {
                    Canvas { context, size in
                        let spacing = max(gridSize * zoomScale, 12)
                        let startX = canvasOffset.width.truncatingRemainder(dividingBy: spacing)
                        let startY = canvasOffset.height.truncatingRemainder(dividingBy: spacing)
                        var path = Path()
                        let dotSize: CGFloat = zoomScale < 0.75 ? 1 : 1.5

                        for x in stride(from: startX, through: size.width, by: spacing) {
                            for y in stride(from: startY, through: size.height, by: spacing) {
                                path.addEllipse(
                                    in: CGRect(
                                        x: x - dotSize / 2,
                                        y: y - dotSize / 2,
                                        width: dotSize,
                                        height: dotSize
                                    )
                                )
                            }
                        }

                        context.fill(path, with: .color(ColorTheme.connectionLine.opacity(gridOpacity)))
                    }
                    .allowsHitTesting(false)
                }

                // Darkened edges keep attention in the middle of the map and stop
                // the canvas from reading as a flat sheet of color.
                RadialGradient(
                    colors: [
                        Color.clear,
                        ColorTheme.bgPageOuterFrame.opacity(0.5)
                    ],
                    center: .center,
                    startRadius: min(proxy.size.width, proxy.size.height) * 0.42,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.85
                )
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    /// The grid recedes as you zoom out, so a wide view shows the map rather
    /// than a field of dots.
    private var gridOpacity: Double {
        zoomScale < 0.6 ? 0.18 : (zoomScale < 1 ? 0.3 : 0.42)
    }
}

/// The empty state, built as a small live mind map rather than an icon.
///
/// Showing the thing the app makes — a root with two children at their real
/// elevations — teaches the depth language before the user creates anything,
/// and doubles as the page's signature moment.
private struct CanvasWelcomeView: View {
    let onAddIdea: () -> Void
    let onBrainstorm: () -> Void
    let onTemplate: (MindMapTemplate) -> Void

    @State private var hasAppeared = false

    // Children share the root's hue here for the same reason they do on the
    // canvas: a branch is one colour family.
    private let rootHue = ColorTheme.nodePalette[0]

    var body: some View {
        VStack(spacing: 30) {
            demonstration
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 8)

            VStack(spacing: 10) {
                Text("Every map starts as one idea")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(ColorTheme.textPrimary)

                Text("Name a thought, then branch it. Press Tab for a child, Return for a sibling.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(ColorTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            HStack(spacing: 10) {
                Button(action: onAddIdea) {
                    Label("New idea", systemImage: "plus")
                        .frame(minWidth: 106)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(ColorTheme.accentPrimary)
                .keyboardShortcut(.defaultAction)

                Button(action: onBrainstorm) {
                    Label("Brainstorm", systemImage: "sparkles")
                        .frame(minWidth: 106)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(ColorTheme.accentAI)

                Menu {
                    ForEach(MindMapTemplate.allCases) { template in
                        Button(template.title) {
                            onTemplate(template)
                        }
                    }
                } label: {
                    Label("Template", systemImage: "square.grid.2x2")
                        .frame(minWidth: 106)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 38)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(ColorTheme.glassStroke, lineWidth: 1)
                }
        }
        .shadow(color: ColorTheme.shadow, radius: 34, y: 16)
        .padding(28)
        .onAppear {
            withAnimation(Motion.chrome.delay(0.1)) { hasAppeared = true }
        }
    }

    /// A miniature of the real thing: one root, two children, drawn with the
    /// same tapering edges and elevation rules the canvas uses.
    private var demonstration: some View {
        HStack(spacing: 0) {
            miniCard("Idea", hue: rootHue, elevation: .root)

            MiniBranches(color: rootHue)
                .frame(width: 46, height: 62)

            VStack(alignment: .leading, spacing: 12) {
                miniCard("Branch", hue: rootHue, elevation: .branch)
                miniCard("Detail", hue: rootHue, elevation: .leaf)
            }
        }
    }

    private func miniCard(
        _ title: String,
        hue: Color,
        elevation: NodeElevation
    ) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(hue)
                .frame(width: 3, height: elevation == .root ? 18 : 13)

            Text(title)
                .font(
                    .system(
                        size: elevation == .root ? 14 : 11.5,
                        weight: elevation == .root ? .bold : .semibold,
                        design: .rounded
                    )
                )
                .foregroundStyle(ColorTheme.textPrimary)
        }
        .padding(.horizontal, elevation == .root ? 14 : 11)
        .padding(.vertical, elevation == .root ? 11 : 8)
        .background {
            RoundedRectangle(cornerRadius: elevation.cornerRadius, style: .continuous)
                .fill(ColorTheme.bgCard)
                .overlay {
                    RoundedRectangle(cornerRadius: elevation.cornerRadius, style: .continuous)
                        .fill(hue.opacity(elevation.tintOpacity))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: elevation.cornerRadius, style: .continuous)
                .stroke(hue.opacity(elevation.strokeOpacity), lineWidth: elevation.strokeWidth)
        }
        .shadow(
            color: ColorTheme.shadow.opacity(elevation.shadowOpacity),
            radius: elevation.shadowRadius * 0.7,
            y: elevation.shadowOffsetY * 0.7
        )
    }
}

/// The two curves joining the demo root to its children.
private struct MiniBranches: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let origin = CGPoint(x: 0, y: size.height / 2)
            for endY in [size.height * 0.16, size.height * 0.84] {
                let end = CGPoint(x: size.width, y: endY)
                var path = Path()
                path.move(to: origin)
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: origin.x + size.width * 0.55, y: origin.y),
                    control2: CGPoint(x: end.x - size.width * 0.55, y: end.y)
                )
                context.stroke(
                    path,
                    with: .color(color.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )
            }
        }
    }
}

private struct CanvasStatusPill: View {
    let nodeCount: Int
    let selectedCount: Int
    let onShowShortcuts: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ColorTheme.textSecondary)

            Divider()
                .frame(height: 14)

            Button(action: onShowShortcuts) {
                Image(systemName: "keyboard")
                    .font(.system(size: 12))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ColorTheme.textMuted)
            .help("Show keyboard shortcuts (⌘/ or ?)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .floatingChrome()
    }

    private var statusText: String {
        if selectedCount == 1 {
            return "1 idea selected"
        }
        if selectedCount > 1 {
            return "\(selectedCount) ideas selected"
        }
        if nodeCount == 0 {
            return "Blank canvas"
        }
        return "\(nodeCount) \(nodeCount == 1 ? "idea" : "ideas")"
    }
}

private struct KeyboardShortcutsOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            ColorTheme.overlayDim
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(ColorTheme.accentPrimary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keyboard shortcuts")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(ColorTheme.textPrimary)
                        Text("Stay in flow without reaching for the pointer.")
                            .font(.system(size: 12))
                            .foregroundStyle(ColorTheme.textSecondary)
                    }

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ColorTheme.textSecondary)
                    .help("Close (Esc)")
                }

                HStack(alignment: .top, spacing: 28) {
                    shortcutSection("Navigate", rows: [
                        ("Arrow keys", "Nearest idea"),
                        ("⇧ Arrow", "Extend selection"),
                        ("⇧ Tab", "Previous idea"),
                        ("Home / End", "First / last")
                    ])

                    shortcutSection("Create & edit", rows: [
                        ("Tab", "Add child"),
                        ("↩", "Add sibling"),
                        ("F2", "Rename"),
                        ("⌥ ↩ or N", "Add main idea"),
                        ("Delete", "Remove selection")
                    ])

                    shortcutSection("Canvas", rows: [
                        ("⌥ Arrow", "Nudge 1 point"),
                        ("⌥ ⇧ Arrow", "Nudge by grid"),
                        ("Space + drag", "Pan"),
                        ("⌘ + / −", "Zoom"),
                        ("⌥ ⌘ F", "Fit content")
                    ])
                }

                HStack {
                    Text("Tip: while typing, press Tab for a child or Return for a sibling.")
                        .font(.system(size: 11))
                        .foregroundStyle(ColorTheme.textMuted)
                    Spacer()
                    Text("⌘/ or ?")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ColorTheme.textSecondary)
                }
            }
            .padding(26)
            .frame(maxWidth: 720)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(ColorTheme.glassStroke, lineWidth: 1)
                    }
            }
            .shadow(color: ColorTheme.shadow, radius: 34, y: 16)
            .padding(28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func shortcutSection(
        _ title: String,
        rows: [(String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                Circle()
                    .fill(ColorTheme.accentPrimary.opacity(0.7))
                    .frame(width: 4, height: 4)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(ColorTheme.textMuted)
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    KeyCap(entry.element.0)
                    Text(entry.element.1)
                        .font(.system(size: 11))
                        .foregroundStyle(ColorTheme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A shortcut rendered as a key you could press.
private struct KeyCap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .foregroundStyle(ColorTheme.textPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(ColorTheme.bgCardSoft)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(ColorTheme.borderSubtle, lineWidth: 1)
                    }
            }
    }
}

private struct CanvasZoomControls: View {
    let zoomScale: CGFloat
    let onZoomOut: () -> Void
    let onReset: () -> Void
    let onZoomIn: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onZoomOut) {
                Image(systemName: "minus")
                    .frame(width: 24, height: 24)
            }
            .help("Zoom out (⌘−)")

            Button(action: onReset) {
                Text("\(Int((zoomScale * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .frame(width: 44)
            }
            .help("Fit to content")

            Button(action: onZoomIn) {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
            }
            .help("Zoom in (⌘+)")
        }
        .buttonStyle(.plain)
        .foregroundStyle(ColorTheme.textSecondary)
        .padding(5)
        .floatingChrome()
    }
}

/// Translucent panel styling for controls that hover over the canvas.
///
/// Using the material rather than a solid fill lets the map show through, which
/// keeps the controls feeling attached to the canvas instead of stacked on top
/// of it in a separate plane.
private struct FloatingChrome: ViewModifier {
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: shape)
            .overlay { shape.fill(ColorTheme.glassFill.opacity(0.18)) }
            .overlay { shape.stroke(ColorTheme.glassStroke, lineWidth: 1) }
            .clipShape(shape)
            .shadow(color: ColorTheme.shadow.opacity(0.7), radius: 12, y: 4)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

private struct EditorNoticeBanner: View {
    let notice: EditorNotice
    let onDismiss: () -> Void

    private var icon: String {
        switch notice.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch notice.kind {
        case .info: return .accentColor
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                Text(notice.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 12, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notice.title). \(notice.message)")
    }
}

private extension View {
    func floatingChrome(cornerRadius: CGFloat = 10) -> some View {
        modifier(FloatingChrome(cornerRadius: cornerRadius))
    }
}
