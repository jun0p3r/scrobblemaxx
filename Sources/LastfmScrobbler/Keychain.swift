import Foundation
import Security

/// Everything secret lives in a single Keychain item so a rebuilt (re-signed) app
/// triggers at most one access prompt.
struct Credentials: Codable, Equatable {
    var apiKey = ""
    var apiSecret = ""
    var sessionKey: String?
    var username: String?

    var hasAPIKeys: Bool { !apiKey.isEmpty && !apiSecret.isEmpty }
    var isLoggedIn: Bool { hasAPIKeys && sessionKey != nil }
}

enum Keychain {
    private static let service = "com.fr.LastfmScrobbler"
    private static let account = "credentials"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> Credentials {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let creds = try? JSONDecoder().decode(Credentials.self, from: data)
        else { return Credentials() }
        return creds
    }

    static func save(_ creds: Credentials) {
        guard let data = try? JSONEncoder().encode(creds) else { return }
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
