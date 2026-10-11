import AppKit
import Foundation

struct CanvasClipboardPayload: Codable {
    let schemaVersion: Int
    let nodes: [IdeaNode]
    let connections: [Connection]

    init(nodes: [IdeaNode], connections: [Connection]) {
        schemaVersion = MindDocumentData.currentSchemaVersion
        self.nodes = nodes
        self.connections = connections
    }
}

enum CanvasClipboardError: LocalizedError {
    case couldNotWrite

    var errorDescription: String? {
        "MindNative could not write the requested format to the clipboard."
    }
}

enum CanvasClipboard {
    static let pasteboardType = NSPasteboard.PasteboardType(
        "com.sirwanafifi.mindnative.nodes"
    )

    static func write(
        nodes: [IdeaNode],
        connections: [Connection],
        to pasteboard: NSPasteboard = .general
    ) throws {
        let payload = CanvasClipboardPayload(nodes: nodes, connections: connections)
        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        let plainText = nodes
            .map { $0.title.isEmpty ? "Untitled idea" : $0.title }
            .joined(separator: "\n")

        pasteboard.clearContents()
        pasteboard.declareTypes([pasteboardType, .string], owner: nil)
        pasteboard.setData(data, forType: pasteboardType)
        pasteboard.setString(plainText, forType: .string)
    }

    static func write(
        exportData: Data,
        format: MindMapExportFormat,
        to pasteboard: NSPasteboard = .general
    ) throws {
        var types = [format.pasteboardType]
        let plainText = format.canAlsoCopyAsPlainText
            ? String(data: exportData, encoding: .utf8)
            : nil

        if plainText != nil, format.pasteboardType != .string {
            types.append(.string)
        }

        pasteboard.clearContents()
        pasteboard.declareTypes(types, owner: nil)

        guard pasteboard.setData(exportData, forType: format.pasteboardType) else {
            throw CanvasClipboardError.couldNotWrite
        }
        if let plainText,
           !pasteboard.setString(plainText, forType: .string) {
            throw CanvasClipboardError.couldNotWrite
        }
    }

    static func read(
        from pasteboard: NSPasteboard = .general
    ) throws -> CanvasClipboardPayload? {
        guard let data = pasteboard.data(forType: pasteboardType) else {
            return nil
        }
        return try JSONDecoder().decode(CanvasClipboardPayload.self, from: data)
    }

    static var containsIdeas: Bool {
        containsIdeas(in: .general)
    }

    static func containsIdeas(in pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [pasteboardType]) != nil
    }
}
