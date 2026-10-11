import AppKit
import SwiftUI
import XCTest
@testable import MindNative

@MainActor
final class CanvasViewModelTests: XCTestCase {
    func testCollapsedBranchHidesDescendantsAndTheirConnections() {
        let graph = makeGraph()
        let viewModel = CanvasViewModel(
            nodes: graph.nodes,
            connections: graph.connections
        )

        viewModel.toggleCollapsed(nodeID: graph.child.id)

        XCTAssertEqual(Set(viewModel.visibleNodes.map(\.id)), [graph.root.id, graph.child.id])
        XCTAssertEqual(viewModel.visibleConnections.count, 1)
    }

    func testReparentRepairsHierarchyAndPreventsCycles() {
        let graph = makeGraph()
        let viewModel = CanvasViewModel(
            nodes: graph.nodes,
            connections: graph.connections
        )

        viewModel.reparentNode(graph.child.id, to: nil)
        XCTAssertNil(viewModel.getNode(by: graph.child.id)?.parentID)
        XCTAssertFalse(
            viewModel.connections.contains {
                $0.kind == .hierarchy && $0.toNodeID == graph.child.id
            }
        )

        viewModel.reparentNode(graph.child.id, to: graph.grandchild.id)
        XCTAssertNil(viewModel.getNode(by: graph.child.id)?.parentID)
        XCTAssertEqual(viewModel.notice?.kind, .error)
    }

    func testAssociationIsDistinctFromHierarchy() {
        let graph = makeGraph()
        let viewModel = CanvasViewModel(
            nodes: graph.nodes,
            connections: graph.connections
        )

        viewModel.createAssociation(from: graph.root.id, to: graph.grandchild.id)

        XCTAssertTrue(
            viewModel.connections.contains {
                $0.fromNodeID == graph.root.id &&
                $0.toNodeID == graph.grandchild.id &&
                $0.kind == .association
            }
        )
        XCTAssertEqual(viewModel.getNode(by: graph.grandchild.id)?.parentID, graph.child.id)
    }

    func testTemplateCreatesRichStructuredMap() {
        let viewModel = CanvasViewModel()

        viewModel.insertTemplate(.projectPlan)

        XCTAssertEqual(viewModel.nodes.count, 6)
        XCTAssertEqual(viewModel.connections.count, 5)
        XCTAssertTrue(viewModel.nodes.contains { $0.isTask })
        XCTAssertTrue(viewModel.nodes.contains { !$0.tags.isEmpty })
        XCTAssertTrue(viewModel.nodes.contains { $0.iconName != nil })
    }

    func testCutAndPastePreserveTheWholeSelectedBranch() throws {
        let graph = makeGraph()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.clearContents() }
        let viewModel = CanvasViewModel(
            nodes: graph.nodes,
            connections: graph.connections,
            pasteboard: pasteboard
        )
        viewModel.selectedNodeIDs = [graph.child.id]

        viewModel.cutSelectedNodes()

        XCTAssertEqual(viewModel.nodes.map(\.id), [graph.root.id])
        let payload = try XCTUnwrap(CanvasClipboard.read(from: pasteboard))
        XCTAssertEqual(Set(payload.nodes.map(\.id)), [graph.child.id, graph.grandchild.id])
        XCTAssertEqual(payload.connections.count, 1)

        viewModel.pasteNodes(at: CGPoint(x: 500, y: 300))

        XCTAssertEqual(viewModel.nodes.count, 3)
        XCTAssertEqual(viewModel.selectedNodeIDs.count, 2)
        let pasted = viewModel.nodes.filter { viewModel.selectedNodeIDs.contains($0.id) }
        XCTAssertEqual(pasted.filter { $0.parentID != nil }.count, 1)
        XCTAssertEqual(
            viewModel.connections.filter { $0.kind == .hierarchy }.count,
            1
        )
    }

    func testCopySelectedBranchAsPNGPDFOrSVG() throws {
        let graph = makeGraph()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.clearContents() }
        let viewModel = CanvasViewModel(
            nodes: graph.nodes,
            connections: graph.connections,
            pasteboard: pasteboard
        )
        viewModel.selectedNodeIDs = [graph.child.id]

        viewModel.copySelectedNodes(as: .png)
        let png = try XCTUnwrap(pasteboard.data(forType: MindMapExportFormat.png.pasteboardType))
        XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])

        viewModel.copySelectedNodes(as: .pdf)
        let pdf = try XCTUnwrap(pasteboard.data(forType: MindMapExportFormat.pdf.pasteboardType))
        XCTAssertEqual(String(data: pdf.prefix(4), encoding: .ascii), "%PDF")

        viewModel.copySelectedNodes(as: .svg)
        let svgData = try XCTUnwrap(
            pasteboard.data(forType: MindMapExportFormat.svg.pasteboardType)
        )
        let svg = String(decoding: svgData, as: UTF8.self)
        XCTAssertTrue(svg.contains("<svg"))
        XCTAssertTrue(svg.contains(">Child</text>"))
        XCTAssertTrue(svg.contains(">Grandchild</text>"))
        XCTAssertFalse(svg.contains(">Root</text>"))
    }

    func testCopySelectedBranchAsMarkdownPromotesSelectionToRoot() throws {
        let graph = makeGraph()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.clearContents() }
        let viewModel = CanvasViewModel(
            nodes: graph.nodes,
            connections: graph.connections,
            pasteboard: pasteboard
        )
        viewModel.selectedNodeIDs = [graph.child.id]

        viewModel.copySelectedNodes(as: .markdown)

        let markdown = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertTrue(markdown.contains("# Child"))
        XCTAssertTrue(markdown.contains("## Grandchild"))
        XCTAssertFalse(markdown.contains("# Root"))
    }

    func testCopySelectedBranchSupportsEveryExportFormat() throws {
        let graph = makeGraph()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.clearContents() }
        let viewModel = CanvasViewModel(
            nodes: graph.nodes,
            connections: graph.connections,
            pasteboard: pasteboard
        )
        viewModel.selectedNodeIDs = [graph.child.id]

        for format in MindMapExportFormat.allCases {
            viewModel.copySelectedNodes(as: format)

            let data = try XCTUnwrap(
                pasteboard.data(forType: format.pasteboardType),
                "Expected clipboard data for \(format.title)"
            )
            XCTAssertFalse(data.isEmpty, "Expected non-empty \(format.title) data")
        }
    }

    private func makeGraph() -> (
        root: IdeaNode,
        child: IdeaNode,
        grandchild: IdeaNode,
        nodes: [IdeaNode],
        connections: [Connection]
    ) {
        let root = IdeaNode(title: "Root", position: CGPoint(x: 0, y: 0))
        let child = IdeaNode(
            title: "Child",
            position: CGPoint(x: 200, y: 0),
            color: root.color,
            parentID: root.id
        )
        let grandchild = IdeaNode(
            title: "Grandchild",
            position: CGPoint(x: 400, y: 0),
            color: root.color,
            parentID: child.id
        )
        return (
            root,
            child,
            grandchild,
            [root, child, grandchild],
            [
                Connection(from: root.id, to: child.id, color: root.color),
                Connection(from: child.id, to: grandchild.id, color: root.color)
            ]
        )
    }
}
