import AppKit
import SwiftUI
import XCTest
@testable import MindNative

final class DocumentModelTests: XCTestCase {
    func testLegacyDocumentWithoutSchemaVersionMigrates() throws {
        let root = IdeaNode(title: "Root", position: CGPoint(x: 10, y: 20))
        let encoded = try JSONEncoder().encode(
            MindDocumentData(nodes: [root], connections: [])
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "schemaVersion")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(MindDocumentData.self, from: legacyData)
        let validated = try decoded.validated()

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(validated.schemaVersion, MindDocumentData.currentSchemaVersion)
        XCTAssertEqual(validated.nodes.first?.title, "Root")
    }

    func testValidationRepairsCyclesAndRebuildsHierarchyEdges() throws {
        let firstID = UUID()
        let secondID = UUID()
        let first = IdeaNode(
            id: firstID,
            title: "First",
            position: .zero,
            parentID: secondID
        )
        let second = IdeaNode(
            id: secondID,
            title: "Second",
            position: CGPoint(x: 100, y: 0),
            parentID: firstID
        )

        let validated = try MindDocumentData(
            nodes: [first, second],
            connections: []
        ).validated()

        XCTAssertTrue(validated.nodes.contains { $0.parentID == nil })
        XCTAssertEqual(
            validated.connections.filter { $0.kind == .hierarchy }.count,
            validated.nodes.filter { $0.parentID != nil }.count
        )
    }

    func testValidationRejectsDuplicateNodeIdentifiers() {
        let id = UUID()
        let first = IdeaNode(id: id, title: "One", position: .zero)
        let duplicate = IdeaNode(id: id, title: "Two", position: CGPoint(x: 1, y: 1))

        XCTAssertThrowsError(
            try MindDocumentData(nodes: [first, duplicate], connections: []).validated()
        )
    }

    func testRichNodeRoundTripUsesPortableImageData() throws {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemPurple.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 8, height: 8)).fill()
        image.unlockFocus()

        let node = IdeaNode(
            title: "Ship",
            position: CGPoint(x: 1, y: 2),
            image: image,
            notes: "A useful note",
            linkURL: "https://example.com",
            tags: ["launch", "urgent"],
            isTask: true,
            isCompleted: true,
            iconName: "flag",
            isCollapsed: true
        )

        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(IdeaNode.self, from: data)

        XCTAssertEqual(decoded.title, node.title)
        XCTAssertEqual(decoded.notes, node.notes)
        XCTAssertEqual(decoded.tags, node.tags)
        XCTAssertEqual(decoded.link, URL(string: "https://example.com"))
        XCTAssertTrue(decoded.isCompleted)
        XCTAssertNotNil(decoded.image)
    }
}
