import Foundation
import Security

/// Minimal generic-password Keychain wrapper.
final class KeychainStore: @unchecked Sendable {
    let service: String

    init(service: String = "com.tempo.app") {
        self.service = service
    }

    func string(forKey key: String) -> String? {
        var query: [String: Any] = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func set(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = baseQuery(forKey: key)
        SecItemDelete(query as CFDictionary)
        var attributes: [String: Any] = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    @discardableResult
    func remove(_ key: String) -> Bool {
        let query: [String: Any] = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [:]
        query[kSecClass as String] = kSecClassGenericPassword
        query[kSecAttrService as String] = service
        query[kSecAttrAccount as String] = key
        return query
    }
}

/// Where the API bearer token lives.
protocol TokenStore: Sendable {
    var token: String? { get }
    func save(_ token: String)
    func clear()
}

final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    private let keychain: KeychainStore
    private let key: String

    init(keychain: KeychainStore = KeychainStore(), key: String = "auth.token") {
        self.keychain = keychain
        self.key = key
    }

    var token: String? {
        keychain.string(forKey: key)
    }

    func save(_ token: String) {
        keychain.set(token, forKey: key)
    }

    func clear() {
        keychain.remove(key)
    }
}

/// Used by previews and tests so they never touch the real Keychain.
final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    init(token: String? = nil) {
        self.value = token
    }

    var token: String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func save(_ token: String) {
        lock.lock()
        value = token
        lock.unlock()
    }

    func clear() {
        lock.lock()
        value = nil
        lock.unlock()
    }
}
