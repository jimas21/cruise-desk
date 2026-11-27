import Foundation
import Security

/// Small wrapper over the Keychain for the server address and app token. Values never leave this device.
enum Keychain {
    private static let service = "dealdesk"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    /// Writes a value, or deletes it when the value is nil or empty.
    static func write(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Where the deal server is and how the app proves who it is.
///
/// The build carries a base URL and app token (Info.plist `DDBaseURL` / `DDAppToken`, injected by CI). On launch
/// the token is copied into the Keychain. Settings can override either one by pasting, for recovery; an override
/// wins over the built-in value until it is cleared.
enum Connection {
    private static let bundledTokenKey = "bundled.token"
    private static let customURLKey = "custom.baseURL"
    private static let customTokenKey = "custom.token"

    static var bundledBaseURL: String { infoString("DDBaseURL") }

    private static func infoString(_ key: String) -> String {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return value.trimmed
    }

    static func isPlaceholder(_ value: String) -> Bool {
        value.isEmpty || value.contains("REPLACE") || value.contains("$(")
    }

    /// Copies the built-in token into the Keychain (again whenever a new build carries a different one).
    static func bootstrap() {
        let token = infoString("DDAppToken")
        guard !isPlaceholder(token) else { return }
        if Keychain.read(bundledTokenKey) != token {
            Keychain.write(token, for: bundledTokenKey)
        }
    }

    static var customBaseURL: String? { Keychain.read(customURLKey) }
    static var hasCustomToken: Bool { Keychain.read(customTokenKey)?.isEmpty == false }
    static var hasBundledToken: Bool { Keychain.read(bundledTokenKey)?.isEmpty == false }
    static var isCustom: Bool { customBaseURL != nil || hasCustomToken }

    static var baseURL: String {
        if let custom = customBaseURL, !custom.isEmpty { return custom }
        let bundled = bundledBaseURL
        return isPlaceholder(bundled) ? "" : bundled
    }

    private static var token: String? {
        if let custom = Keychain.read(customTokenKey), !custom.isEmpty { return custom }
        return Keychain.read(bundledTokenKey)
    }

    /// "https://host[:port][/path]" without a trailing slash, or nil if it is not a usable address.
    static func normalized(_ text: String) -> String? {
        var value = text.trimmed
        while value.hasSuffix("/") { value.removeLast() }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty else { return nil }
        return value
    }

    static var isConfigured: Bool { client() != nil }

    static func client() -> APIClient? {
        guard let base = normalized(Connection.baseURL), let token = Connection.token, !token.isEmpty else { return nil }
        return APIClient(base: base, token: token)
    }

    /// Saves pasted values. Empty fields leave that value as it was.
    static func saveCustom(baseURL: String, token: String) {
        let url = baseURL.trimmed
        if !url.isEmpty, url != bundledBaseURL { Keychain.write(normalized(url) ?? url, for: customURLKey) }
        if url == bundledBaseURL { Keychain.write(nil, for: customURLKey) }
        let pasted = token.trimmed
        if !pasted.isEmpty { Keychain.write(pasted, for: customTokenKey) }
    }

    static func clearCustom() {
        Keychain.write(nil, for: customURLKey)
        Keychain.write(nil, for: customTokenKey)
    }
}

/// The on-disk cache and write queue (JSON in Application Support), so the app opens instantly and works offline.
enum Disk {
    private static var folder: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("DealDesk", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(name),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }
}
