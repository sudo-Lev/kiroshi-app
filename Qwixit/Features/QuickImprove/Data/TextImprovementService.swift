import Foundation

actor TextImprovementService: TextImproving, ActionPerforming {
    enum ImprovementError: Error { case empty }
    private let openAI = OpenAIClient()

    func improve(_ text: String, instruction: String?) async throws -> String {
        guard !text.isEmpty else { throw ImprovementError.empty }
        if KeychainStore.apiKey() != nil {
            return try await openAI.improve(text, instruction: instruction)
        }
        try await Task.sleep(for: .milliseconds(560))

        if let instruction {
            if instruction.localizedCaseInsensitiveContains("short") {
                return text.split(separator: ".").first.map { String($0).trimmingCharacters(in: .whitespaces) + "." } ?? text
            }
            if instruction.localizedCaseInsensitiveContains("friendly") {
                return text.replacingOccurrences(of: "Hello", with: "Hi").replacingOccurrences(of: "Regards", with: "Thanks")
            }
            if instruction.localizedCaseInsensitiveContains("professional") {
                return text.replacingOccurrences(of: "Hey", with: "Hello").replacingOccurrences(of: "Thanks!", with: "Kind regards,")
            }
        }

        var result = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = result.first { result.replaceSubrange(result.startIndex...result.startIndex, with: String(first).uppercased()) }
        if !result.hasSuffix(".") && !result.hasSuffix("!") && !result.hasSuffix("?") { result += "." }
        return result
    }

    func perform(_ text: String, instruction: String) async throws -> String {
        guard !text.isEmpty else { throw ImprovementError.empty }
        if KeychainStore.apiKey() != nil {
            return try await openAI.performAction(text, instruction: instruction)
        }
        try await Task.sleep(for: .milliseconds(420))
        if instruction.localizedCaseInsensitiveContains("summar") {
            return text.split(separator: ".").prefix(2).joined(separator: ".") + "."
        }
        if instruction.localizedCaseInsensitiveContains("expand") {
            return "This adds useful context while preserving the original point."
        }
        return try await improve(text, instruction: instruction)
    }

    func clarifyingQuestions(_ text: String, goal: String) async throws -> [RefineQuestion] {
        guard !text.isEmpty else { throw ImprovementError.empty }
        if KeychainStore.apiKey() != nil {
            return try await openAI.clarifyingQuestions(text, goal: goal)
        }
        try await Task.sleep(for: .milliseconds(320))
        return [
            RefineQuestion(question: "Who will read it?", options: ["Colleague", "Client", "LLM", "Myself"]),
            RefineQuestion(question: "How long?", options: ["Same", "A bit longer", "Much longer"])
        ]
    }
}
