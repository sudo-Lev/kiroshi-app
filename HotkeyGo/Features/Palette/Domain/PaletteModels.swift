import Foundation

protocol ActionPerforming: AnyObject {
    /// Runs a server-defined action preset; the Worker owns the prompt for each `action` id.
    func perform(_ text: String, action: String, language: String?) async throws -> String
}

enum ActionMode: String, Codable, CaseIterable, Hashable {
    case replace = "REPLACE"
    case insert = "INSERT"
}

struct PaletteAction: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let hint: String
    let mode: ActionMode
    var language: String?
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
            PaletteAction(id: "translate", name: "Translate", hint: "choose one of two languages", mode: .replace),
            PaletteAction(id: "slack", name: "Slack style", hint: "clear, concise, human", mode: .replace),
            PaletteAction(id: "formal", name: "Make formal", hint: "polished professional tone", mode: .replace)
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
