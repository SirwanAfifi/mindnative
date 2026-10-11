import SwiftUI

enum ConnectionKind: String, Codable, CaseIterable {
    case hierarchy
    case association
}

struct Connection: Identifiable, Codable, Equatable {
    let id: UUID
    let fromNodeID: UUID
    let toNodeID: UUID
    var color: Color
    var kind: ConnectionKind
    var label: String?

    init(
        id: UUID = UUID(),
        from: UUID,
        to: UUID,
        color: Color,
        kind: ConnectionKind = .hierarchy,
        label: String? = nil
    ) {
        self.id = id
        self.fromNodeID = from
        self.toNodeID = to
        self.color = color
        self.kind = kind
        self.label = label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func == (lhs: Connection, rhs: Connection) -> Bool {
        lhs.id == rhs.id &&
        lhs.fromNodeID == rhs.fromNodeID &&
        lhs.toNodeID == rhs.toNodeID &&
        lhs.color == rhs.color &&
        lhs.kind == rhs.kind &&
        lhs.label == rhs.label
    }

    enum CodingKeys: String, CodingKey {
        case id, fromNodeID, toNodeID, colorHex, kind, label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fromNodeID = try container.decode(UUID.self, forKey: .fromNodeID)
        toNodeID = try container.decode(UUID.self, forKey: .toNodeID)
        let colorHex = try container.decode(String.self, forKey: .colorHex)
        color = Color(hex: colorHex)
        kind = try container.decodeIfPresent(ConnectionKind.self, forKey: .kind) ?? .hierarchy
        label = try container.decodeIfPresent(String.self, forKey: .label)?.nilIfEmpty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fromNodeID, forKey: .fromNodeID)
        try container.encode(toNodeID, forKey: .toNodeID)
        try container.encode(color.toHex() ?? "#0000FF", forKey: .colorHex)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(label, forKey: .label)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
