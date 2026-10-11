import Foundation
import FoundationModels
import OSLog

enum AIServiceError: LocalizedError {
    case requiresMacOS26
    case modelUnavailable
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .requiresMacOS26:
            return "Apple Intelligence idea generation requires macOS 26 or later."
        case .modelUnavailable:
            return "Apple Intelligence is not available on this Mac or is turned off."
        case .emptyResponse:
            return "Apple Intelligence returned no usable ideas."
        }
    }
}

final class AIService {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MindNative",
        category: "IdeaGeneration"
    )

    func generateIdeas(topic: String, context: [String] = []) async throws -> [String] {
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else {
                throw AIServiceError.modelUnavailable
            }

            let systemPrompt = """
You are a topic–decomposition engine for a mind-mapping app.

Your job:
- Break the user's topic into 5–7 meaningful subtopics.
- Subtopics must be conceptual, instructional, or structural — not fictional, not playful.
- They must represent real knowledge areas someone would study or explore.

Formatting rules (strict):
- Each idea must be 2–4 words long.
- No narrative themes (e.g. Travel Diary, Art Adventures, Music Jam Sessions).
- No fictional or creative scenarios.
- No metaphors or storytelling.
- Ideas must be academically or technically relevant to the topic.
- NO numbering, NO bullet points, NO colons, NO headings.
- NO sentences. NO punctuation except normal letters and spaces.
- NO quotes or JSON. NO explanation before or after.
- Output only the ideas, one per line, nothing else.

Examples:

Topic: Learning SwiftUI
OUTPUT:
Core Concepts
Layout System
State Management
View Modifiers
Data Flow
Animations
Navigation Patterns

Topic: Machine Learning
OUTPUT:
Model Training
Feature Engineering
Neural Networks
Evaluation Metrics
Data Preprocessing
Deployment Pipelines
Optimization Methods
"""

            return try await generateWithFoundationModel(
                system: systemPrompt,
                topic: topic,
                context: context
            )
        } else {
            throw AIServiceError.requiresMacOS26
        }
    }

    func summarizeBranch(title: String, outline: [String]) async throws -> String {
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else {
                throw AIServiceError.modelUnavailable
            }

            let session = LanguageModelSession()
            let prompt = """
Summarize this mind-map branch in two concise sentences.
Do not add facts that are not present.
Return only the summary.

Branch: \(title)
Ideas:
\(outline.joined(separator: "\n"))
"""
            let response = try await session.respond(to: prompt)
            try Task.checkCancellation()
            let summary = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else { throw AIServiceError.emptyResponse }
            logger.debug("On-device branch summary completed")
            return summary
        } else {
            throw AIServiceError.requiresMacOS26
        }
    }

    @available(macOS 26.0, *)
    private func generateWithFoundationModel(system: String, topic: String, context: [String] = []) async throws -> [String] {
        let session = LanguageModelSession()

        // Build context chain string
        let contextString: String
        if !context.isEmpty {
            contextString = """

Context (parent topics in the mind map):
\(context.joined(separator: " → "))

You are generating subtopics for "\(topic)" which appears in this context.
Consider the hierarchy when generating ideas.
"""
        } else {
            contextString = ""
        }

        // Combine system + user into one prompt for now
        let fullPrompt = """
\(system)
\(contextString)

Topic: \(topic)

Remember:
- Output ONLY the ideas.
- One idea per line.
- No bullets, no numbers, no extra text.
"""

        let response = try await session.respond(to: fullPrompt)
        try Task.checkCancellation()
        logger.debug("On-device idea generation completed")

        let ideas = response.content
            .components(separatedBy: .newlines)
            .map { line -> String in
                var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)

                // Strip numbering and bullets defensively
                cleaned = cleaned.replacingOccurrences(
                    of: #"^\d+\.\s*"#,
                    with: "",
                    options: .regularExpression
                )
                cleaned = cleaned.replacingOccurrences(
                    of: #"^[-•*]\s*"#,
                    with: "",
                    options: .regularExpression
                )

                // Strip quotes / JSON junk just in case
                cleaned = cleaned.replacingOccurrences(of: "\"", with: "")
                cleaned = cleaned.replacingOccurrences(of: "{", with: "")
                cleaned = cleaned.replacingOccurrences(of: "}", with: "")
                cleaned = cleaned.replacingOccurrences(of: "[", with: "")
                cleaned = cleaned.replacingOccurrences(of: "]", with: "")
                cleaned = cleaned.replacingOccurrences(of: "ideas:", with: "", options: .caseInsensitive)
                cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

                return cleaned
            }
            .filter { !$0.isEmpty }
            .prefix(7)

        guard !ideas.isEmpty else {
            throw AIServiceError.emptyResponse
        }

        return Array(ideas)
    }
}
