import AppKit
import Foundation
import UniformTypeIdentifiers

struct IdeaAttachment: Identifiable, Hashable, Codable {
    static let maximumFileSize = 50 * 1_024 * 1_024

    var id: UUID
    var name: String
    var typeIdentifier: String
    var data: Data
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        typeIdentifier: String,
        data: Data,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.typeIdentifier = typeIdentifier
        self.data = data
        self.createdAt = createdAt
    }

    init(contentsOf url: URL) throws {
        let values = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        let fileSize = values.fileSize ?? 0
        guard fileSize <= Self.maximumFileSize else {
            throw IdeaAttachmentError.fileTooLarge(url.lastPathComponent)
        }

        self.init(
            name: url.lastPathComponent,
            typeIdentifier: values.contentType?.identifier ?? UTType.data.identifier,
            data: try Data(contentsOf: url, options: .mappedIfSafe)
        )
    }

    var contentType: UTType {
        UTType(typeIdentifier) ?? .data
    }

    var image: NSImage? {
        contentType.conforms(to: .image) ? NSImage(data: data) : nil
    }

    var systemImageName: String {
        if contentType.conforms(to: .image) { return "photo" }
        if contentType.conforms(to: .pdf) { return "doc.richtext" }
        if contentType.conforms(to: .plainText) { return "doc.text" }
        if contentType.conforms(to: .audio) { return "waveform" }
        if contentType.conforms(to: .movie) { return "film" }
        return "paperclip"
    }
}

enum IdeaAttachmentError: LocalizedError {
    case fileTooLarge(String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let name):
            return "\(name) is larger than the 50 MB attachment limit."
        }
    }
}
