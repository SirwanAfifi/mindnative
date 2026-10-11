import SwiftUI
import UniformTypeIdentifiers

// MARK: - Custom UTType

extension UTType {
    static var mindNativeDocument: UTType {
        UTType(exportedAs: "com.sirwanafifi.mindnative.document")
    }

    static var legacyMindNativeDocument: UTType {
        UTType(importedAs: "com.example.MindNative.document")
    }
}

/// Document model for MindNative mind maps
struct MindDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.mindNativeDocument, .legacyMindNativeDocument]
    }
    static var writableContentTypes: [UTType] { [.mindNativeDocument] }

    var nodes: [IdeaNode]
    var connections: [Connection]

    init(nodes: [IdeaNode] = [],
         connections: [Connection] = []) {
        self.nodes = nodes
        self.connections = connections
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MindDocumentData.self, from: data).validated()
        nodes = decoded.nodes
        connections = decoded.connections
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let validated = try MindDocumentData(
            nodes: nodes,
            connections: connections
        ).validated()
        let data = try encoder.encode(validated)
        return FileWrapper(regularFileWithContents: data)
    }
}

/// Codable wrapper for document data
struct MindDocumentData: Codable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var nodes: [IdeaNode]
    var connections: [Connection]

    init(
        schemaVersion: Int = MindDocumentData.currentSchemaVersion,
        nodes: [IdeaNode],
        connections: [Connection]
    ) {
        self.schemaVersion = schemaVersion
        self.nodes = nodes
        self.connections = connections
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, nodes, connections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        nodes = try container.decode([IdeaNode].self, forKey: .nodes)
        connections = try container.decodeIfPresent([Connection].self, forKey: .connections) ?? []
    }

    func validated() throws -> MindDocumentData {
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw MindDocumentError.unsupportedSchema(schemaVersion)
        }

        var repairedNodes = nodes
        let ids = repairedNodes.map(\.id)
        guard Set(ids).count == ids.count else {
            throw MindDocumentError.duplicateNodeIdentifiers
        }

        let validIDs = Set(ids)
        for index in repairedNodes.indices {
            if !repairedNodes[index].position.x.isFinite ||
                !repairedNodes[index].position.y.isFinite {
                repairedNodes[index].position = .zero
            }

            if let parentID = repairedNodes[index].parentID,
               parentID == repairedNodes[index].id || !validIDs.contains(parentID) {
                repairedNodes[index].parentID = nil
            }

            let attachmentBytes = repairedNodes[index].attachments.reduce(0) {
                $0 + $1.data.count
            }
            guard attachmentBytes <= 200 * 1_024 * 1_024 else {
                throw MindDocumentError.attachmentsTooLarge
            }
        }

        breakParentCycles(in: &repairedNodes)

        let nodeByID = Dictionary(uniqueKeysWithValues: repairedNodes.map { ($0.id, $0) })
        var existingHierarchy: [String: Connection] = [:]
        var repairedConnections: [Connection] = []
        var seenAssociations = Set<String>()

        for connection in connections {
            guard validIDs.contains(connection.fromNodeID),
                  validIDs.contains(connection.toNodeID),
                  connection.fromNodeID != connection.toNodeID else {
                continue
            }

            let key = Self.connectionKey(
                from: connection.fromNodeID,
                to: connection.toNodeID
            )
            if connection.kind == .hierarchy {
                existingHierarchy[key] = connection
            } else if seenAssociations.insert(key).inserted {
                repairedConnections.append(connection)
            }
        }

        for node in repairedNodes {
            guard let parentID = node.parentID else { continue }
            let key = Self.connectionKey(from: parentID, to: node.id)
            repairedConnections.append(
                existingHierarchy[key] ?? Connection(
                    from: parentID,
                    to: node.id,
                    color: nodeByID[node.id]?.color ?? node.color
                )
            )
        }

        return MindDocumentData(
            nodes: repairedNodes,
            connections: repairedConnections
        )
    }

    private func breakParentCycles(in nodes: inout [IdeaNode]) {
        var indexByID = Dictionary(
            uniqueKeysWithValues: nodes.indices.map { (nodes[$0].id, $0) }
        )

        for startIndex in nodes.indices {
            var visited = Set<UUID>()
            var currentID: UUID? = nodes[startIndex].id

            while let id = currentID, let index = indexByID[id] {
                guard visited.insert(id).inserted else {
                    nodes[startIndex].parentID = nil
                    indexByID[nodes[startIndex].id] = startIndex
                    break
                }
                currentID = nodes[index].parentID
            }
        }
    }

    private static func connectionKey(from: UUID, to: UUID) -> String {
        "\(from.uuidString)|\(to.uuidString)"
    }
}

enum MindDocumentError: LocalizedError {
    case unsupportedSchema(Int)
    case duplicateNodeIdentifiers
    case attachmentsTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "This mind map uses a newer document format (version \(version))."
        case .duplicateNodeIdentifiers:
            return "This mind map is damaged because two ideas share the same identifier."
        case .attachmentsTooLarge:
            return "One idea contains more than 200 MB of attachments."
        }
    }
}
