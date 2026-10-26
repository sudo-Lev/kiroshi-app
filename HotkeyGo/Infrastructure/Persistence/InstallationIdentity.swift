import Foundation
import Security

/// A random, device-local identifier used to associate usage and billing state.
/// It is intentionally not an OpenAI or Paddle credential.
enum InstallationIdentity {
    private static let service = "ai.hotkeygo.app"
    private static let previousService = "ai.qwixit.app"
    private static let account = "installation-id"

    enum IdentityError: LocalizedError {
        case unavailable(OSStatus)

        var errorDescription: String? {
            "hotkeygo could not access its secure device identity (Keychain error \(statusCode))."
        }

        private var statusCode: OSStatus {
            switch self { case .unavailable(let status): status }
        }
    }

    static func current() throws -> String {
        if let stored = try read(service: service) { return stored }
        if let previous = try read(service: previousService) {
            let status = store(previous)
            if status == errSecSuccess { return previous }
            if status == errSecDuplicateItem, let stored = try read(service: service) {
                return stored
            }
            throw IdentityError.unavailable(status)
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard randomStatus == errSecSuccess else { throw IdentityError.unavailable(randomStatus) }

        let value = Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let status = store(value)
        if status == errSecSuccess { return value }
        if status == errSecDuplicateItem, let stored = try read(service: service) { return stored }
        throw IdentityError.unavailable(status)
    }

    private static func store(_ value: String) -> OSStatus {
        guard let data = value.data(using: .utf8) else { return errSecParam }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(item as CFDictionary, nil)
    }

    private static func read(service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw IdentityError.unavailable(status) }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { throw IdentityError.unavailable(errSecDecode) }
        return value
    }
}
