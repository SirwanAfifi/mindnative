import Foundation
import LinkPresentation

struct LinkPreviewDetails: Equatable {
    let title: String
    let summary: String
}

enum LinkPreviewService {
    static func fetch(for url: URL) async throws -> LinkPreviewDetails {
        let provider = LPMetadataProvider()
        provider.timeout = 15
        let metadata: LPLinkMetadata = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<LPLinkMetadata, Error>) in
                provider.startFetchingMetadata(for: url) { metadata, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let metadata {
                        continuation.resume(returning: metadata)
                    } else {
                        continuation.resume(throwing: LinkPreviewError.emptyMetadata)
                    }
                }
            }
        } onCancel: {
            provider.cancel()
        }

        return LinkPreviewDetails(
            title: metadata.title?.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines
            )
                .nonEmpty ?? url.host ?? url.absoluteString,
            summary: url.host ?? url.absoluteString
        )
    }
}

enum LinkPreviewError: LocalizedError {
    case emptyMetadata

    var errorDescription: String? {
        "The link did not provide preview information."
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
