import AppKit
import Foundation

struct AppUpdate: Codable, Equatable {
    let version: String
    let build: Int?
    let minimumSystemVersion: String?
    let releaseNotesURL: URL
    let downloadURL: URL
    let publishedAt: Date?
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }
}

@MainActor
final class UpdateService: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case current
        case available(AppUpdate)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    func check() async {
        guard let urlString = Bundle.main.object(
            forInfoDictionaryKey: "MindNativeUpdateFeedURL"
        ) as? String,
        let url = URL(string: urlString) else {
            state = .failed("No update feed is configured.")
            return
        }

        state = .checking
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw UpdateError.invalidResponse
            }

            let update = try decodeUpdate(data)
            state = isNewer(update.version) ? .available(update) : .current
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
            Diagnostics.record(
                error,
                logger: Diagnostics.updates,
                operation: "Check for updates"
            )
        }
    }

    func open(_ update: AppUpdate) {
        NSWorkspace.shared.open(update.downloadURL)
    }

    private func decodeUpdate(_ data: Data) throws -> AppUpdate {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let feed = try? decoder.decode(AppUpdate.self, from: data) {
            return feed
        }

        let release = try decoder.decode(GitHubRelease.self, from: data)
        return AppUpdate(
            version: release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
            build: nil,
            minimumSystemVersion: nil,
            releaseNotesURL: release.htmlURL,
            downloadURL: release.htmlURL,
            publishedAt: release.publishedAt
        )
    }

    private func isNewer(_ candidate: String) -> Bool {
        let current = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"
        return candidate.compare(current, options: .numeric) == .orderedDescending
    }
}

enum UpdateError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "The update service returned an invalid response."
    }
}
