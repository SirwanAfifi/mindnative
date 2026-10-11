import AppIntents
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppIntentRouter: ObservableObject {
    static let shared = AppIntentRouter()

    @Published var pendingBrainstormPrompt: String?

    private init() {}
}

struct CreateMindMapIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Mind Map"
    static let description = IntentDescription(
        "Create a portable MindNative document from a topic."
    )

    @Parameter(title: "Topic")
    var topic: String

    static var parameterSummary: some ParameterSummary {
        Summary("Create a mind map about \(\.$topic)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let cleanTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = IdeaNode(
            title: cleanTopic.isEmpty ? "New mind map" : cleanTopic,
            position: CGPoint(x: 360, y: 300),
            color: ColorTheme.nodePalette.first ?? .blue
        )
        let starterTitles = [
            "Goals",
            "Key Ideas",
            "Next Steps",
            "Questions"
        ]
        var nodes = [root]
        var connections: [Connection] = []

        for (index, title) in starterTitles.enumerated() {
            let child = IdeaNode(
                title: title,
                position: CGPoint(x: 650, y: 135 + CGFloat(index) * 115),
                color: root.color,
                parentID: root.id
            )
            nodes.append(child)
            connections.append(
                Connection(from: root.id, to: child.id, color: root.color)
            )
        }

        let document = try MindDocumentData(
            nodes: nodes,
            connections: connections
        ).validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        let safeName = cleanTopic
            .replacingOccurrences(
                of: #"[^A-Za-z0-9 -]"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(60)
        let filename = safeName.isEmpty ? "Mind Map" : String(safeName)
        let file = IntentFile(
            data: data,
            filename: "\(filename).mindnative",
            type: .mindNativeDocument
        )
        return .result(value: file, dialog: "Created \(filename).")
    }
}

struct OpenBrainstormIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Brainstorming"
    static let description = IntentDescription(
        "Open MindNative ready to brainstorm a topic."
    )
    static let openAppWhenRun = true

    @Parameter(title: "Topic")
    var topic: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Start brainstorming \(\.$topic)")
    }

    func perform() async throws -> some IntentResult {
        let prompt = topic?.trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run {
            AppIntentRouter.shared.pendingBrainstormPrompt = prompt
        }
        return .result()
    }
}

struct ExportOutlineIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Mind Map Outline"
    static let description = IntentDescription(
        "Convert a MindNative document into a Markdown outline."
    )

    @Parameter(
        title: "Mind Map",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var document: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Export \(\.$document) as a Markdown outline")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        let decoded = try JSONDecoder()
            .decode(MindDocumentData.self, from: document.data)
            .validated()
        let markdown = MindMapTextExporter.markdown(nodes: decoded.nodes)
        let file = IntentFile(
            data: Data(markdown.utf8),
            filename: "\(document.filename.deletingPathExtension).md",
            type: UTType(filenameExtension: "md") ?? .plainText
        )
        return .result(value: file, dialog: "Exported the Markdown outline.")
    }
}

struct MindNativeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateMindMapIntent(),
            phrases: [
                "Create a mind map with \(.applicationName)",
                "Make a map in \(.applicationName)"
            ],
            shortTitle: "Create Mind Map",
            systemImageName: "point.3.connected.trianglepath.dotted"
        )

        AppShortcut(
            intent: OpenBrainstormIntent(),
            phrases: [
                "Brainstorm with \(.applicationName)",
                "Start brainstorming in \(.applicationName)"
            ],
            shortTitle: "Start Brainstorming",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: ExportOutlineIntent(),
            phrases: [
                "Export an outline with \(.applicationName)"
            ],
            shortTitle: "Export Outline",
            systemImageName: "list.bullet.indent"
        )
    }
}

private extension String {
    var deletingPathExtension: String {
        (self as NSString).deletingPathExtension
    }
}
