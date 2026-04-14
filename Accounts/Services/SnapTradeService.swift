import CryptoKit
import Foundation

@MainActor
final class SnapTradeService {
    static let shared = SnapTradeService()

    private let baseURL = URL(string: "https://api.snaptrade.com/api/v1")!

    var isConfigured: Bool {
        credentials != nil
    }

    private var credentials: (clientId: String, consumerKey: String)? {
        guard let clientId = KeychainHelper.load(.snapTradeClientId)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let consumerKey = KeychainHelper.load(.snapTradeConsumerKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clientId.isEmpty,
              !consumerKey.isEmpty else {
            return nil
        }
        return (clientId, consumerKey)
    }

    func ensureUser() async throws -> SnapTradeUser {
        if let userId = KeychainHelper.load(.snapTradeUserId),
           let userSecret = KeychainHelper.load(.snapTradeUserSecret),
           !userId.isEmpty,
           !userSecret.isEmpty {
            return SnapTradeUser(userId: userId, userSecret: userSecret)
        }

        let userId = "accounts-\(UUID().uuidString.lowercased())"
        let response: SnapTradeUser = try await request(
            method: "POST",
            path: "/snapTrade/registerUser",
            queryItems: [],
            body: ["userId": .string(userId)]
        )
        KeychainHelper.save(response.userId, for: .snapTradeUserId)
        KeychainHelper.save(response.userSecret, for: .snapTradeUserSecret)
        return response
    }

    func connectionPortalURL(
        broker: String = "ROBINHOOD",
        redirectURL: String = "accounts://snaptrade-callback"
    ) async throws -> URL {
        let user = try await ensureUser()
        let response: SnapTradeLoginResponse = try await request(
            method: "POST",
            path: "/snapTrade/login",
            queryItems: [
                URLQueryItem(name: "userId", value: user.userId),
                URLQueryItem(name: "userSecret", value: user.userSecret)
            ],
            body: [
                "broker": .string(broker),
                "connectionType": .string("read"),
                "connectionPortalVersion": .string("v4"),
                "customRedirect": .string(redirectURL),
                "immediateRedirect": .bool(true),
                "showCloseButton": .bool(true)
            ]
        )
        guard let url = URL(string: response.redirectURI) else {
            throw SnapTradeError.invalidResponse
        }
        return url
    }

    func listAccounts() async throws -> [SnapTradeAccount] {
        let user = try await ensureUser()
        return try await request(
            method: "GET",
            path: "/accounts",
            queryItems: [
                URLQueryItem(name: "userId", value: user.userId),
                URLQueryItem(name: "userSecret", value: user.userSecret)
            ],
            body: nil as [String: JSONValue]?
        )
    }

    func refreshConnection(authorizationId: String) async throws {
        let user = try await ensureUser()
        let _: SnapTradeRefreshResponse = try await request(
            method: "POST",
            path: "/authorizations/\(authorizationId)/refresh",
            queryItems: [
                URLQueryItem(name: "userId", value: user.userId),
                URLQueryItem(name: "userSecret", value: user.userSecret)
            ],
            body: nil as [String: JSONValue]?
        )
    }

    func holdings(accountId: String) async throws -> SnapTradeHoldingsResponse {
        let user = try await ensureUser()
        return try await request(
            method: "GET",
            path: "/accounts/\(accountId)/holdings",
            queryItems: [
                URLQueryItem(name: "userId", value: user.userId),
                URLQueryItem(name: "userSecret", value: user.userSecret)
            ],
            body: nil as [String: JSONValue]?
        )
    }

    private func request<Response: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        body: [String: JSONValue]?
    ) async throws -> Response {
        guard let credentials else { throw SnapTradeError.notConfigured }

        let timestamp = String(Int(Date().timeIntervalSince1970.rounded()))
        var allQueryItems = [
            URLQueryItem(name: "clientId", value: credentials.clientId),
            URLQueryItem(name: "timestamp", value: timestamp)
        ]
        allQueryItems.append(contentsOf: queryItems)

        var components = URLComponents(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false)!
        components.queryItems = allQueryItems
        guard let url = components.url else { throw SnapTradeError.invalidResponse }

        let bodyData = body.map { sortedJSONData($0) }
        let query = components.percentEncodedQuery ?? ""
        let signaturePayload = sortedJSONString(.object([
            "content": body.map(JSONValue.object) ?? .null,
            "path": .string("/api/v1\(path)"),
            "query": .string(query)
        ]))
        let signature = hmacSHA256Base64(message: signaturePayload, key: credentials.consumerKey)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(signature, forHTTPHeaderField: "Signature")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            throw SnapTradeError.api(message)
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func sortedJSONData(_ object: [String: JSONValue]) -> Data {
        Data(sortedJSONString(.object(object)).utf8)
    }

    private func sortedJSONString(_ value: JSONValue) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            return NSDecimalNumber(decimal: value).stringValue
        case .string(let value):
            let data = try? JSONEncoder().encode(value)
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        case .object(let object):
            let pairs = object.keys.sorted().map { key in
                "\(sortedJSONString(.string(key))):\(sortedJSONString(object[key] ?? .null))"
            }
            return "{\(pairs.joined(separator: ","))}"
        case .array(let array):
            return "[\(array.map(sortedJSONString).joined(separator: ","))]"
        }
    }

    private func hmacSHA256Base64(message: String, key: String) -> String {
        let symmetricKey = SymmetricKey(data: Data(key.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: symmetricKey)
        return Data(code).base64EncodedString()
    }
}

enum JSONValue {
    case null
    case bool(Bool)
    case number(Decimal)
    case string(String)
    case object([String: JSONValue])
    case array([JSONValue])
}

struct SnapTradeUser: Decodable {
    let userId: String
    let userSecret: String
}

struct SnapTradeLoginResponse: Decodable {
    let redirectURI: String
    let sessionId: String?
}

struct SnapTradeRefreshResponse: Decodable {}

struct SnapTradeAccount: Decodable, Identifiable {
    let id: String
    let brokerageAuthorization: String?
    let name: String?
    let institutionName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case brokerageAuthorization = "brokerage_authorization"
        case name
        case institutionName = "institution_name"
    }
}

struct SnapTradeHoldingsResponse: Decodable {
    let account: SnapTradeAccount?
    let balances: [SnapTradeBalance]?
    let positions: [SnapTradePosition]?
}

struct SnapTradeBalance: Decodable {
    let currency: SnapTradeCurrency?
    let cash: Decimal?
}

struct SnapTradePosition: Decodable {
    let symbol: SnapTradePositionSymbol?
    let price: Decimal?
    let units: Decimal?
    let fractionalUnits: Decimal?
    let currency: SnapTradeCurrency?
    let cashEquivalent: Bool?

    enum CodingKeys: String, CodingKey {
        case symbol
        case price
        case units
        case fractionalUnits = "fractional_units"
        case currency
        case cashEquivalent = "cash_equivalent"
    }
}

struct SnapTradePositionSymbol: Decodable {
    let symbol: SnapTradeSecurity?
}

struct SnapTradeSecurity: Decodable {
    let symbol: String?
    let rawSymbol: String?
    let description: String?
    let currency: SnapTradeCurrency?

    enum CodingKeys: String, CodingKey {
        case symbol
        case rawSymbol = "raw_symbol"
        case description
        case currency
    }
}

struct SnapTradeCurrency: Decodable {
    let code: String?
}

enum SnapTradeError: LocalizedError {
    case notConfigured
    case invalidResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "SnapTrade credentials are not configured. Add them in Settings."
        case .invalidResponse:
            "SnapTrade returned an invalid response."
        case .api(let message):
            "SnapTrade API error: \(message)"
        }
    }
}
