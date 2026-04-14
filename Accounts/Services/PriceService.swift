import Foundation

@MainActor
final class PriceService {
    static let shared = PriceService()

    private let baseURL = "https://financialmodelingprep.com/api/v3"
    private var cache: [String: CachedQuote] = [:]
    private var fxCache: [String: CachedFXRate] = [:]

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
        let name: String?
        let currency: String?
    }

    struct FMPSearchResult: Decodable {
        let symbol: String?
        let name: String?
        let currency: String?
        let exchangeShortName: String?
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

        let url = URL(string: "\(baseURL)/quote/\(ticker)?apikey=\(apiKey)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let quotes = try JSONDecoder().decode([FMPQuote].self, from: data)

        guard let quote = quotes.first, let price = quote.price else {
            throw PriceError.noData
        }

        let cached = CachedQuote(
            price: Decimal(price),
            currency: normalizedCurrency(quote.currency ?? fallbackCurrency ?? inferredCurrency(for: ticker)),
            change: Decimal(quote.change ?? 0),
            changePercent: quote.changesPercentage ?? 0,
            fetchedAt: Date()
        )
        cache[ticker] = cached
        return cached
    }

    func searchByISIN(isin: String) async throws -> String? {
        guard let apiKey else { throw PriceError.notConfigured }

        let url = URL(string: "\(baseURL)/search?query=\(isin)&apikey=\(apiKey)")!
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

        if let direct = try await fetchFXPair("\(source)GBP", apiKey: apiKey) {
            fxCache[cacheKey] = CachedFXRate(rate: direct, fetchedAt: Date())
            return direct
        }

        if let inverse = try await fetchFXPair("GBP\(source)", apiKey: apiKey), inverse != 0 {
            let rate = 1 / inverse
            fxCache[cacheKey] = CachedFXRate(rate: rate, fetchedAt: Date())
            return rate
        }

        throw PriceError.noData
    }

    private func fetchFXPair(_ pair: String, apiKey: String) async throws -> Decimal? {
        let url = URL(string: "\(baseURL)/quote/\(pair)?apikey=\(apiKey)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let quotes = try JSONDecoder().decode([FMPQuote].self, from: data)
        guard let price = quotes.first?.price else { return nil }
        return Decimal(price)
    }

    func refreshHoldings(_ holdings: [Holding]) async {
        for holding in holdings {
            guard let identifier = holding.ticker ?? holding.isin else { continue }

            do {
                var ticker = identifier
                if holding.ticker == nil, let isin = holding.isin {
                    if let resolved = try await searchByISIN(isin: isin) {
                        ticker = resolved
                    } else {
                        continue
                    }
                }

                let fallbackCurrency = holding.ticker == nil ? holding.priceCurrency : nil
                let quote = try await fetchQuote(ticker: ticker, fallbackCurrency: fallbackCurrency)
                let fxRate = try await fetchFXRateToGBP(from: quote.currency)
                holding.lastPrice = quote.price
                holding.priceCurrency = quote.currency
                holding.fxRateToGBP = fxRate
                holding.fxRateDate = Date()
                holding.lastPriceDate = Date()
                if holding.ticker == nil {
                    holding.ticker = ticker
                }
            } catch {
                continue
            }
        }
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
