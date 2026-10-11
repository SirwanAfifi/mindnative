import SwiftUI

struct IdeaNode: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var position: CGPoint
    var color: Color
    var parentID: UUID?
    var image: NSImage?
    var notes: String
    var linkURL: String?
    var tags: [String]
    var isTask: Bool
    var isCompleted: Bool
    var iconName: String?
    var isCollapsed: Bool
    var attachments: [IdeaAttachment]
    var linkTitle: String?
    var linkSummary: String?

    init(
        id: UUID = UUID(),
        title: String,
        position: CGPoint,
        color: Color = .blue,
        parentID: UUID? = nil,
        image: NSImage? = nil,
        notes: String = "",
        linkURL: String? = nil,
        tags: [String] = [],
        isTask: Bool = false,
        isCompleted: Bool = false,
        iconName: String? = nil,
        isCollapsed: Bool = false,
        attachments: [IdeaAttachment] = [],
        linkTitle: String? = nil,
        linkSummary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.position = position
        self.color = color
        self.parentID = parentID
        self.image = image
        self.notes = notes
        self.linkURL = linkURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.tags = Self.normalizedTags(tags)
        self.isTask = isTask
        self.isCompleted = isTask && isCompleted
        self.iconName = iconName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.isCollapsed = isCollapsed
        self.attachments = attachments
        self.linkTitle = linkTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.linkSummary = linkSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    enum CodingKeys: String, CodingKey {
        case id, title, position, colorHex, parentID, imageData
        case notes, linkURL, tags, isTask, isCompleted, iconName, isCollapsed
        case attachments, linkTitle, linkSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        let positionData = try container.decode([String: CGFloat].self, forKey: .position)
        position = CGPoint(x: positionData["x"] ?? 0, y: positionData["y"] ?? 0)
        let colorHex = try container.decode(String.self, forKey: .colorHex)
        color = Color(hex: colorHex)
        parentID = try container.decodeIfPresent(UUID.self, forKey: .parentID)
        if let imageData = try container.decodeIfPresent(Data.self, forKey: .imageData) {
            image = NSImage(data: imageData)
        }
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        linkURL = try container.decodeIfPresent(String.self, forKey: .linkURL)?.nilIfEmpty
        tags = Self.normalizedTags(
            try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        )
        isTask = try container.decodeIfPresent(Bool.self, forKey: .isTask) ?? false
        let decodedCompletion =
            try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        isCompleted = isTask && decodedCompletion
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)?.nilIfEmpty
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        attachments = try container.decodeIfPresent([IdeaAttachment].self, forKey: .attachments) ?? []
        linkTitle = try container.decodeIfPresent(String.self, forKey: .linkTitle)?.nilIfEmpty
        linkSummary = try container.decodeIfPresent(String.self, forKey: .linkSummary)?.nilIfEmpty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(["x": position.x, "y": position.y], forKey: .position)
        try container.encode(color.toHex() ?? "#0000FF", forKey: .colorHex)
        try container.encodeIfPresent(parentID, forKey: .parentID)
        if let imageData = image?.mindNativePNGData {
            try container.encode(imageData, forKey: .imageData)
        }
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(linkURL, forKey: .linkURL)
        try container.encode(tags, forKey: .tags)
        try container.encode(isTask, forKey: .isTask)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encodeIfPresent(iconName, forKey: .iconName)
        try container.encode(isCollapsed, forKey: .isCollapsed)
        try container.encode(attachments, forKey: .attachments)
        try container.encodeIfPresent(linkTitle, forKey: .linkTitle)
        try container.encodeIfPresent(linkSummary, forKey: .linkSummary)
    }

    static func == (lhs: IdeaNode, rhs: IdeaNode) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.position == rhs.position &&
        lhs.color == rhs.color &&
        lhs.parentID == rhs.parentID &&
        lhs.notes == rhs.notes &&
        lhs.linkURL == rhs.linkURL &&
        lhs.tags == rhs.tags &&
        lhs.isTask == rhs.isTask &&
        lhs.isCompleted == rhs.isCompleted &&
        lhs.iconName == rhs.iconName &&
        lhs.isCollapsed == rhs.isCollapsed &&
        lhs.attachments == rhs.attachments &&
        lhs.linkTitle == rhs.linkTitle &&
        lhs.linkSummary == rhs.linkSummary &&
        imagesAreEqual(lhs.image, rhs.image)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var link: URL? {
        guard let linkURL else { return nil }
        return URL(string: linkURL)
    }

    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { rawTag in
            let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { return nil }
            let key = tag.localizedLowercase
            guard seen.insert(key).inserted else { return nil }
            return tag
        }
    }

    private static func imagesAreEqual(_ lhs: NSImage?, _ rhs: NSImage?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.isEqual(rhs)
        default:
            return false
        }
    }
}

private extension NSImage {
    var mindNativePNGData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
