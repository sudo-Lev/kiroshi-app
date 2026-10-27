import Foundation

enum OnboardingStep: CaseIterable, Identifiable {
    case welcome
    case accessibility
    case fix
    case actions
    case peek
    case complete

    var id: Self { self }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .accessibility: "Access"
        case .fix: "Fix"
        case .actions: "Actions"
        case .peek: "Peek"
        case .complete: "Done"
        }
    }

    var isPractice: Bool {
        practiceOrdinal != nil
    }

    static var practiceCount: Int { practiceSteps.count }

    var practiceOrdinal: Int? {
        guard let index = Self.practiceSteps.firstIndex(of: self) else { return nil }
        return index + 1
    }

    private static let practiceSteps: [Self] = [.fix, .actions, .peek]

    var next: Self? {
        guard let index = Self.allCases.firstIndex(of: self) else { return nil }
        let nextIndex = Self.allCases.index(after: index)
        return Self.allCases.indices.contains(nextIndex) ? Self.allCases[nextIndex] : nil
    }

    var previous: Self? {
        guard let index = Self.allCases.firstIndex(of: self), index > Self.allCases.startIndex else { return nil }
        return Self.allCases[Self.allCases.index(before: index)]
    }

    func precedes(_ other: Self) -> Bool {
        guard let index = Self.allCases.firstIndex(of: self),
              let otherIndex = Self.allCases.firstIndex(of: other) else { return false }
        return index < otherIndex
    }
}

enum OnboardingPhase: Equatable {
    case idle
    case processing
    case typing
    case palette
    case peekChoice
    case peekProcessing
    case peek
    case peekDone
    case skipped
    case done
}

enum OnboardingPeekLanguage: Int, CaseIterable, Identifiable, Equatable {
    case ukrainian
    case polish
    case french
    case english

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .ukrainian: "Українська"
        case .polish: "Polski"
        case .french: "Français"
        case .english: "English"
        }
    }

    var result: String {
        switch self {
        case .ukrainian: "Чи зустрінемося біля вокзалу близько полудня?"
        case .polish: "Czy spotkamy się przed dworcem około południa?"
        case .french: "On se retrouve devant la gare vers midi ?"
        case .english: "Shall we meet in front of the station around noon?"
        }
    }
}

enum OnboardingChoice: Int, CaseIterable, Identifiable {
    case ukrainian
    case polish
    case slack
    case formal

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .slack: "Slack style"
        case .formal: "Make formal"
        case .ukrainian: "Ukrainian"
        case .polish: "Polish"
        }
    }

    var result: String {
        switch self {
        case .slack: "Hey, could you send me the file when you get a sec?"
        case .formal: "Could you please send me the file at your earliest convenience?"
        case .ukrainian: "Можеш надіслати мені файл якнайшвидше, будь ласка?"
        case .polish: "Możesz wysłać mi plik jak najszybciej?"
        }
    }

    var isRewrite: Bool { self == .slack || self == .formal }
}
