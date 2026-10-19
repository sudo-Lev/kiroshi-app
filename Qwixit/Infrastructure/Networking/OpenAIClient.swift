import Foundation

enum QwixitAPIError: LocalizedError {
    case invalidResponse
    case emptyOutput
    case incompleteOutput
    case quotaExceeded(checkoutURL: URL?)
    case rateLimited(retryAfter: Duration?)
    case operationExhausted
    case textTooLong
    case outputRejected
    case dailyLimit
    case monthlyLimit
    case api(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The AI service returned an unreadable response. Your text is unchanged."
        case .emptyOutput: "The AI service returned no text. Your text is unchanged."
        case .incompleteOutput: "The AI service did not finish the result. Your text is unchanged."
        case .quotaExceeded: "You’ve used your free actions this month."
        case .rateLimited: "Slow down a bit. Your text is unchanged."
        case .operationExhausted: "This action can’t be retried again. Your text is unchanged."
        case .textTooLong: "Too long: select at most 2 pages (6,000 characters). Your text is unchanged."
        case .outputRejected: "The result didn’t pass Tokiri’s checks, so it was not replaced. Your text is unchanged."
        case .dailyLimit: "Daily limit reached: Advanced resets at midnight UTC. Your text is unchanged."
        case .monthlyLimit: "Monthly limit reached: you’ve used this month’s Advanced fair use. Your text is unchanged."
        case .api(let status, let message): "Tokiri service error \(status): \(message)"
        }
    }
}

enum QwixitAPI {
    static let endpoint = URL(string: "https://qwixit-api.levmisiliuk.workers.dev/v2/qwix")!
    /// Matches the Worker limit: about two pages. Longer selections are rejected before any request.
    static let maxTextUTF16Units = 6_000

    static func accepts(_ text: String) -> Bool {
        text.utf16.count <= maxTextUTF16Units
    }

    static func prepare(_ request: inout URLRequest, operationID: String? = QwixitOperation.id) throws {
#if DEBUG
        if AppPreferences().developerUsageScenario == .limitReached {
            throw QwixitAPIError.quotaExceeded(checkoutURL: nil)
        }
#endif
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Qwixit/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(try InstallationIdentity.current(), forHTTPHeaderField: "X-Qwixit-Installation-ID")
        if let operationID {
            request.setValue(operationID, forHTTPHeaderField: "X-Qwixit-Operation-ID")
        }
    }

    static func responseError(_ response: HTTPURLResponse, data: Data) -> QwixitAPIError {
        let status = response.statusCode
        let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        if status == 402, envelope?.error.code == "free_limit_reached" {
            QwixitUsage.recordLimitReached()
            return .quotaExceeded(checkoutURL: envelope?.error.checkoutURL.flatMap(URL.init(string:)))
        }
        switch (status, envelope?.error.code) {
        case (409, "operation_exhausted"): return .operationExhausted
        case (413, _): return .textTooLong
        case (422, "output_rejected"): return .outputRejected
        case (429, "daily_limit"): return .dailyLimit
        case (429, "monthly_limit"): return .monthlyLimit
        default: break
        }
        if status == 429 {
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap(Int.init)
                .map { Duration.seconds(max($0, 0)) }
            return .rateLimited(retryAfter: retryAfter)
        }
        return .api(
            status: status,
            message: envelope?.error.message ?? HTTPURLResponse.localizedString(forStatusCode: status)
        )
    }

    static func isConnectivityError(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .timedOut, .internationalRoamingOff:
            true
        default:
            false
        }
    }

    static func isRetryableError(_ error: Error) -> Bool {
        if isConnectivityError(error) { return true }

        guard let error = error as? QwixitAPIError else { return false }
        switch error {
        case .invalidResponse:
            return true
        case .rateLimited(let retryAfter):
            return retryAfter.map { $0 <= NetworkRetry.maximumRetryAfter } ?? true
        case .api(let status, _):
            return status == 408 || status == 425 || (500...599).contains(status)
        // The same text under the same output limit would be cut off or empty again.
        case .emptyOutput, .incompleteOutput, .quotaExceeded, .operationExhausted,
             .textTooLong, .outputRejected, .dailyLimit, .monthlyLimit:
            return false
        }
    }
}

/// Identifies one user action across its retries so the Worker charges it once.
enum QwixitOperation {
    @TaskLocal static var id: String?

    static func makeID() -> String { UUID().uuidString }
}

enum NetworkRetry {
    static let maximumAttempts = 3
    static let retryDelays: [Duration] = [.seconds(1), .seconds(2)]
    static let maximumRetryAfter: Duration = .seconds(10)

    static func perform<T>(
        operationID: String = QwixitOperation.makeID(),
        operation: () async throws -> T,
        onRetry: (Int, Int) async -> Void = { _, _ in },
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> T {
        try await QwixitOperation.$id.withValue(operationID) {
            for attempt in 1...maximumAttempts {
                do {
                    return try await operation()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    guard attempt < maximumAttempts, QwixitAPI.isRetryableError(error) else {
                        throw error
                    }

                    let nextAttempt = attempt + 1
                    await onRetry(nextAttempt, maximumAttempts)
                    try await sleep(delay(after: attempt, error: error))
                }
            }

            throw CancellationError()
        }
    }

    static func delay(after attempt: Int, error: Error) -> Duration {
        let backoff = retryDelays[min(attempt, retryDelays.count) - 1]
        if case QwixitAPIError.rateLimited(let retryAfter?) = error {
            return max(backoff, retryAfter)
        }
        return backoff
    }
}

enum QwixitUsage {
    static let didChange = Notification.Name("QwixitUsageDidChange")

    private static let lock = NSLock()

    static var remaining: Int? { AppPreferences().remainingActions }

    /// The Worker reports `advanced`; builds before the rename and `/billing/status` still say `unlimited`.
    static func isAdvancedPlan(_ plan: String?) -> Bool {
        plan == "advanced" || plan == "unlimited"
    }

    static func record(_ response: HTTPURLResponse, defaults: UserDefaults = .standard) {
        let period = response.value(forHTTPHeaderField: "X-Qwixit-Period") ?? currentUTCMonth()
        update(defaults: defaults) {
            if let plan = response.value(forHTTPHeaderField: "X-Qwixit-Plan") {
                defaults.set(plan, forKey: AppPreferenceKey.quotaPlan)
                if isAdvancedPlan(plan) {
                    defaults.removeObject(forKey: AppPreferenceKey.quotaRemaining)
                    defaults.set(period, forKey: AppPreferenceKey.quotaPeriod)
                    return
                }
            }
            if let raw = response.value(forHTTPHeaderField: "X-Qwixit-Remaining"),
               let remaining = Int(raw) {
                recordFreeRemaining(remaining, period: period, defaults: defaults)
            }
        }
    }

    static func recordLimitReached(defaults: UserDefaults = .standard) {
        update(defaults: defaults) {
            defaults.set("free", forKey: AppPreferenceKey.quotaPlan)
            recordFreeRemaining(0, period: currentUTCMonth(), defaults: defaults)
        }
    }

    static func record(_ status: BillingStatus, defaults: UserDefaults = .standard) {
        let period = status.period ?? currentUTCMonth()
        update(defaults: defaults) {
            defaults.set(status.plan, forKey: AppPreferenceKey.quotaPlan)
            if status.isAdvanced {
                defaults.removeObject(forKey: AppPreferenceKey.quotaRemaining)
                defaults.set(period, forKey: AppPreferenceKey.quotaPeriod)
            } else if let remaining = status.remaining {
                recordFreeRemaining(remaining, period: period, defaults: defaults)
            }
        }
    }

    private static func update(defaults: UserDefaults, mutation: () -> Void) {
        lock.lock()
        mutation()
        lock.unlock()
        NotificationCenter.default.post(name: didChange, object: defaults)
    }

    private static func recordFreeRemaining(
        _ remaining: Int,
        period: String,
        defaults: UserDefaults
    ) {
        let clamped = min(max(remaining, 0), 30)
        let cachedPeriod = defaults.string(forKey: AppPreferenceKey.quotaPeriod)
        let cachedRemaining = defaults.object(forKey: AppPreferenceKey.quotaRemaining) as? Int
        let resolved = cachedPeriod == period
            ? min(cachedRemaining ?? clamped, clamped)
            : clamped
        defaults.set(period, forKey: AppPreferenceKey.quotaPeriod)
        defaults.set(resolved, forKey: AppPreferenceKey.quotaRemaining)
    }

    private static func currentUTCMonth() -> String {
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(secondsFromGMT: 0)!,
            from: Date()
        )
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }
}

/// Fix either found nothing to change or returns the corrected text.
enum FixOutcome: Equatable, Sendable {
    case clean
    case fixed(String)
}

/// Sends tasks to the Worker. Prompts, model, and limits live in `cloudflare-worker/prompts.js`.
actor OpenAIClient {
    static let endpoint = QwixitAPI.endpoint
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func improve(_ text: String) async throws -> FixOutcome {
        let data = try await send(QwixTask(task: "fix", text: text, priority: Self.wantsPriority))
        guard let decoded = try? JSONDecoder().decode(FixEnvelope.self, from: data) else {
            throw QwixitAPIError.invalidResponse
        }
        switch decoded.result {
        case "clean":
            return .clean
        case "fixed":
            guard let text = decoded.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw QwixitAPIError.emptyOutput
            }
            return .fixed(text)
        default:
            throw QwixitAPIError.invalidResponse
        }
    }

    func performAction(_ text: String, action: String, language: String?) async throws -> String {
        let data = try await send(QwixTask(
            task: "action",
            text: text,
            priority: Self.wantsPriority,
            action: action,
            language: language
        ))
        guard let decoded = try? JSONDecoder().decode(TextEnvelope.self, from: data) else {
            throw QwixitAPIError.invalidResponse
        }
        guard !decoded.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QwixitAPIError.emptyOutput
        }
        return decoded.text
    }

    private func send(_ task: QwixTask) async throws -> Data {
        guard QwixitAPI.accepts(task.text) else { throw QwixitAPIError.textTooLong }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        try QwixitAPI.prepare(&request)
        request.httpBody = try JSONEncoder().encode(task)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw QwixitAPIError.invalidResponse }
        QwixitUsage.record(http)
        guard (200..<300).contains(http.statusCode) else {
            throw QwixitAPI.responseError(http, data: data)
        }
        return data
    }

    /// The Worker ignores priority for Free; the client only asks when Advanced and the setting is on.
    private static var wantsPriority: Bool? {
        let preferences = AppPreferences()
        return preferences.isAdvanced && UserDefaults.standard.bool(forKey: AppPreferenceKey.priorityProcessing) ? true : nil
    }
}

/// The `/v2/qwix` request body. Optional fields are omitted when nil.
struct QwixTask: Encodable, Sendable {
    let task: String
    let text: String
    var priority: Bool?
    var action: String?
    var language: String?
    var mode: String?
    var length: String?
    var sourceLanguage: String?
}

private struct FixEnvelope: Decodable {
    let result: String
    let text: String?
}

private struct TextEnvelope: Decodable {
    let text: String
}

private struct APIErrorEnvelope: Decodable {
    let error: APIError
    struct APIError: Decodable {
        let message: String
        let code: String?
        let checkoutURL: String?

        enum CodingKeys: String, CodingKey {
            case message, code
            case checkoutURL = "checkout_url"
        }
    }
}
