import Foundation
import Security

/// Acesso mínimo ao Keychain do macOS (senha genérica por conta).
enum KeychainStore {
    private static let service = "com.v1r8.downside"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Cofre da chave da API do Claude: vive no Keychain (cifrado pelo
/// sistema), com migração silenciosa da preferência antiga em
/// UserDefaults e cache em memória para evitar consultas repetidas.
enum APIKeyVault {
    private static let account = "claudeAPIKey"
    private static var cache = ""
    private static var loaded = false

    static var key: String? {
        if !loaded { load() }
        return cache.isEmpty ? nil : cache
    }

    static func set(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        cache = trimmed
        loaded = true
        if trimmed.isEmpty {
            KeychainStore.delete(account)
        } else {
            KeychainStore.write(trimmed, account: account)
        }
    }

    private static func load() {
        loaded = true
        // Migração: a chave que vivia em texto puro no UserDefaults
        // passa para o Keychain e some do arquivo de preferências.
        if let legacy = UserDefaults.standard.string(forKey: PrefKey.claudeAPIKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !legacy.isEmpty {
            KeychainStore.write(legacy, account: account)
            UserDefaults.standard.removeObject(forKey: PrefKey.claudeAPIKey)
            cache = legacy
            return
        }
        UserDefaults.standard.removeObject(forKey: PrefKey.claudeAPIKey)
        cache = KeychainStore.read(account) ?? ""
    }
}
