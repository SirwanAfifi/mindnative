import SwiftUI
import XCTest
@testable import MindNative

final class InterchangeServiceTests: XCTestCase {
    func testMarkdownExportAndImportPreserveHierarchyAndRichText() throws {
        let root = IdeaNode(
            title: "Product",
            position: CGPoint(x: 100, y: 100),
            notes: "The big picture",
            tags: ["strategy"]
        )
        let child = IdeaNode(
            title: "Launch",
            position: CGPoint(x: 300, y: 100),
            color: root.color,
            parentID: root.id,
            linkURL: "https://example.com/launch",
            tags: ["go-to-market"],
            isTask: true
        )
        let connection = Connection(from: root.id, to: child.id, color: root.color)

        let exported = try InterchangeService.exportData(
            format: .markdown,
            nodes: [root, child],
            connections: [connection]
        )
        let markdown = try XCTUnwrap(String(data: exported, encoding: .utf8))

        XCTAssertTrue(markdown.contains("# Product"))
        XCTAssertTrue(markdown.contains("The big picture"))
        XCTAssertTrue(markdown.contains("[ ] Launch"))
        XCTAssertTrue(markdown.contains("#strategy"))

        let imported = try InterchangeService.importData(exported, format: .markdown)
        XCTAssertEqual(imported.nodes.count, 2)
        XCTAssertEqual(imported.connections.filter { $0.kind == .hierarchy }.count, 1)
    }

    func testStandardExportSignatures() throws {
        let node = IdeaNode(title: "Root", position: CGPoint(x: 100, y: 100))

        let png = try InterchangeService.exportData(
            format: .png,
            nodes: [node],
            connections: []
        )
        let pdf = try InterchangeService.exportData(
            format: .pdf,
            nodes: [node],
            connections: []
        )
        let svg = try InterchangeService.exportData(
            format: .svg,
            nodes: [node],
            connections: []
        )
        let opml = try InterchangeService.exportData(
            format: .opml,
            nodes: [node],
            connections: []
        )

        XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(String(data: pdf.prefix(4), encoding: .ascii), "%PDF")
        XCTAssertTrue(String(decoding: svg, as: UTF8.self).contains("<svg"))
        XCTAssertTrue(String(decoding: opml, as: UTF8.self).contains("<opml"))
    }
}
