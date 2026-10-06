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
        TranslationLanguage(id: "de", code: "DE", name: "Deutsch"),
        TranslationLanguage(id: "en", code: "EN", name: "English")
    ]

    static func targets(for sourceLanguage: String?) -> [TranslationLanguage] {
        supported
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
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
        return DetectedLanguage(code: code, displayName: name)
    }
}
