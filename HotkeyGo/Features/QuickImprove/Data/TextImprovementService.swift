import Foundation

actor TextImprovementService: TextImproving, ActionPerforming {
    enum ImprovementError: Error { case empty }
    private let openAI = OpenAIClient()

    func improve(_ text: String) async throws -> FixOutcome {
        guard !text.isEmpty else { throw ImprovementError.empty }
        return try await openAI.improve(text)
    }

    func perform(_ text: String, action: String, language: String?) async throws -> String {
        guard !text.isEmpty else { throw ImprovementError.empty }
        return try await openAI.performAction(text, action: action, language: language)
    }
}
