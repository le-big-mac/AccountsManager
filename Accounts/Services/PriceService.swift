import Foundation

actor PriceService {
    static let shared = PriceService()

    private let baseURL = "https://financialmodelingprep.com/api/v3"
    private var cache: [String: CachedQuote] = [:]

    struct CachedQuote {
        let price: Decimal
        let change: Decimal
        let changePercent: Double
        let fetchedAt: Date
    }

    struct FMPQuote: Decodable {
        let symbol: String?
        let price: Double?
        let change: Double?
        let changesPercentage: Double?
        let name: String?
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

    func fetchQuote(ticker: String) async throws -> CachedQuote {
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

                let quote = try await fetchQuote(ticker: ticker)
                await MainActor.run {
                    holding.lastPrice = quote.price
                    holding.lastPriceDate = Date()
                    if holding.ticker == nil {
                        holding.ticker = ticker
                    }
                }
            } catch {
                continue
            }
        }
    }

    func clearCache() {
        cache.removeAll()
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
