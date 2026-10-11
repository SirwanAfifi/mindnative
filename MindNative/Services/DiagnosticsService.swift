import Foundation
import OSLog

enum Diagnostics {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.sirwanafifi.MindNative"

    static let documents = Logger(subsystem: subsystem, category: "documents")
    static let interchange = Logger(subsystem: subsystem, category: "interchange")
    static let integrations = Logger(subsystem: subsystem, category: "integrations")
    static let updates = Logger(subsystem: subsystem, category: "updates")
    static let performance = Logger(subsystem: subsystem, category: "performance")

    static func record(
        _ error: Error,
        logger: Logger,
        operation: String
    ) {
        logger.error(
            "\(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .private(mask: .hash))"
        )
    }

    static func event(
        _ message: String,
        logger: Logger
    ) {
        logger.notice("\(message, privacy: .public)")
    }
}
