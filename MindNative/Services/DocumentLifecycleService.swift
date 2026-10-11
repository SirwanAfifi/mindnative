import CryptoKit
import Foundation

struct DocumentConflict: Identifiable, Equatable {
    let id: String
    let url: URL
    let modifiedAt: Date
    let displayName: String
}

private struct RecoverySnapshot: Codable {
    let savedAt: Date
    let document: MindDocumentData
}

@MainActor
final class DocumentLifecycleService: ObservableObject {
    @Published private(set) var conflicts: [DocumentConflict] = []
    @Published private(set) var latestRecoveryDate: Date?
    @Published private(set) var lastError: String?

    private var documentURL: URL?
    private let sessionIdentifier: String
    private let recoveryRoot: URL?
    private var recoveryTask: Task<Void, Never>?

    init(
        recoveryRoot: URL? = nil,
        sessionIdentifier: String = UUID().uuidString
    ) {
        self.recoveryRoot = recoveryRoot
        self.sessionIdentifier = sessionIdentifier
    }

    deinit {
        recoveryTask?.cancel()
    }

    func setDocumentURL(_ url: URL?) {
        guard documentURL != url else { return }
        documentURL = url
        refreshConflicts()
        latestRecoveryDate = loadLatestSnapshot()?.savedAt
    }

    func refreshConflicts() {
        guard let documentURL else {
            conflicts = []
            return
        }

        conflicts = (NSFileVersion.unresolvedConflictVersionsOfItem(at: documentURL) ?? [])
            .map {
                DocumentConflict(
                    id: "\($0.url.absoluteString)|\($0.modificationDate?.timeIntervalSince1970 ?? 0)",
                    url: $0.url,
                    modifiedAt: $0.modificationDate ?? .distantPast,
                    displayName: $0.localizedName ?? "Conflicting copy"
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func resolveKeepingCurrent() {
        guard let documentURL else { return }
        markConflictsResolved(at: documentURL)
        refreshConflicts()
    }

    func resolveUsingNewest() throws -> MindDocumentData {
        guard let newest = conflicts.first else {
            throw DocumentLifecycleError.noConflict
        }
        let data = try Data(contentsOf: newest.url)
        let document = try JSONDecoder().decode(MindDocumentData.self, from: data).validated()
        resolveKeepingCurrent()
        return document
    }

    func scheduleRecovery(nodes: [IdeaNode], connections: [Connection]) {
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.saveRecovery(nodes: nodes, connections: connections)
        }
    }

    func saveRecovery(nodes: [IdeaNode], connections: [Connection]) {
        do {
            let validated = try MindDocumentData(
                nodes: nodes,
                connections: connections
            ).validated()
            let snapshot = RecoverySnapshot(savedAt: Date(), document: validated)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)
            let url = try recoveryURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            latestRecoveryDate = snapshot.savedAt
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            Diagnostics.record(
                error,
                logger: Diagnostics.documents,
                operation: "Save recovery snapshot"
            )
        }
    }

    func restoreLatestRecovery() throws -> MindDocumentData {
        guard let snapshot = loadLatestSnapshot() else {
            throw DocumentLifecycleError.noRecoverySnapshot
        }
        return try snapshot.document.validated()
    }

    private func loadLatestSnapshot() -> RecoverySnapshot? {
        guard let url = try? recoveryURL(),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(RecoverySnapshot.self, from: data)
    }

    private func recoveryURL() throws -> URL {
        let base = try recoveryRoot ?? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let identity = documentURL?.standardizedFileURL.path ?? sessionIdentifier
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return base
            .appendingPathComponent("MindNative", isDirectory: true)
            .appendingPathComponent("Recovery", isDirectory: true)
            .appendingPathComponent("\(digest).recovery")
    }

    private func markConflictsResolved(at url: URL) {
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
            version.isResolved = true
        }
    }
}

enum DocumentLifecycleError: LocalizedError {
    case noConflict
    case noRecoverySnapshot

    var errorDescription: String? {
        switch self {
        case .noConflict:
            return "No unresolved document conflict is available."
        case .noRecoverySnapshot:
            return "No recovery snapshot is available for this document."
        }
    }
}
