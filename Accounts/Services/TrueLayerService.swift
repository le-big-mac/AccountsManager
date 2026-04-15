import Foundation

actor TrueLayerService {
    static let shared = TrueLayerService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        return URLSession(configuration: config)
    }()

    private var isSandbox: Bool {
        KeychainHelper.load(.trueLayerClientId)?.hasPrefix("sandbox-") ?? false
    }

    private var authBaseURL: String {
        isSandbox ? "https://auth.truelayer-sandbox.com" : "https://auth.truelayer.com"
    }

    private var apiBaseURL: String {
        isSandbox ? "https://api.truelayer-sandbox.com/data/v1" : "https://api.truelayer.com/data/v1"
    }

    var isConfigured: Bool {
        let clientId = KeychainHelper.load(.trueLayerClientId)
        let clientSecret = KeychainHelper.load(.trueLayerClientSecret)
        return clientId != nil && clientSecret != nil
            && !(clientId?.isEmpty ?? true)
            && !(clientSecret?.isEmpty ?? true)
    }

    // MARK: - OAuth Flow

    struct AuthRequest {
        let url: URL
        let state: String
        let providerId: String?
    }

    /// Build the auth URL targeting a specific bank provider.
    func buildAuthURL(providerId: String? = nil, redirectURI: String = "accounts://truelayer-callback") -> AuthRequest? {
        guard let clientId = KeychainHelper.load(.trueLayerClientId) else { return nil }

        let state = UUID().uuidString
        let providers = providerId ?? "uk-ob-all"

        var components = URLComponents(string: "\(authBaseURL)/")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "scope", value: "accounts balance transactions info offline_access"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "providers", value: providers),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { return nil }
        return AuthRequest(url: url, state: state, providerId: providerId)
    }

    /// Known UK bank providers
    static let ukProviders: [(id: String, name: String)] = [
        ("ob-revolut", "Revolut"),
        ("ob-santander-personal", "Santander Personal"),
        ("ob-santander-business", "Santander Business"),
    ]

    /// Exchange the authorization code from the callback for access + refresh tokens.
    func exchangeCode(_ code: String, redirectURI: String = "accounts://truelayer-callback") async throws -> TokenPair {
        guard let clientId = KeychainHelper.load(.trueLayerClientId)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let clientSecret = KeychainHelper.load(.trueLayerClientSecret)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clientId.isEmpty, !clientSecret.isEmpty else {
            throw TrueLayerError.notConfigured
        }

        let url = URL(string: "\(authBaseURL)/connect/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = [
            "grant_type=authorization_code",
            "client_id=\(clientId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientId)",
            "client_secret=\(clientSecret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientSecret)",
            "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)",
            "code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code)",
        ].joined(separator: "&")
        request.httpBody = Data(bodyString.utf8)

        let (data, response) = try await session.data(for: request)

        // Check for error response from TrueLayer
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let errorBody = try? JSONDecoder().decode(TrueLayerErrorResponse.self, from: data) {
                throw TrueLayerError.apiError(errorBody.error, errorBody.errorDescription ?? "Unknown error")
            }
            let bodyString = String(data: data, encoding: .utf8) ?? "No response body"
            throw TrueLayerError.apiError("http_\(httpResponse.statusCode)", bodyString)
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        return TokenPair(
            accessToken: tokenResponse.accessToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
            refreshToken: tokenResponse.refreshToken
        )
    }

    struct RefreshResult {
        let accessToken: String
        let refreshToken: String?
    }

    /// Refresh an expired access token using a refresh token.
    func refreshAccessToken(refreshToken: String? = nil) async throws -> RefreshResult {
        guard let clientId = KeychainHelper.load(.trueLayerClientId),
              let clientSecret = KeychainHelper.load(.trueLayerClientSecret) else {
            throw TrueLayerError.notConfigured
        }
        let token = refreshToken ?? KeychainHelper.load(.trueLayerRefreshToken)
        guard let refreshToken = token else {
            throw TrueLayerError.notConfigured
        }

        let url = URL(string: "\(authBaseURL)/connect/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "refresh_token", value: refreshToken),
        ]
        request.httpBody = bodyComponents.percentEncodedQuery.flatMap { Data($0.utf8) }

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        return RefreshResult(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken
        )
    }

    // MARK: - Data API

    func listAccounts(accessToken: String) async throws -> [BankAccount] {
        let url = URL(string: "\(apiBaseURL)/accounts")!
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await session.data(for: request)
        logDataResponse("accounts", response: response, data: data)
        try validateHTTPResponse(response, data: data)
        let accountsResponse = try JSONDecoder().decode(AccountsResponse.self, from: data)
        return accountsResponse.results
    }

    func fetchBalanceSnapshot(accountId: String, accessToken: String) async throws -> BalanceSnapshot {
        let url = URL(string: "\(apiBaseURL)/accounts/\(accountId)/balance")!
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        let balancesResponse = try JSONDecoder().decode(BalancesResponse.self, from: data)

        guard let balance = balancesResponse.results.first else {
            throw TrueLayerError.noBalance
        }

        // TrueLayer returns balance in minor units (pence) for the v1 balances endpoint,
        // but the /accounts/{id}/balance endpoint may return in major units.
        // Handle both cases.
        let amount: Decimal
        if let current = balance.current {
            amount = current
        } else if let currentMinor = balance.currentBalanceInMinor {
            amount = Decimal(currentMinor) / 100
        } else {
            throw TrueLayerError.noBalance
        }

        return BalanceSnapshot(
            accountId: accountId,
            amount: amount,
            currency: normalizedCurrency(balance.currency)
        )
    }

    func fetchBalance(accountId: String, accessToken: String) async throws -> Decimal {
        try await fetchBalanceSnapshot(accountId: accountId, accessToken: accessToken).amount
    }

    func fetchTransactions(accountId: String, accessToken: String) async throws -> [TransactionSnapshot] {
        var components = URLComponents(string: "\(apiBaseURL)/accounts/\(accountId)/transactions")!
        components.queryItems = [
            URLQueryItem(name: "from", value: Self.apiDateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date())),
            URLQueryItem(name: "to", value: Self.apiDateFormatter.string(from: Date())),
        ]
        let url = components.url!
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
        let transactionsResponse = try JSONDecoder().decode(TransactionsResponse.self, from: data)
        return transactionsResponse.results.map { transaction in
            TransactionSnapshot(
                id: transaction.transactionId ?? "\(accountId):\(transaction.timestamp ?? ""):\(transaction.description ?? ""):\(transaction.amount?.description ?? "")",
                accountId: accountId,
                date: Self.parseDate(transaction.timestamp) ?? Date(),
                description: transaction.description ?? transaction.merchantName ?? "Transaction",
                amount: transaction.amount ?? 0,
                currency: normalizedCurrency(transaction.currency)
            )
        }
    }

    // MARK: - Models

    struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let tokenType: String
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
            case refreshToken = "refresh_token"
        }
    }

    struct TokenPair {
        let accessToken: String
        let expiresAt: Date
        let refreshToken: String?
    }

    struct BalanceSnapshot {
        let accountId: String
        let amount: Decimal
        let currency: String
    }

    struct TransactionSnapshot {
        let id: String
        let accountId: String
        let date: Date
        let description: String
        let amount: Decimal
        let currency: String
    }

    struct AccountsResponse: Decodable {
        let results: [BankAccount]
    }

    struct BankAccount: Decodable, Identifiable {
        let accountId: String
        let accountType: String?
        let displayName: String?
        let currency: String?
        let provider: AccountProvider?
        let accountNumber: AccountNumber?

        var id: String { accountId }

        var label: String {
            var parts: [String] = []
            if let type = accountType {
                parts.append(type.replacingOccurrences(of: "TRANSACTION", with: "Current")
                    .replacingOccurrences(of: "SAVINGS", with: "Savings")
                    .capitalized)
            }
            if let currency { parts.append(currency) }
            if let last4 = accountNumber?.number?.suffix(4) { parts.append("••\(last4)") }
            return parts.isEmpty ? (displayName ?? accountId) : parts.joined(separator: " · ")
        }

        enum CodingKeys: String, CodingKey {
            case accountId = "account_id"
            case accountType = "account_type"
            case displayName = "display_name"
            case currency
            case provider
            case accountNumber = "account_number"
        }
    }

    struct AccountNumber: Decodable {
        let iban: String?
        let number: String?
        let sortCode: String?
        let swiftBic: String?

        enum CodingKeys: String, CodingKey {
            case iban
            case number
            case sortCode = "sort_code"
            case swiftBic = "swift_bic"
        }
    }

    struct AccountProvider: Decodable {
        let displayName: String?
        let providerId: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case providerId = "provider_id"
        }
    }

    struct BalancesResponse: Decodable {
        let results: [BalanceResult]
    }

    struct BalanceResult: Decodable {
        let current: Decimal?
        let available: Decimal?
        let currency: String?
        let currentBalanceInMinor: Int?
        let availableBalanceInMinor: Int?

        enum CodingKeys: String, CodingKey {
            case current
            case available
            case currency
            case currentBalanceInMinor = "current_balance_in_minor"
            case availableBalanceInMinor = "available_balance_in_minor"
        }
    }

    struct TransactionsResponse: Decodable {
        let results: [TransactionResult]
    }

    struct TransactionResult: Decodable {
        let transactionId: String?
        let timestamp: String?
        let description: String?
        let merchantName: String?
        let amount: Decimal?
        let currency: String?

        enum CodingKeys: String, CodingKey {
            case transactionId = "transaction_id"
            case timestamp
            case description
            case merchantName = "merchant_name"
            case amount
            case currency
        }
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let errorBody = try? JSONDecoder().decode(TrueLayerErrorResponse.self, from: data) {
                throw TrueLayerError.apiError(errorBody.error, errorBody.errorDescription ?? "Unknown error")
            }
            let bodyString = String(data: data, encoding: .utf8) ?? "No response body"
            throw TrueLayerError.apiError("http_\(httpResponse.statusCode)", bodyString)
        }
    }

    private func logDataResponse(_ name: String, response: URLResponse, data: Data) {
        guard let httpResponse = response as? HTTPURLResponse else {
            DebugLog.write("TrueLayer \(name): non-HTTP response, \(data.count) bytes")
            return
        }

        let requestId = httpResponse.value(forHTTPHeaderField: "x-request-id") ?? "nil"
        let cacheControl = httpResponse.value(forHTTPHeaderField: "cache-control") ?? "nil"
        DebugLog.write("TrueLayer \(name): status=\(httpResponse.statusCode) bytes=\(data.count) requestId=\(requestId) cacheControl=\(cacheControl)")

        if let body = String(data: data, encoding: .utf8) {
            DebugLog.write("TrueLayer \(name) body: \(body.prefix(4000))")
        }
    }

    private func normalizedCurrency(_ currency: String?) -> String {
        let trimmed = currency?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "GBP" : trimmed.uppercased()
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) {
            return date
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: value)
    }

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct TrueLayerErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

enum TrueLayerError: LocalizedError {
    case notConfigured
    case noBalance
    case authenticationFailed
    case tokenExpired
    case apiError(String, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "TrueLayer credentials not configured. Go to Settings."
        case .noBalance: "No balance data returned from the bank."
        case .authenticationFailed: "Bank authentication failed. Please reconnect."
        case .tokenExpired: "Bank connection expired. Please reconnect (90-day limit)."
        case .apiError(let code, let message): "TrueLayer error (\(code)): \(message)"
        }
    }
}
