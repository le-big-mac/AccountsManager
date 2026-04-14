import Foundation

@MainActor
final class PriceService {
    static let shared = PriceService()

    private let stableBaseURL = "https://financialmodelingprep.com/stable"
    private var cache: [String: CachedQuote] = [:]
    private var fxCache: [String: CachedFXRate] = [:]
    private var vanguardProductsCache: [VanguardProduct]?

    struct CachedQuote {
        let price: Decimal
        let currency: String
        let change: Decimal
        let changePercent: Double
        let fetchedAt: Date
    }

    struct CachedFXRate {
        let rate: Decimal
        let fetchedAt: Date
    }

    struct FMPQuote: Decodable {
        let symbol: String?
        let price: Double?
        let change: Double?
        let changesPercentage: Double?
        let changePercentage: Double?
        let name: String?
        let currency: String?
    }

    struct FMPSearchResult: Decodable {
        let symbol: String?
        let name: String?
        let currency: String?
        let exchangeShortName: String?
    }

    struct VanguardProduct: Decodable {
        let id: String?
        let name: String?
        let portId: String?
        let sedol: String?
    }

    struct VanguardFund: Decodable {
        let displayName: String?
        let name: String?
        let ticker: String?
        let sedol: String?
        let portId: String?
        let navPrice: VanguardNAVPrice?
    }

    struct VanguardNAVPrice: Decodable {
        let value: String?
        let currency: String?
        let percentChange: String?
        let amountChange: String?
        let asOfDate: String?
    }

    private var apiKey: String? {
        KeychainHelper.load(.fmpApiKey)
    }

    var isConfigured: Bool {
        apiKey != nil && !(apiKey?.isEmpty ?? true)
    }

    func fetchQuote(ticker: String, fallbackCurrency: String? = nil) async throws -> CachedQuote {
        if let cached = cache[ticker],
           Date().timeIntervalSince(cached.fetchedAt) < 300 {
            return cached
        }

        guard let apiKey else {
            throw PriceError.notConfigured
        }

        var components = URLComponents(string: "\(stableBaseURL)/quote")!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: ticker),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        let url = components.url!
        let (data, _) = try await URLSession.shared.data(from: url)
        let quotes = try JSONDecoder().decode([FMPQuote].self, from: data)

        guard let quote = quotes.first, let price = quote.price else {
            throw PriceError.noData
        }

        let cached = CachedQuote(
            price: Decimal(price),
            currency: normalizedCurrency(quote.currency ?? fallbackCurrency ?? inferredCurrency(for: ticker)),
            change: Decimal(quote.change ?? 0),
            changePercent: quote.changePercentage ?? quote.changesPercentage ?? 0,
            fetchedAt: Date()
        )
        cache[ticker] = cached
        return cached
    }

    func searchByISIN(isin: String) async throws -> String? {
        guard let apiKey else { throw PriceError.notConfigured }

        var components = URLComponents(string: "\(stableBaseURL)/search-symbol")!
        components.queryItems = [
            URLQueryItem(name: "query", value: isin),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        let url = components.url!
        let (data, _) = try await URLSession.shared.data(from: url)
        let results = try JSONDecoder().decode([FMPSearchResult].self, from: data)
        return results.first?.symbol
    }

    func fetchFXRateToGBP(from currency: String) async throws -> Decimal {
        let source = normalizedCurrency(currency)
        guard source != "GBP" else { return 1 }
        guard source != "GBX" else { return Decimal(string: "0.01") ?? 0.01 }

        let cacheKey = "\(source)GBP"
        if let cached = fxCache[cacheKey],
           Date().timeIntervalSince(cached.fetchedAt) < 3600 {
            return cached.rate
        }

        guard let apiKey else {
            throw PriceError.notConfigured
        }

        if let direct = try? await fetchFXPair("\(source)GBP", apiKey: apiKey) {
            fxCache[cacheKey] = CachedFXRate(rate: direct, fetchedAt: Date())
            return direct
        }

        if let inverse = try? await fetchFXPair("GBP\(source)", apiKey: apiKey), inverse != 0 {
            let rate = 1 / inverse
            fxCache[cacheKey] = CachedFXRate(rate: rate, fetchedAt: Date())
            return rate
        }

        throw PriceError.noData
    }

    private func fetchFXPair(_ pair: String, apiKey: String) async throws -> Decimal? {
        var components = URLComponents(string: "\(stableBaseURL)/quote")!
        components.queryItems = [
            URLQueryItem(name: "symbol", value: pair),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        let url = components.url!
        let (data, _) = try await URLSession.shared.data(from: url)
        let quotes = try JSONDecoder().decode([FMPQuote].self, from: data)
        guard let price = quotes.first?.price else { return nil }
        return Decimal(price)
    }

    func refreshHoldings(_ holdings: [Holding]) async {
        for holding in holdings {
            do {
                let quote: CachedQuote
                if let vanguardQuote = try await fetchVanguardQuote(for: holding) {
                    quote = vanguardQuote
                } else {
                    guard let identifier = holding.ticker ?? holding.isin else { continue }

                    var ticker = identifier
                    if holding.ticker == nil, let isin = holding.isin {
                        if let resolved = try await searchByISIN(isin: isin) {
                            ticker = resolved
                        } else {
                            continue
                        }
                    }

                    let fallbackCurrency = holding.ticker == nil ? holding.priceCurrency : nil
                    quote = try await fetchQuote(ticker: ticker, fallbackCurrency: fallbackCurrency)
                    if holding.ticker == nil {
                        holding.ticker = ticker
                    }
                }
                let fxRate = try await fetchFXRateToGBP(from: quote.currency)
                holding.lastPrice = quote.price
                holding.priceCurrency = quote.currency
                holding.fxRateToGBP = fxRate
                holding.fxRateDate = Date()
                holding.lastPriceDate = Date()
            } catch {
                continue
            }
        }
    }

    private func fetchVanguardQuote(for holding: Holding) async throws -> CachedQuote? {
        guard let portId = try await vanguardPortId(for: holding) else { return nil }
        let cacheKey = "vanguard:\(portId)"
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.fetchedAt) < 300 {
            return cached
        }

        let url = URL(string: "https://www.vanguardinvestor.co.uk/api/funds/\(portId)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let fund = try JSONDecoder().decode(VanguardFund.self, from: data)
        guard let navPrice = fund.navPrice,
              let valueText = navPrice.value,
              let price = Decimal(string: valueText.replacingOccurrences(of: ",", with: "")) else {
            throw PriceError.noData
        }

        let cached = CachedQuote(
            price: price,
            currency: normalizedCurrency(navPrice.currency ?? "GBP"),
            change: parsePercentOrAmount(navPrice.amountChange) ?? 0,
            changePercent: double(from: parsePercentOrAmount(navPrice.percentChange)) ?? 0,
            fetchedAt: Date()
        )
        cache[cacheKey] = cached
        if let ticker = fund.ticker, holding.ticker == nil {
            holding.ticker = ticker
        }
        if let sedol = fund.sedol, holding.sedol == nil {
            holding.sedol = sedol
        }
        return cached
    }

    private func vanguardPortId(for holding: Holding) async throws -> String? {
        let identifiers = [
            holding.ticker,
            holding.isin,
            holding.sedol,
            holding.name
        ]
            .compactMap { $0 }
            .map(normalizedIdentifier)

        if identifiers.contains("VAFTGAG") || identifiers.contains("GB00BD3RZ582") || identifiers.contains("BD3RZ58") {
            return "8617"
        }

        guard let product = try await vanguardProducts().first(where: { product in
            identifiers.contains(normalizedIdentifier(product.sedol))
                || identifiers.contains(normalizedIdentifier(product.id))
                || identifiers.contains(normalizedIdentifier(product.name))
        }) else {
            return nil
        }
        return product.portId
    }

    private func vanguardProducts() async throws -> [VanguardProduct] {
        if let vanguardProductsCache {
            return vanguardProductsCache
        }

        let url = URL(string: "https://www.vanguardinvestor.co.uk/api/productList")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let products = try JSONDecoder().decode([VanguardProduct].self, from: data)
        vanguardProductsCache = products
        return products
    }

    func refreshCashBalances(_ cashBalances: [CashBalance]) async {
        for cash in cashBalances {
            do {
                let fxRate = try await fetchFXRateToGBP(from: cash.currency)
                cash.fxRateToGBP = fxRate
                cash.fxRateDate = Date()
                cash.updatedAt = Date()
            } catch {
                continue
            }
        }
    }

    func clearCache() {
        cache.removeAll()
        fxCache.removeAll()
    }

    private func normalizedCurrency(_ currency: String) -> String {
        let trimmed = currency.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "GBp" || trimmed == "GBX" {
            return "GBX"
        }
        return trimmed.uppercased()
    }

    private func normalizedIdentifier(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
    }

    private func parsePercentOrAmount(_ value: String?) -> Decimal? {
        guard let value else { return nil }
        return Decimal(string: value
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func double(from decimal: Decimal?) -> Double? {
        guard let decimal else { return nil }
        return NSDecimalNumber(decimal: decimal).doubleValue
    }

    private func inferredCurrency(for ticker: String) -> String {
        let uppercased = ticker.uppercased()
        if uppercased.hasSuffix(".L") || uppercased.hasSuffix(".LON") {
            return "GBP"
        }
        return "USD"
    }
}

enum PriceError: LocalizedError {
    case notConfigured
    case noData
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .notConfigured: "FMP API key not configured. Go to Settings to add it."
        case .noData: "No price data available for this security."
        case .rateLimited: "API rate limit reached. Try again later."
        }
    }
}
