import AppKit
import Foundation
import UniformTypeIdentifiers

enum AttachmentService {
    @MainActor
    static func chooseAttachments() throws -> [IdeaAttachment] {
        let panel = NSOpenPanel()
        panel.title = "Attach Files"
        panel.prompt = "Attach"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.item]

        guard panel.runModal() == .OK else { return [] }
        return try panel.urls.map(IdeaAttachment.init(contentsOf:))
    }

    @MainActor
    static func open(_ attachment: IdeaAttachment) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindNativeAttachments", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = uniqueURL(for: attachment.name, in: directory)
        try attachment.data.write(to: url, options: .atomic)
        NSWorkspace.shared.open(url)
    }

    private static func uniqueURL(for name: String, in directory: URL) -> URL {
        let safeName = URL(fileURLWithPath: name).lastPathComponent
        let candidate = directory.appendingPathComponent(safeName)
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return candidate
        }
        return directory.appendingPathComponent(
            "\(UUID().uuidString)-\(safeName)"
        )
    }
}
