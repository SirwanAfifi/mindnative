import AppKit
import EventKit
import Foundation
import PDFKit

enum SystemIntegrationService {
    @MainActor
    static func addReminder(for node: IdeaNode) async throws {
        let store = EKEventStore()
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await store.requestFullAccessToReminders()
        } else {
            granted = try await requestLegacyAccess(to: .reminder, store: store)
        }
        guard granted else { throw SystemIntegrationError.permissionDenied("Reminders") }
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw SystemIntegrationError.noDefaultCalendar("Reminders")
        }

        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = node.title.nonEmpty ?? "MindNative idea"
        reminder.notes = integrationNotes(for: node)
        try store.save(reminder, commit: true)
    }

    @MainActor
    static func addCalendarEvent(for node: IdeaNode) async throws {
        let store = EKEventStore()
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await store.requestWriteOnlyAccessToEvents()
        } else {
            granted = try await requestLegacyAccess(to: .event, store: store)
        }
        guard granted else { throw SystemIntegrationError.permissionDenied("Calendar") }
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw SystemIntegrationError.noDefaultCalendar("Calendar")
        }

        let start = Calendar.current.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: Date().addingTimeInterval(86_400)
        ) ?? Date().addingTimeInterval(86_400)
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = node.title.nonEmpty ?? "MindNative idea"
        event.notes = integrationNotes(for: node)
        event.startDate = start
        event.endDate = start.addingTimeInterval(30 * 60)
        try store.save(event, span: .thisEvent, commit: true)
    }

    @MainActor
    static func shareMap(nodes: [IdeaNode], connections: [Connection]) throws {
        let data = try MindMapRenderer.pdfData(nodes: nodes, connections: connections)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindNative-\(UUID().uuidString).pdf")
        try data.write(to: url, options: .atomic)

        guard let view = NSApp.keyWindow?.contentView else {
            throw SystemIntegrationError.noWindow
        }
        NSSharingServicePicker(items: [url]).show(
            relativeTo: view.bounds,
            of: view,
            preferredEdge: .minY
        )
    }

    @MainActor
    static func printMap(nodes: [IdeaNode], connections: [Connection]) throws {
        let data = try MindMapRenderer.pdfData(nodes: nodes, connections: connections)
        guard let document = PDFDocument(data: data) else {
            throw SystemIntegrationError.invalidPDF
        }

        let pdfView = PDFView(
            frame: CGRect(x: 0, y: 0, width: 900, height: 700)
        )
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.print(with: NSPrintInfo.shared, autoRotate: true)
    }

    @MainActor
    private static func requestLegacyAccess(
        to type: EKEntityType,
        store: EKEventStore
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(to: type) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private static func integrationNotes(for node: IdeaNode) -> String {
        [node.notes, node.linkURL].compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

enum SystemIntegrationError: LocalizedError {
    case permissionDenied(String)
    case noDefaultCalendar(String)
    case noWindow
    case invalidPDF

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let app):
            return "\(app) permission was not granted."
        case .noDefaultCalendar(let app):
            return "No default \(app) list is configured."
        case .noWindow:
            return "No MindNative window is available for sharing."
        case .invalidPDF:
            return "The printable map could not be created."
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
