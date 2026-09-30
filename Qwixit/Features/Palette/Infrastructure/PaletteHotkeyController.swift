import Foundation

enum HotkeyTapDecision: Equatable {
    case pendingSingle
    case double
}

struct DoubleTapClassifier {
    let interval: TimeInterval
    private(set) var firstTapTime: TimeInterval?

    mutating func registerTap(at time: TimeInterval) -> HotkeyTapDecision {
        if let firstTapTime, time - firstTapTime <= interval {
            self.firstTapTime = nil
            return .double
        }
        firstTapTime = time
        return .pendingSingle
    }

    mutating func consumePendingSingle(at time: TimeInterval) -> Bool {
        guard let firstTapTime, time - firstTapTime >= interval else { return false }
        self.firstTapTime = nil
        return true
    }
}

final class HotkeyManager {
    private let hotKey: HotKeyManaging
    private var classifier: DoubleTapClassifier
    private var pendingSingle: DispatchWorkItem?
    private var onSingle: (() -> Void)?
    private var onDouble: (() -> Void)?

    init(hotKey: HotKeyManaging = GlobalHotKey(), intervalMilliseconds: Int = 300) {
        self.hotKey = hotKey
        classifier = DoubleTapClassifier(interval: Double(intervalMilliseconds) / 1_000)
    }

    @discardableResult
    func start(
        binding: HotkeyBinding = .defaultMain,
        intervalMilliseconds: Int,
        onSingle: @escaping () -> Void,
        onDouble: @escaping () -> Void
    ) -> Bool {
        pendingSingle?.cancel()
        classifier = DoubleTapClassifier(interval: Double(min(max(intervalMilliseconds, 200), 500)) / 1_000)
        self.onSingle = onSingle
        self.onDouble = onDouble
        return hotKey.register(keyCode: binding.keyCode, modifiers: binding.modifiers) { [weak self] in
            self?.receiveTap()
        }
    }

    func stop() {
        pendingSingle?.cancel()
        pendingSingle = nil
        hotKey.unregister()
    }

    private func receiveTap() {
        let now = ProcessInfo.processInfo.systemUptime
        switch classifier.registerTap(at: now) {
        case .pendingSingle:
            pendingSingle?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard var classifier = self?.classifier,
                      classifier.consumePendingSingle(at: ProcessInfo.processInfo.systemUptime) else { return }
                self?.classifier = classifier
                self?.onSingle?()
            }
            pendingSingle = work
            DispatchQueue.main.asyncAfter(deadline: .now() + classifier.interval, execute: work)
        case .double:
            pendingSingle?.cancel()
            pendingSingle = nil
            onDouble?()
        }
    }
}
