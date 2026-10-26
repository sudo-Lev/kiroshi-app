import Foundation

enum PeekMode: String, CaseIterable, Codable, Sendable {
    case translate
    case summary
}

enum PeekInputLimit {
    static let maxUTF16Units = HotkeyGoAPI.maxTextUTF16Units

    static func accepts(_ text: String) -> Bool {
        text.utf16.count <= maxUTF16Units
    }
}

enum PeekSummaryLength: String, CaseIterable, Codable, Sendable {
    case tldr
    case points
    case full
}

struct PeekRequest: Sendable {
    let text: String
    let sourceLanguage: String?
    let targetLanguage: String
    let mode: PeekMode
    let length: PeekSummaryLength
    /// Shared by every retry of the same panel request so the Worker charges it once.
    let operationID: String
    let provider: HotkeyGoAIProvider

    init(
        text: String,
        sourceLanguage: String?,
        targetLanguage: String,
        mode: PeekMode,
        length: PeekSummaryLength,
        operationID: String,
        provider: HotkeyGoAIProvider = .openAI
    ) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.mode = mode
        self.length = length
        self.operationID = operationID
        self.provider = provider
    }
}

protocol PeekClientProtocol: AnyObject {
    func stream(_ request: PeekRequest) -> AsyncThrowingStream<String, Error>
}

actor PeekClient: PeekClientProtocol {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    nonisolated func stream(_ request: PeekRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let timingStartedAt = ProcessInfo.processInfo.systemUptime
                defer {
                    let elapsed = max(0, Int(((ProcessInfo.processInfo.systemUptime - timingStartedAt) * 1_000).rounded()))
                    HotkeyGoAPI.recordClientTiming(provider: request.provider.rawValue, task: "peek", durationMs: elapsed)
                }
                do {
                    var urlRequest = URLRequest(url: OpenAIClient.endpoint)
                    urlRequest.httpMethod = "POST"
                    try HotkeyGoAPI.prepare(&urlRequest, operationID: request.operationID)
                    urlRequest.httpBody = try makeBody(request)

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else { throw PeekClientError.invalidResponse }
                    HotkeyGoUsage.record(http)
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes.prefix(8_192) { body.append(byte) }
                        throw HotkeyGoAPI.responseError(http, data: body)
                    }

                    var completed = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard payload != "[DONE]", let data = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else { continue }
                        switch event.type {
                        case "response.output_text.delta":
                            if let delta = event.delta { continuation.yield(delta) }
                        case "response.completed":
                            completed = true
                        case "response.incomplete", "response.failed":
                            throw PeekClientError.invalidResponse
                        default:
                            break
                        }
                    }
                    guard completed else { throw PeekClientError.invalidResponse }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Only the task and its parameters leave the app; the Worker builds the Peek prompt.
    nonisolated func makeBody(_ request: PeekRequest) throws -> Data {
        guard PeekInputLimit.accepts(request.text) else { throw PeekClientError.inputTooLong }
        let task = HotkeyGoTask(
            task: "peek",
            text: request.text,
            provider: request.provider.rawValue,
            language: Self.baseLanguageCode(request.targetLanguage),
            mode: request.mode.rawValue,
            length: request.length.rawValue,
            sourceLanguage: request.sourceLanguage.map(Self.baseLanguageCode)
        )
        return try JSONEncoder().encode(task)
    }

    private nonisolated static func baseLanguageCode(_ code: String) -> String {
        (code.split(separator: "-").first.map(String.init) ?? code).lowercased()
    }
}

private struct StreamEvent: Decodable {
    let type: String
    let delta: String?
}

enum PeekClientError: LocalizedError {
    case invalidResponse
    case inputTooLong

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The server returned an unreadable response."
        case .inputTooLong: "The selection is too long for Peek. Select a shorter passage."
        }
    }
}
