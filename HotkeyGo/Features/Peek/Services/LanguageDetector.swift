import Foundation
import NaturalLanguage

struct DetectedLanguage: Equatable {
    let code: String
    let displayName: String
}

struct TranslationLanguage: Identifiable, Hashable {
    let id: String
    let code: String
    let name: String
}

enum TranslationLanguages {
    private static let supported = [
        TranslationLanguage(id: "uk", code: "UA", name: "Українська"),
        TranslationLanguage(id: "pl", code: "PL", name: "Polski"),
        TranslationLanguage(id: "fr", code: "FR", name: "Français"),
        TranslationLanguage(id: "en", code: "EN", name: "English")
    ]

    static func targets(for sourceLanguage: String?) -> [TranslationLanguage] {
        supported
    }

    /// Actions stays intentionally compact: two useful replacement targets,
    /// excluding the detected source language. Peek keeps the full chooser.
    static func actionTargets(for sourceLanguage: String?) -> [TranslationLanguage] {
        let source = sourceLanguage?
            .split(separator: "-")
            .first
            .map(String.init)?
            .lowercased()
        let preferredIDs: [String] = switch source {
        case "en": ["uk", "pl"]
        case "uk": ["en", "pl"]
        case "pl", "fr", .none: ["en", "uk"]
        default: ["en", "uk"]
        }
        return preferredIDs.compactMap { id in supported.first(where: { $0.id == id }) }
    }
}

protocol LanguageDetecting {
    func detect(_ text: String) -> DetectedLanguage?
}

struct LanguageDetector: LanguageDetecting {
    func detect(_ text: String) -> DetectedLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        let code = language.rawValue
        let name = Locale.current.localizedString(forLanguageCode: code) ?? "Unknown language"
        return DetectedLanguage(code: code, displayName: name)
    }
}
