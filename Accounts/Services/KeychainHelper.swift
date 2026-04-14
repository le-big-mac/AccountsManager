import Foundation

enum KeychainHelper {
    enum Key: String {
        case fmpApiKey = "com.accounts.fmp-api-key"
        case trueLayerClientId = "com.accounts.truelayer-client-id"
        case trueLayerClientSecret = "com.accounts.truelayer-client-secret"
        case trueLayerRefreshToken = "com.accounts.truelayer-refresh-token"
        case trueLayerAccessToken = "com.accounts.truelayer-access-token"
        case trueLayerTokenExpiry = "com.accounts.truelayer-token-expiry"
        case snapTradeClientId = "com.accounts.snaptrade-client-id"
        case snapTradeConsumerKey = "com.accounts.snaptrade-consumer-key"
        case snapTradeUserId = "com.accounts.snaptrade-user-id"
        case snapTradeUserSecret = "com.accounts.snaptrade-user-secret"
    }

    private static let storeURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Accounts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("credentials.json")
    }()

    private static func loadStore() -> [String: String] {
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL),
              !data.isEmpty,
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func saveStore(_ store: [String: String]) {
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    static func save(_ value: String, for key: Key) {
        var store = loadStore()
        store[key.rawValue] = value
        saveStore(store)
    }

    static func load(_ key: Key) -> String? {
        loadStore()[key.rawValue]
    }

    static func delete(_ key: Key) {
        var store = loadStore()
        store.removeValue(forKey: key.rawValue)
        saveStore(store)
    }
}
