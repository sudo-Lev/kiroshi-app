import Foundation
import Security

enum KeychainStore {
    static let service = "ai.qwixit.app"
    static let account = "openai-api-key"

    enum KeychainError: LocalizedError {
        case invalidValue
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidValue: return "The API key is empty or invalid."
            case .unexpectedStatus(let status):
                return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
            }
        }
    }

    static func saveAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("sk-"), let data = trimmed.data(using: .utf8) else {
            throw KeychainError.invalidValue
        }

        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = lookup
            attributes.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func apiKey() -> String? {
        if let key = storedAPIKey() { return key }
        let environmentKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return environmentKey?.hasPrefix("sk-") == true ? environmentKey : nil
    }

    static func storedAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let key = String(data: data, encoding: .utf8) {
            return key
        }
        return nil
    }

    static func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
