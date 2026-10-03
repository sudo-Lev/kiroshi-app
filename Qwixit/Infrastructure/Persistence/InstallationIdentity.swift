import Foundation
import Security

/// A random, device-local identifier used to associate usage and billing state.
/// It is intentionally not an OpenAI or Paddle credential.
enum InstallationIdentity {
    private static let service = "ai.qwixit.app"
    private static let account = "installation-id"

    enum IdentityError: LocalizedError {
        case unavailable(OSStatus)

        var errorDescription: String? {
            "Qwixit could not access its secure device identity (Keychain error \(statusCode))."
        }

        private var statusCode: OSStatus {
            switch self { case .unavailable(let status): status }
        }
    }

    static func current() throws -> String {
        if let stored = read() { return stored }

        var bytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else { throw IdentityError.unavailable(randomStatus) }

        let value = Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard let data = value.data(using: .utf8) else { throw IdentityError.unavailable(errSecParam) }

        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem, let stored = read() { return stored }
        guard status == errSecSuccess else { throw IdentityError.unavailable(status) }
        return value
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }
}
