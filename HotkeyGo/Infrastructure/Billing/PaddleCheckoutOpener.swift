import AppKit
import Foundation
import Combine

struct PaddleCheckoutOpener: CheckoutOpening {
    private let checkoutURL: URL

    init(
        checkoutURL: URL = URL(
            string: "https://qwixit-api.levmisiliuk.workers.dev/billing/checkout"
        )!
    ) {
        self.checkoutURL = checkoutURL
    }

    func openStarterCheckout() -> Bool {
        guard let installationID = try? InstallationIdentity.current(),
              var components = URLComponents(url: checkoutURL, resolvingAgainstBaseURL: false) else { return false }
        components.queryItems = [URLQueryItem(name: "installation_id", value: installationID)]
        guard let url = components.url else { return false }
        return NSWorkspace.shared.open(url)
    }
}

struct BillingStatus: Decodable, Equatable {
    let plan: String
    let subscriptionStatus: String
    let remaining: Int?
    let period: String?
    let resetsAt: Date?
    let renewsAt: Date?

    var isAdvanced: Bool { HotkeyGoUsage.isAdvancedPlan(plan) }

    enum CodingKeys: String, CodingKey {
        case plan, remaining, period
        case subscriptionStatus = "subscription_status"
        case resetsAt = "resets_at"
        case renewsAt = "renews_at"
    }

    init(
        plan: String,
        subscriptionStatus: String,
        remaining: Int?,
        period: String?,
        resetsAt: Date? = nil,
        renewsAt: Date? = nil
    ) {
        self.plan = plan
        self.subscriptionStatus = subscriptionStatus
        self.remaining = remaining
        self.period = period
        self.resetsAt = resetsAt
        self.renewsAt = renewsAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        plan = try values.decode(String.self, forKey: .plan)
        subscriptionStatus = try values.decode(String.self, forKey: .subscriptionStatus)
        remaining = try values.decodeIfPresent(Int.self, forKey: .remaining)
        period = try values.decodeIfPresent(String.self, forKey: .period)
        resetsAt = Self.decodeDate(try values.decodeIfPresent(String.self, forKey: .resetsAt))
        renewsAt = Self.decodeDate(try values.decodeIfPresent(String.self, forKey: .renewsAt))
    }

    private static func decodeDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

enum Plan: Equatable {
    case free
    case advanced
}

struct Usage: Equatable {
    let used: Int
    let limit: Int
    let resetsAt: Date

    init(used: Int, limit: Int = 30, resetsAt: Date) {
        self.used = min(max(used, 0), limit)
        self.limit = limit
        self.resetsAt = resetsAt
    }
}

enum MeterTone: Equatable {
    case ink
    case orange
    case red
    case green
}

struct PlanMeterValue: Equatable {
    let filled: Int
    let tone: MeterTone
}

func meter(plan: Plan, used: Int) -> PlanMeterValue {
    if plan == .advanced { return PlanMeterValue(filled: 3, tone: .green) }
    return switch min(max(used, 0), 30) {
    case 0...10: PlanMeterValue(filled: 1, tone: .ink)
    case 11...20: PlanMeterValue(filled: 2, tone: .orange)
    case 21...29: PlanMeterValue(filled: 3, tone: .orange)
    default: PlanMeterValue(filled: 3, tone: .red)
    }
}

@MainActor
final class PlanStatus: ObservableObject {
    struct Snapshot: Equatable {
        let plan: Plan
        let usage: Usage?
        let renewsAt: Date?
    }

    static let shared = PlanStatus()

    @Published private(set) var snapshot: Snapshot

    private let defaults: UserDefaults
    private var usageObserver: NSObjectProtocol?
    private var resetTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snapshot = Self.cachedSnapshot(defaults: defaults)
        usageObserver = NotificationCenter.default.addObserver(
            forName: HotkeyGoUsage.didChange,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshFromCache() }
        }
        scheduleMonthlyReset()
    }

    deinit {
        resetTask?.cancel()
        if let usageObserver { NotificationCenter.default.removeObserver(usageObserver) }
    }

    var isAdvanced: Bool { snapshot.plan == .advanced }
    var used: Int { snapshot.usage?.used ?? 0 }
    var remainingActions: Int? { snapshot.usage.map { $0.limit - $0.used } }
    var meterValue: PlanMeterValue { meter(plan: snapshot.plan, used: used) }

    func refreshFromCache() {
        snapshot = Self.cachedSnapshot(defaults: defaults)
        scheduleMonthlyReset()
    }

    private func scheduleMonthlyReset() {
        resetTask?.cancel()
        guard let resetsAt = snapshot.usage?.resetsAt else { return }
        let delay = max(0.1, resetsAt.timeIntervalSinceNow)
        resetTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            self?.refreshFromCache()
        }
    }

    private static func cachedSnapshot(defaults: UserDefaults) -> Snapshot {
        let preferences = AppPreferences(defaults: defaults)
        if preferences.isAdvanced {
            return Snapshot(
                plan: .advanced,
                usage: nil,
                renewsAt: defaults.object(forKey: AppPreferenceKey.quotaRenewsAt) as? Date
            )
        }

        let currentPeriod = HotkeyGoUsage.currentUTCMonth()
        let isCurrentPeriod = defaults.string(forKey: AppPreferenceKey.quotaPeriod) == currentPeriod
        var used = isCurrentPeriod ? 30 - (preferences.remainingActions ?? 30) : 0
#if DEBUG
        if preferences.developerUsageScenario == .limitReached { used = 30 }
#endif
        let resetsAt = isCurrentPeriod
            ? defaults.object(forKey: AppPreferenceKey.quotaResetsAt) as? Date ?? nextUTCMonthStart()
            : nextUTCMonthStart()
        return Snapshot(
            plan: .free,
            usage: Usage(used: used, resetsAt: resetsAt),
            renewsAt: nil
        )
    }

    private static func nextUTCMonthStart(now: Date = .now) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let start = calendar.date(from: components),
              let next = calendar.date(byAdding: .month, value: 1, to: start) else { return now }
        return next
    }
}

protocol BillingStatusChecking {
    func fetchStatus() async throws -> BillingStatus
}

struct BillingStatusClient: BillingStatusChecking {
    private let endpoint: URL
    private let session: URLSession

    init(
        endpoint: URL = URL(string: "https://qwixit-api.levmisiliuk.workers.dev/billing/status")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    func fetchStatus() async throws -> BillingStatus {
        guard let installationID = try? InstallationIdentity.current(),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "installation_id", value: installationID)]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(BillingStatus.self, from: data)
    }
}
