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
