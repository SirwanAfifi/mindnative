import Foundation
import SwiftUI
import XCTest
@testable import MindNative

@MainActor
final class PhaseTwoFeatureTests: XCTestCase {
    func testSchemaV3RoundTripPreservesAttachmentsAndLinkPreview() throws {
        let attachment = IdeaAttachment(
            name: "brief.txt",
            typeIdentifier: "public.plain-text",
            data: Data("Launch brief".utf8),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let node = IdeaNode(
            title: "Launch",
            position: CGPoint(x: 10, y: 20),
            attachments: [attachment],
            linkTitle: "Launch plan",
            linkSummary: "The current launch plan."
        )
        let document = MindDocumentData(nodes: [node], connections: [])

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(MindDocumentData.self, from: data).validated()

        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertEqual(decoded.nodes.first?.attachments, [attachment])
        XCTAssertEqual(decoded.nodes.first?.linkTitle, "Launch plan")
        XCTAssertEqual(decoded.nodes.first?.linkSummary, "The current launch plan.")
    }

    func testXMindRoundTripProducesZipAndPreservesHierarchy() throws {
        let root = IdeaNode(
            title: "Product",
            position: .zero,
            notes: "Strategy",
            tags: ["north-star"]
        )
        let child = IdeaNode(
            title: "Launch",
            position: CGPoint(x: 200, y: 0),
            parentID: root.id,
            notes: "Ship deliberately",
            tags: ["delivery"]
        )

        let data = try InterchangeService.exportData(
            format: .xMind,
            nodes: [root, child],
            connections: [Connection(from: root.id, to: child.id, color: root.color)]
        )
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B])

        let imported = try InterchangeService.importData(data, format: .xMind)
        XCTAssertEqual(imported.nodes.count, 2)
        XCTAssertEqual(imported.nodes.first(where: { $0.parentID == nil })?.title, "Product")
        XCTAssertEqual(imported.nodes.first(where: { $0.parentID != nil })?.notes, "Ship deliberately")
        XCTAssertEqual(imported.connections.filter { $0.kind == .hierarchy }.count, 1)
    }

    func testRecoverySnapshotRoundTripUsesIsolatedStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindNativeRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = DocumentLifecycleService(
            recoveryRoot: root,
            sessionIdentifier: "phase-two-test"
        )
        let node = IdeaNode(title: "Recovered", position: CGPoint(x: 42, y: 84))

        service.saveRecovery(nodes: [node], connections: [])
        let restored = try service.restoreLatestRecovery()

        XCTAssertNotNil(service.latestRecoveryDate)
        XCTAssertEqual(restored.nodes.first?.id, node.id)
        XCTAssertEqual(restored.nodes.first?.title, node.title)
        XCTAssertEqual(restored.nodes.first?.position, node.position)
    }

    func testUndoRedoCoversRichNodeMutation() {
        let node = IdeaNode(title: "Draft", position: .zero)
        let viewModel = CanvasViewModel(nodes: [node], connections: [])
        let undo = UndoService()
        viewModel.undoService = undo

        var updated = node
        updated.notes = "A reviewable note"
        updated.isTask = true
        updated.attachments = [
            IdeaAttachment(
                name: "context.txt",
                typeIdentifier: "public.plain-text",
                data: Data("Context".utf8)
            )
        ]
        viewModel.updateNode(updated)

        XCTAssertTrue(undo.canUndo)
        XCTAssertEqual(viewModel.nodes.first?.notes, "A reviewable note")
        undo.undo()
        XCTAssertEqual(viewModel.nodes.first?.notes, "")
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        XCTAssertEqual(viewModel.nodes.first?.attachments.count, 1)
    }

    func testAllLayoutsHandleAThousandNodesWithFiniteCoordinates() {
        let root = IdeaNode(title: "Root", position: CGPoint(x: 500, y: 500))
        var nodes = [root]
        nodes.append(
            contentsOf: (0..<999).map { index in
                IdeaNode(
                    title: "Idea \(index)",
                    position: .zero,
                    parentID: root.id
                )
            }
        )

        for style in MindMapLayout.allCases {
            let positions = LayoutEngine.computeLayout(nodes: nodes, style: style)
            XCTAssertEqual(positions.count, nodes.count, "\(style) omitted nodes")
            XCTAssertTrue(
                positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite },
                "\(style) produced a non-finite coordinate"
            )
        }
    }

    func testSpatialIndexCullsLargeCanvas() {
        let nodes = (0..<10_000).map { index in
            IdeaNode(
                title: "Idea \(index)",
                position: CGPoint(
                    x: CGFloat(index % 100) * 300,
                    y: CGFloat(index / 100) * 220
                )
            )
        }
        var index = CanvasSpatialIndex()
        index.rebuild(nodes: nodes)

        let visible = index.identifiers(
            in: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            padding: 0
        )

        XCTAssertFalse(visible.isEmpty)
        XCTAssertLessThan(visible.count, 100)
    }

    func testImportParsersRejectOrSafelyHandleFuzzedInput() {
        for seed in 0..<64 {
            let length = 1 + (seed * 37) % 2_048
            let bytes = (0..<length).map { offset in
                UInt8((offset * 31 + seed * 17) % 256)
            }
            let data = Data(bytes)

            for format in MindMapImportFormat.allCases {
                do {
                    let document = try InterchangeService.importData(data, format: format)
                    XCTAssertFalse(document.nodes.isEmpty)
                } catch {
                    XCTAssertNotNil(error as Error)
                }
            }
        }
    }

    func testSpatialIndexBuildPerformanceAtTwentyThousandNodes() {
        let nodes = (0..<20_000).map { index in
            IdeaNode(
                title: "Idea \(index)",
                position: CGPoint(
                    x: CGFloat(index % 200) * 180,
                    y: CGFloat(index / 200) * 140
                )
            )
        }

        measure(metrics: [XCTClockMetric()]) {
            var index = CanvasSpatialIndex()
            index.rebuild(nodes: nodes)
            _ = index.identifiers(
                in: CGRect(x: 2_000, y: 2_000, width: 1_400, height: 900)
            )
        }
    }
}
