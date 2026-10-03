import Foundation

actor TextImprovementService: TextImproving, ActionPerforming {
    enum ImprovementError: Error { case empty }
    private let openAI = OpenAIClient()

    func improve(_ text: String, instruction: String?) async throws -> String {
        guard !text.isEmpty else { throw ImprovementError.empty }
        return try await openAI.improve(text, instruction: instruction)
    }

    func perform(_ text: String, instruction: String) async throws -> String {
        guard !text.isEmpty else { throw ImprovementError.empty }
        return try await openAI.performAction(text, instruction: instruction)
    }

    func clarifyingQuestions(_ text: String, goal: String) async throws -> [RefineQuestion] {
        guard !text.isEmpty else { throw ImprovementError.empty }
        return try await openAI.clarifyingQuestions(text, goal: goal)
    }
}
