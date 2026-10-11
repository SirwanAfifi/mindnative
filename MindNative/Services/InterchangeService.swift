import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

enum MindMapExportFormat: String, CaseIterable, Identifiable {
    case png
    case pdf
    case svg
    case markdown
    case opml
    case freeMind
    case xMind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: return "PNG Image"
        case .pdf: return "PDF Document"
        case .svg: return "SVG Image"
        case .markdown: return "Markdown"
        case .opml: return "OPML"
        case .freeMind: return "FreeMind"
        case .xMind: return "XMind"
        }
    }

    var filenameExtension: String {
        switch self {
        case .png: return "png"
        case .pdf: return "pdf"
        case .svg: return "svg"
        case .markdown: return "md"
        case .opml: return "opml"
        case .freeMind: return "mm"
        case .xMind: return "xmind"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .pdf: return .pdf
        case .svg: return .svg
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .opml: return UTType(filenameExtension: "opml") ?? .xml
        case .freeMind: return UTType(filenameExtension: "mm") ?? .xml
        case .xMind: return UTType(filenameExtension: "xmind") ?? .data
        }
    }

    var pasteboardType: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(contentType.identifier)
    }

    var canAlsoCopyAsPlainText: Bool {
        switch self {
        case .svg, .markdown, .opml, .freeMind:
            return true
        case .png, .pdf, .xMind:
            return false
        }
    }
}

enum MindMapImportFormat: String, CaseIterable, Identifiable {
    case markdown
    case opml
    case freeMind
    case xMind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: return "Markdown"
        case .opml: return "OPML"
        case .freeMind: return "FreeMind"
        case .xMind: return "XMind"
        }
    }

    var contentTypes: [UTType] {
        switch self {
        case .markdown:
            return [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        case .opml:
            return [UTType(filenameExtension: "opml") ?? .xml]
        case .freeMind:
            return [UTType(filenameExtension: "mm") ?? .xml]
        case .xMind:
            return [UTType(filenameExtension: "xmind") ?? .data, .zip]
        }
    }
}

enum InterchangeError: LocalizedError {
    case noIdeas
    case couldNotRender
    case unsupportedFile
    case emptyImport

    var errorDescription: String? {
        switch self {
        case .noIdeas:
            return "Add at least one idea before exporting."
        case .couldNotRender:
            return "MindNative could not render this map."
        case .unsupportedFile:
            return "The selected file is not a supported mind-map format."
        case .emptyImport:
            return "The selected file did not contain any ideas."
        }
    }
}

enum InterchangeService {
    @MainActor
    static func export(
        format: MindMapExportFormat,
        nodes: [IdeaNode],
        connections: [Connection],
        suggestedName: String = "Mind Map"
    ) throws -> Bool {
        guard !nodes.isEmpty else { throw InterchangeError.noIdeas }

        let panel = NSSavePanel()
        panel.title = "Export \(format.title)"
        panel.nameFieldStringValue = "\(suggestedName).\(format.filenameExtension)"
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        let data = try exportData(
            format: format,
            nodes: nodes,
            connections: connections
        )
        try data.write(to: url, options: .atomic)
        return true
    }

    @MainActor
    static func importDocument(format: MindMapImportFormat) throws -> MindDocumentData? {
        let panel = NSOpenPanel()
        panel.title = "Import \(format.title)"
        panel.allowedContentTypes = format.contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let data = try Data(contentsOf: url)
        return try importData(data, format: format)
    }

    static func importData(
        _ data: Data,
        format: MindMapImportFormat
    ) throws -> MindDocumentData {
        let imported: MindDocumentData
        switch format {
        case .markdown:
            guard let string = String(data: data, encoding: .utf8) else {
                throw InterchangeError.unsupportedFile
            }
            imported = MarkdownMindMapParser.parse(string)
        case .opml:
            imported = try XMLMindMapParser.parseOPML(data)
        case .freeMind:
            imported = try XMLMindMapParser.parseFreeMind(data)
        case .xMind:
            imported = try XMindArchive.importDocument(data)
        }
        guard !imported.nodes.isEmpty else { throw InterchangeError.emptyImport }
        return try imported.validated()
    }

    static func exportData(
        format: MindMapExportFormat,
        nodes: [IdeaNode],
        connections: [Connection]
    ) throws -> Data {
        switch format {
        case .png:
            guard let data = MindMapRenderer.pngData(
                nodes: nodes,
                connections: connections
            ) else {
                throw InterchangeError.couldNotRender
            }
            return data
        case .pdf:
            return try MindMapRenderer.pdfData(
                nodes: nodes,
                connections: connections
            )
        case .svg:
            return Data(
                MindMapTextExporter.svg(nodes: nodes, connections: connections).utf8
            )
        case .markdown:
            return Data(MindMapTextExporter.markdown(nodes: nodes).utf8)
        case .opml:
            return Data(MindMapTextExporter.opml(nodes: nodes).utf8)
        case .freeMind:
            return Data(MindMapTextExporter.freeMind(nodes: nodes).utf8)
        case .xMind:
            return try XMindArchive.export(nodes: nodes)
        }
    }
}

enum XMindArchive {
    static func export(nodes: [IdeaNode]) throws -> Data {
        let children = Dictionary(grouping: nodes.compactMap { node in
            node.parentID.map { ($0, node) }
        }, by: { $0.0 }).mapValues { $0.map { $0.1 } }

        func topic(_ node: IdeaNode) -> XMindTopic {
            let childTopics = (children[node.id] ?? []).map(topic)
            return XMindTopic(
                id: node.id.uuidString,
                className: "topic",
                title: node.title.isEmpty ? "Untitled idea" : node.title,
                labels: node.tags,
                notes: node.notes.isEmpty
                    ? nil
                    : XMindNotes(plain: XMindPlainNotes(content: node.notes)),
                children: childTopics.isEmpty
                    ? nil
                    : XMindChildren(attached: childTopics)
            )
        }

        let roots = nodes.filter { $0.parentID == nil }
        let sheets = roots.map { root in
            XMindSheet(
                id: UUID().uuidString,
                className: "sheet",
                title: root.title.isEmpty ? "MindNative Map" : root.title,
                rootTopic: topic(root)
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let content = try encoder.encode(sheets)
        let metadata = Data(
            #"{"creator":{"name":"MindNative","version":"1.0"}}"#.utf8
        )
        let manifest = Data(
            #"{"file-entries":{"content.json":{},"metadata.json":{}}}"#.utf8
        )

        let archive = try Archive(accessMode: .create)
        try add(content, path: "content.json", to: archive)
        try add(metadata, path: "metadata.json", to: archive)
        try add(manifest, path: "manifest.json", to: archive)
        guard let data = archive.data else {
            throw InterchangeError.couldNotRender
        }
        return data
    }

    static func importDocument(_ data: Data) throws -> MindDocumentData {
        let archive = try Archive(data: data, accessMode: .read)
        guard let entry = archive["content.json"] else {
            throw InterchangeError.unsupportedFile
        }
        var content = Data()
        _ = try archive.extract(entry) { content.append($0) }
        let sheets = try JSONDecoder().decode([XMindSheet].self, from: content)

        var nodes: [IdeaNode] = []
        var connections: [Connection] = []
        var row = 0

        func append(_ topic: XMindTopic, parent: IdeaNode?, depth: Int, rootIndex: Int) {
            let color = parent?.color ?? ColorTheme.nodePalette[
                rootIndex % ColorTheme.nodePalette.count
            ]
            let node = IdeaNode(
                id: UUID(uuidString: topic.id) ?? UUID(),
                title: topic.title,
                position: CGPoint(
                    x: 240 + CGFloat(depth) * 260,
                    y: 160 + CGFloat(row) * 100
                ),
                color: color,
                parentID: parent?.id,
                notes: topic.notes?.plain?.content ?? "",
                tags: topic.labels ?? []
            )
            nodes.append(node)
            if let parent {
                connections.append(
                    Connection(from: parent.id, to: node.id, color: color)
                )
            }
            row += 1
            for child in topic.children?.attached ?? [] {
                append(child, parent: node, depth: depth + 1, rootIndex: rootIndex)
            }
        }

        for (index, sheet) in sheets.enumerated() {
            append(sheet.rootTopic, parent: nil, depth: 0, rootIndex: index)
        }
        return MindDocumentData(nodes: nodes, connections: connections)
    }

    private static func add(_ data: Data, path: String, to archive: Archive) throws {
        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .deflate
        ) { position, size in
            let lower = Int(position)
            return data.subdata(in: lower..<(lower + size))
        }
    }
}

private struct XMindSheet: Codable {
    let id: String
    let className: String
    let title: String
    let rootTopic: XMindTopic

    enum CodingKeys: String, CodingKey {
        case id
        case className = "class"
        case title
        case rootTopic
    }
}

private struct XMindTopic: Codable {
    let id: String
    let className: String
    let title: String
    let labels: [String]?
    let notes: XMindNotes?
    let children: XMindChildren?

    enum CodingKeys: String, CodingKey {
        case id
        case className = "class"
        case title, labels, notes, children
    }
}

private struct XMindChildren: Codable {
    let attached: [XMindTopic]
}

private struct XMindNotes: Codable {
    let plain: XMindPlainNotes?
}

private struct XMindPlainNotes: Codable {
    let content: String
}

enum MindMapTextExporter {
    static func markdown(nodes: [IdeaNode]) -> String {
        let children = childrenIndex(nodes)
        let roots = nodes.filter { $0.parentID == nil }
        var lines = ["<!-- Exported from MindNative -->", ""]

        func appendNode(_ node: IdeaNode, depth: Int) {
            let taskPrefix = node.isTask ? (node.isCompleted ? "[x] " : "[ ] ") : ""
            lines.append("\(String(repeating: "#", count: max(depth + 1, 1))) \(taskPrefix)\(displayTitle(node))")
            if !node.notes.isEmpty {
                lines.append("")
                lines.append(node.notes)
            }
            if let linkURL = node.linkURL {
                lines.append("")
                lines.append("Link: \(linkURL)")
            }
            if !node.tags.isEmpty {
                lines.append("")
                lines.append("Tags: \(node.tags.map { "#\($0)" }.joined(separator: " "))")
            }
            lines.append("")
            for child in children[node.id] ?? [] {
                appendNode(child, depth: depth + 1)
            }
        }

        for root in roots {
            appendNode(root, depth: 0)
        }
        return lines.joined(separator: "\n")
    }

    static func opml(nodes: [IdeaNode]) -> String {
        let children = childrenIndex(nodes)
        let roots = nodes.filter { $0.parentID == nil }

        func outline(_ node: IdeaNode, indent: Int) -> String {
            let attributes = richXMLAttributes(node)
            let prefix = String(repeating: "  ", count: indent)
            let childXML = (children[node.id] ?? []).map {
                outline($0, indent: indent + 1)
            }
            if childXML.isEmpty {
                return "\(prefix)<outline text=\"\(xmlEscape(displayTitle(node)))\"\(attributes)/>"
            }
            return """
            \(prefix)<outline text="\(xmlEscape(displayTitle(node)))"\(attributes)>
            \(childXML.joined(separator: "\n"))
            \(prefix)</outline>
            """
        }

        let body = roots.map { outline($0, indent: 3) }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>MindNative Export</title></head>
          <body>
        \(body)
          </body>
        </opml>
        """
    }

    static func freeMind(nodes: [IdeaNode]) -> String {
        let children = childrenIndex(nodes)
        let roots = nodes.filter { $0.parentID == nil }

        func element(_ node: IdeaNode, indent: Int) -> String {
            let prefix = String(repeating: "  ", count: indent)
            let childXML = (children[node.id] ?? []).map {
                element($0, indent: indent + 1)
            }
            let attributes = richXMLAttributes(node)
            if childXML.isEmpty {
                return "\(prefix)<node TEXT=\"\(xmlEscape(displayTitle(node)))\"\(attributes)/>"
            }
            return """
            \(prefix)<node TEXT="\(xmlEscape(displayTitle(node)))"\(attributes)>
            \(childXML.joined(separator: "\n"))
            \(prefix)</node>
            """
        }

        let body = roots.map { element($0, indent: 1) }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <map version="1.0.1">
        \(body)
        </map>
        """
    }

    static func svg(nodes: [IdeaNode], connections: [Connection]) -> String {
        let bounds = MindMapRenderer.contentBounds(nodes: nodes)
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        let position: (CGPoint) -> CGPoint = { point in
            CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
        }
        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var elements: [String] = []

        for connection in connections {
            guard let from = nodeByID[connection.fromNodeID],
                  let to = nodeByID[connection.toNodeID] else {
                continue
            }
            let a = position(from.position)
            let b = position(to.position)
            let dash = connection.kind == .association ? " stroke-dasharray=\"7 5\"" : ""
            elements.append(
                "<path d=\"M \(a.x) \(a.y) C \((a.x + b.x) / 2) \(a.y), \((a.x + b.x) / 2) \(b.y), \(b.x) \(b.y)\" fill=\"none\" stroke=\"\(colorHex(connection.color))\" stroke-width=\"3\"\(dash)/>"
            )
        }

        for node in nodes {
            let point = position(node.position)
            let title = xmlEscape(displayTitle(node))
            let fill = colorHex(node.color)
            elements.append(
                "<rect x=\"\(point.x - 90)\" y=\"\(point.y - 28)\" width=\"180\" height=\"56\" rx=\"14\" fill=\"#171827\" stroke=\"\(fill)\" stroke-width=\"2\"/>"
            )
            elements.append(
                "<text x=\"\(point.x)\" y=\"\(point.y + 5)\" text-anchor=\"middle\" fill=\"#F5F4FF\" font-family=\"-apple-system, sans-serif\" font-size=\"15\" font-weight=\"600\">\(title)</text>"
            )
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
          <rect width="100%" height="100%" fill="#0D1020"/>
          \(elements.joined(separator: "\n  "))
        </svg>
        """
    }

    private static func childrenIndex(_ nodes: [IdeaNode]) -> [UUID: [IdeaNode]] {
        Dictionary(grouping: nodes.compactMap { node -> (UUID, IdeaNode)? in
            guard let parentID = node.parentID else { return nil }
            return (parentID, node)
        }, by: \.0).mapValues { $0.map(\.1) }
    }

    private static func richXMLAttributes(_ node: IdeaNode) -> String {
        var attributes: [String] = []
        if !node.notes.isEmpty {
            attributes.append("note=\"\(xmlEscape(node.notes))\"")
        }
        if let linkURL = node.linkURL {
            attributes.append("link=\"\(xmlEscape(linkURL))\"")
        }
        if !node.tags.isEmpty {
            attributes.append("tags=\"\(xmlEscape(node.tags.joined(separator: ",")))\"")
        }
        if node.isTask {
            attributes.append("task=\"true\"")
            attributes.append("completed=\"\(node.isCompleted)\"")
        }
        return attributes.isEmpty ? "" : " " + attributes.joined(separator: " ")
    }

    private static func displayTitle(_ node: IdeaNode) -> String {
        node.title.isEmpty ? "Untitled idea" : node.title
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func colorHex(_ color: Color) -> String {
        color.toHex() ?? "#7C6CFF"
    }
}

enum MindMapRenderer {
    static func contentBounds(nodes: [IdeaNode]) -> CGRect {
        guard let first = nodes.first else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        var bounds = CGRect(
            x: first.position.x,
            y: first.position.y,
            width: 0,
            height: 0
        )
        for node in nodes.dropFirst() {
            bounds = bounds.union(
                CGRect(x: node.position.x, y: node.position.y, width: 0, height: 0)
            )
        }
        return bounds.insetBy(dx: -150, dy: -110)
    }

    static func pngData(nodes: [IdeaNode], connections: [Connection]) -> Data? {
        let image = renderImage(nodes: nodes, connections: connections)
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return representation.representation(using: .png, properties: [:])
    }

    static func pdfData(nodes: [IdeaNode], connections: [Connection]) throws -> Data {
        let bounds = contentBounds(nodes: nodes)
        let view = MindMapExportView(
            frame: CGRect(origin: .zero, size: bounds.size),
            nodes: nodes,
            connections: connections,
            mapBounds: bounds
        )
        let data = view.dataWithPDF(inside: view.bounds)
        guard !data.isEmpty else { throw InterchangeError.couldNotRender }
        return data
    }

    private static func renderImage(
        nodes: [IdeaNode],
        connections: [Connection]
    ) -> NSImage {
        let bounds = contentBounds(nodes: nodes)
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        draw(
            nodes: nodes,
            connections: connections,
            mapBounds: bounds,
            outputBounds: CGRect(origin: .zero, size: bounds.size)
        )
        image.unlockFocus()
        return image
    }

    fileprivate static func draw(
        nodes: [IdeaNode],
        connections: [Connection],
        mapBounds: CGRect,
        outputBounds: CGRect
    ) {
        NSColor(red: 0.05, green: 0.06, blue: 0.12, alpha: 1).setFill()
        outputBounds.fill()

        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let transform: (CGPoint) -> CGPoint = { point in
            CGPoint(
                x: point.x - mapBounds.minX,
                y: outputBounds.height - (point.y - mapBounds.minY)
            )
        }

        for connection in connections {
            guard let from = nodeByID[connection.fromNodeID],
                  let to = nodeByID[connection.toNodeID] else {
                continue
            }
            let a = transform(from.position)
            let b = transform(to.position)
            let path = NSBezierPath()
            path.move(to: a)
            path.curve(
                to: b,
                controlPoint1: CGPoint(x: (a.x + b.x) / 2, y: a.y),
                controlPoint2: CGPoint(x: (a.x + b.x) / 2, y: b.y)
            )
            path.lineWidth = connection.kind == .association ? 2 : 3
            if connection.kind == .association {
                path.setLineDash([7, 5], count: 2, phase: 0)
            }
            (NSColor(connection.color).usingColorSpace(.deviceRGB) ?? .systemPurple)
                .withAlphaComponent(0.85)
                .setStroke()
            path.stroke()
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]

        for node in nodes {
            let point = transform(node.position)
            let rect = CGRect(x: point.x - 90, y: point.y - 28, width: 180, height: 56)
            let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
            NSColor(red: 0.09, green: 0.09, blue: 0.15, alpha: 1).setFill()
            path.fill()
            (NSColor(node.color).usingColorSpace(.deviceRGB) ?? .systemPurple).setStroke()
            path.lineWidth = 2
            path.stroke()

            let title = node.title.isEmpty ? "Untitled idea" : node.title
            title.draw(
                in: rect.insetBy(dx: 10, dy: 17),
                withAttributes: textAttributes
            )
        }
    }
}

private final class MindMapExportView: NSView {
    let nodes: [IdeaNode]
    let connections: [Connection]
    let mapBounds: CGRect

    init(
        frame: CGRect,
        nodes: [IdeaNode],
        connections: [Connection],
        mapBounds: CGRect
    ) {
        self.nodes = nodes
        self.connections = connections
        self.mapBounds = mapBounds
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        MindMapRenderer.draw(
            nodes: nodes,
            connections: connections,
            mapBounds: mapBounds,
            outputBounds: bounds
        )
    }
}

enum MarkdownMindMapParser {
    static func parse(_ source: String) -> MindDocumentData {
        var nodes: [IdeaNode] = []
        var connections: [Connection] = []
        var nodeAtDepth: [Int: IdeaNode] = [:]
        var row = 0
        var lastNodeIndex: Int?

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("<!--") else { continue }

            if line.hasPrefix("#") {
                let hashes = line.prefix { $0 == "#" }.count
                var title = line.dropFirst(hashes)
                    .trimmingCharacters(in: .whitespaces)
                let taskState: Bool?
                if title.hasPrefix("[x] ") || title.hasPrefix("[X] ") {
                    taskState = true
                    title = String(title.dropFirst(4))
                } else if title.hasPrefix("[ ] ") {
                    taskState = false
                    title = String(title.dropFirst(4))
                } else {
                    taskState = nil
                }

                let depth = max(hashes - 1, 0)
                let parent = nodeAtDepth[depth - 1]
                let color = parent?.color ?? ColorTheme.nodePalette[
                    nodes.filter { $0.parentID == nil }.count % ColorTheme.nodePalette.count
                ]
                let node = IdeaNode(
                    title: title,
                    position: CGPoint(x: 220 + CGFloat(depth) * 260, y: 160 + CGFloat(row) * 100),
                    color: color,
                    parentID: parent?.id,
                    isTask: taskState != nil,
                    isCompleted: taskState ?? false
                )
                nodes.append(node)
                if let parent {
                    connections.append(
                        Connection(from: parent.id, to: node.id, color: color)
                    )
                }
                nodeAtDepth[depth] = node
                nodeAtDepth = nodeAtDepth.filter { $0.key <= depth }
                lastNodeIndex = nodes.count - 1
                row += 1
            } else if let lastNodeIndex {
                if line.hasPrefix("Link: ") {
                    nodes[lastNodeIndex].linkURL = String(line.dropFirst(6))
                } else if line.hasPrefix("Tags: ") {
                    nodes[lastNodeIndex].tags = line.dropFirst(6)
                        .split(separator: " ")
                        .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
                } else {
                    if !nodes[lastNodeIndex].notes.isEmpty {
                        nodes[lastNodeIndex].notes += "\n"
                    }
                    nodes[lastNodeIndex].notes += line
                }
            }
        }

        return MindDocumentData(nodes: nodes, connections: connections)
    }
}

enum XMLMindMapParser {
    static func parseOPML(_ data: Data) throws -> MindDocumentData {
        try parse(data, mode: .opml)
    }

    static func parseFreeMind(_ data: Data) throws -> MindDocumentData {
        try parse(data, mode: .freeMind)
    }

    private enum Mode {
        case opml
        case freeMind
    }

    private static func parse(_ data: Data, mode: Mode) throws -> MindDocumentData {
        let delegate = XMLTreeDelegate(mode: mode == .opml ? .opml : .freeMind)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? InterchangeError.unsupportedFile
        }
        return MindDocumentData(nodes: delegate.nodes, connections: delegate.connections)
    }
}

private final class XMLTreeDelegate: NSObject, XMLParserDelegate {
    enum Mode {
        case opml
        case freeMind
    }

    let mode: Mode
    var nodes: [IdeaNode] = []
    var connections: [Connection] = []
    private var parentStack: [IdeaNode] = []
    private var row = 0

    init(mode: Mode) {
        self.mode = mode
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let isNode = mode == .opml ? elementName == "outline" : elementName == "node"
        guard isNode else { return }
        let titleKey = mode == .opml ? "text" : "TEXT"
        let title = attributeDict[titleKey] ?? "Untitled idea"
        let parent = parentStack.last
        let depth = parentStack.count
        let color = parent?.color ?? ColorTheme.nodePalette[
            nodes.filter { $0.parentID == nil }.count % ColorTheme.nodePalette.count
        ]
        let node = IdeaNode(
            title: title,
            position: CGPoint(x: 220 + CGFloat(depth) * 260, y: 160 + CGFloat(row) * 100),
            color: color,
            parentID: parent?.id,
            notes: attributeDict["note"] ?? "",
            linkURL: attributeDict["link"],
            tags: attributeDict["tags"]?.split(separator: ",").map(String.init) ?? [],
            isTask: attributeDict["task"] == "true",
            isCompleted: attributeDict["completed"] == "true"
        )
        nodes.append(node)
        if let parent {
            connections.append(
                Connection(from: parent.id, to: node.id, color: color)
            )
        }
        parentStack.append(node)
        row += 1
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let isNode = mode == .opml ? elementName == "outline" : elementName == "node"
        if isNode, !parentStack.isEmpty {
            parentStack.removeLast()
        }
    }
}
