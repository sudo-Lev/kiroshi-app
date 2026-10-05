import Foundation

protocol ActionPerforming: AnyObject {
    func perform(_ text: String, instruction: String) async throws -> String
    /// Short multiple-choice questions whose answers most change the result of `goal`.
    func clarifyingQuestions(_ text: String, goal: String) async throws -> [RefineQuestion]
}

struct RefineQuestion: Codable, Equatable {
    let question: String
    let options: [String]
}

enum ActionMode: String, Codable, CaseIterable, Hashable {
    case replace = "REPLACE"
    case insert = "INSERT"
    case panel = "PANEL"
}

struct PaletteAction: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let hint: String
    let mode: ActionMode
    let prompt: String
    var language: String?
    var isPreset = false
    /// Asks a few quick questions before running, so the result lands in one pass.
    var refines = false
}

struct ActionGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let actions: [PaletteAction]
}

protocol ActionRegistering {
    func groups() -> [ActionGroup]
}

struct ActionRegistry: ActionRegistering {
    func groups() -> [ActionGroup] {
        let actions = [
            PaletteAction(id: "translate", name: "Translate", hint: "choose one of two languages", mode: .replace, prompt: "Translate naturally."),
            PaletteAction(id: "slack", name: "Slack style", hint: "clear, concise, human", mode: .replace, prompt: "Rewrite as a brief, natural Slack message. Keep facts and intent."),
            PaletteAction(id: "formal", name: "Make formal", hint: "polished professional tone", mode: .replace, prompt: "Rewrite professionally and directly. Keep the meaning.")
        ]
        return [ActionGroup(id: "actions", title: "Actions", actions: actions)]
    }
}

enum PaletteFilter {
    static func apply(_ query: String, to groups: [ActionGroup]) -> [ActionGroup] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !normalized.isEmpty else { return groups }
        let languageAliases = ["polski": "polish", "українська": "ukrainian", "deutsch": "german", "español": "spanish"]
        let terms = [normalized, languageAliases[normalized]].compactMap { $0 }
        return groups.compactMap { group in
            let actions = group.actions.filter { action in
                let haystack = [action.name, action.hint, action.mode.rawValue, action.language ?? ""]
                    .joined(separator: " ")
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                return terms.contains { haystack.localizedCaseInsensitiveContains($0) }
                    || (action.id == "translate" && languageAliases[normalized] != nil)
            }
            return actions.isEmpty ? nil : ActionGroup(id: group.id, title: group.title, actions: actions)
        }
    }
}
