import AppKit
import Foundation

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

    var isUnlimited: Bool { plan == "unlimited" }

    enum CodingKeys: String, CodingKey {
        case plan, remaining, period
        case subscriptionStatus = "subscription_status"
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
