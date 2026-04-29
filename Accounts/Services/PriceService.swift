import Foundation

@MainActor
final class PriceService {
    static let shared = PriceService()

    private let stableBaseURL = "https://financialmodelingprep.com/stable"
    private var cache: [String: CachedQuote] = [:]
    private var fxCache: [String: CachedFXRate] = [:]
    private var analystRatingCache: [String: CachedAnalystRating] = [:]
    private var securityMetadataCache: [String: SecurityMetadata] = [:]
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

    struct CachedAnalystRating {
        let consensus: String
        let score: Decimal?
        let count: Int?
        let sourceUpdatedAt: Date?
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

    struct FidelityFactsheetPage: Decodable {
        let props: FidelityProps
    }

    struct FidelityProps: Decodable {
        let pageProps: FidelityPageProps
    }

    struct FidelityPageProps: Decodable {
        let initialState: FidelityInitialState
    }

    struct FidelityInitialState: Decodable {
        let fund: FidelityFundState
    }

    struct FidelityFundState: Decodable {
        let priceDtls: FidelityPriceDetails?
    }

    struct FidelityPriceDetails: Decodable {
        let lastBuySellPrice: String?
        let changeAbsolute: String?
        let changePercentage: String?
        let currency: String?
    }

    struct HLFactsheetPage: Decodable {
        let props: HLProps
    }

    struct HLProps: Decodable {
        let pageProps: HLPageProps
    }

    struct HLPageProps: Decodable {
        let investmentDetails: HLInvestmentDetails
    }

    struct HLInvestmentDetails: Decodable {
        let sedol: String?
        let isin: String?
        let epicCode: String?
        let sell: HLMoney?
        let buy: HLMoney?
        let close: HLMoney?
        let previousChange: HLPreviousChange?
    }

    struct HLMoney: Decodable {
        let currency: String?
        let value: Decimal?
    }

    struct HLPreviousChange: Decodable {
        let percent: Double?
        let price: HLMoney?
    }

    private var apiKey: String? {
        KeychainHelper.load(.fmpApiKey)
    }

    var isConfigured: Bool {
        apiKey != nil && !(apiKey?.isEmpty ?? true)
    }

    func primeSecurityMetadata(_ metadata: [SecurityMetadata]) {
        for item in metadata {
            securityMetadataCache[item.securityKey] = item
        }
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
        for (index, holding) in holdings.enumerated() {
            if index.isMultiple(of: 4) {
                await Task.yield()
            }
            _ = securityMetadata(for: holding)
            do {
                let quote: CachedQuote
                if let giltQuote = try await fetchHLGiltQuote(for: holding) {
                    quote = giltQuote
                } else if let vanguardQuote = try await fetchVanguardQuote(for: holding) {
                    quote = vanguardQuote
                } else if let fidelityQuote = try await fetchFidelityFundQuote(for: holding) {
                    quote = fidelityQuote
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
        await refreshAnalystRatings(holdings)
    }

    func refreshAnalystRatings(_ holdings: [Holding]) async {
        var refreshedTickers: Set<String> = []
        for holding in holdings {
            guard supportsAnalystRatings(for: holding),
                  needsAnalystRatingRefresh(for: holding),
                  let ticker = holding.ticker,
                  !ticker.isEmpty,
                  !refreshedTickers.contains(ticker) else {
                continue
            }
            guard !Task.isCancelled else { return }

            let metadata = securityMetadata(for: holding)
            do {
                let rating = try await fetchStockAnalysisRating(ticker: ticker)
                metadata.analystConsensusRatingRaw = rating.consensus
                metadata.analystRatingScore = rating.score
                metadata.analystRatingCount = rating.count
                metadata.analystRatingSource = "StockAnalysis"
                metadata.analystRatingError = nil
                metadata.analystRatingUpdatedAt = Date()
                refreshedTickers.insert(ticker)
            } catch {
                metadata.analystRatingError = "Analyst rating refresh failed: \(error.localizedDescription)"
                refreshedTickers.insert(ticker)
            }
        }
    }

    func refreshHoldingFXRates(_ holdings: [Holding]) async {
        for holding in holdings {
            do {
                let fxRate = try await fetchFXRateToGBP(from: holding.priceCurrency)
                holding.fxRateToGBP = fxRate
                holding.fxRateDate = Date()
            } catch {
                continue
            }
        }
    }

    private func fetchStockAnalysisRating(ticker: String) async throws -> CachedAnalystRating {
        let normalizedTicker = ticker.uppercased()
        if let cached = analystRatingCache[normalizedTicker],
           Date().timeIntervalSince(cached.fetchedAt) < 21_600 {
            return cached
        }

        let url = URL(string: "https://stockanalysis.com/stocks/\(normalizedTicker.lowercased())/forecast/")!
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw PriceError.sourceUnavailable("StockAnalysis returned HTTP \(httpResponse.statusCode).")
        }
        guard let html = String(data: data, encoding: .utf8),
              let recommendation = latestStockAnalysisRecommendation(from: html),
              let consensus = recommendation["consensus"] as? String,
              AnalystConsensusRating.from(consensus) != nil else {
            throw PriceError.sourceUnavailable("StockAnalysis forecast page did not contain the expected analyst consensus data.")
        }

        let cached = CachedAnalystRating(
            consensus: consensus,
            score: decimal(from: recommendation["score"]),
            count: int(from: recommendation["total"]),
            sourceUpdatedAt: date(from: recommendation["updated"]),
            fetchedAt: Date()
        )
        analystRatingCache[normalizedTicker] = cached
        return cached
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

    private func fetchFidelityFundQuote(for holding: Holding) async throws -> CachedQuote? {
        guard holding.assetClass == .fund, let isin = holding.isin else { return nil }

        let cacheKey = "fidelity:\(isin)"
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.fetchedAt) < 300 {
            return cached
        }

        let url = URL(string: "https://www.fidelity.co.uk/factsheet-data/factsheet/\(isin)/performance")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8),
              let jsonData = nextDataJSON(from: html) else {
            throw PriceError.noData
        }

        let page = try JSONDecoder().decode(FidelityFactsheetPage.self, from: jsonData)
        guard let priceDetails = page.props.pageProps.initialState.fund.priceDtls,
              let valueText = priceDetails.lastBuySellPrice,
              let price = Decimal(string: valueText.replacingOccurrences(of: ",", with: "")) else {
            throw PriceError.noData
        }

        let cached = CachedQuote(
            price: price,
            currency: normalizedCurrency(priceDetails.currency ?? holding.priceCurrency),
            change: parsePercentOrAmount(priceDetails.changeAbsolute) ?? 0,
            changePercent: double(from: parsePercentOrAmount(priceDetails.changePercentage)) ?? 0,
            fetchedAt: Date()
        )
        cache[cacheKey] = cached
        return cached
    }

    private func fetchHLGiltQuote(for holding: Holding) async throws -> CachedQuote? {
        guard holding.assetClass == .gilt,
              let sedol = holding.sedol?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sedol.isEmpty else {
            return nil
        }

        let normalizedSEDOL = normalizedIdentifier(sedol)
        let cacheKey = "hl-gilt:\(normalizedSEDOL)"
        if let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.fetchedAt) < 300 {
            return cached
        }

        let url = URL(string: "https://www.hl.co.uk/shares/shares-search-results/\(normalizedSEDOL)")!
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8),
              let jsonData = nextDataJSON(from: html) else {
            throw PriceError.noData
        }

        let page = try JSONDecoder().decode(HLFactsheetPage.self, from: jsonData)
        let details = page.props.pageProps.investmentDetails
        guard normalizedIdentifier(details.sedol) == normalizedSEDOL || normalizedIdentifier(details.isin) == normalizedIdentifier(holding.isin) else {
            throw PriceError.noData
        }

        let price = midPrice(sell: details.sell?.value, buy: details.buy?.value)
            ?? details.close?.value
        guard let price else {
            throw PriceError.noData
        }

        let cached = CachedQuote(
            price: price,
            currency: normalizedCurrency(details.sell?.currency ?? details.buy?.currency ?? details.close?.currency ?? "GBP"),
            change: details.previousChange?.price?.value ?? 0,
            changePercent: details.previousChange?.percent ?? 0,
            fetchedAt: Date()
        )
        cache[cacheKey] = cached

        if let epicCode = details.epicCode, holding.ticker == nil {
            holding.ticker = epicCode
        }
        if let isin = details.isin, holding.isin == nil {
            holding.isin = isin
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
        for (index, cash) in cashBalances.enumerated() {
            if index.isMultiple(of: 8) {
                await Task.yield()
            }
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
        analystRatingCache.removeAll()
        securityMetadataCache.removeAll()
    }

    private func supportsAnalystRatings(for holding: Holding) -> Bool {
        switch holding.assetClass {
        case .stock, .etf:
            return holding.ticker != nil
        case .cash, .fund, .gilt, .other:
            return false
        }
    }

    private func needsAnalystRatingRefresh(for holding: Holding) -> Bool {
        let metadata = securityMetadata(for: holding)
        if metadata.analystConsensusRatingRaw == nil, metadata.analystRatingError != nil {
            return true
        }
        guard let updatedAt = metadata.analystRatingUpdatedAt else { return true }
        return Date().timeIntervalSince(updatedAt) > 24 * 60 * 60
    }

    private func securityMetadata(for holding: Holding) -> SecurityMetadata {
        if let metadata = holding.securityMetadata {
            securityMetadataCache[metadata.securityKey] = metadata
            return metadata
        }

        let key = holding.securityMetadataKey
        if let cached = securityMetadataCache[key] {
            holding.securityMetadata = cached
            return cached
        }

        let metadata = SecurityMetadata(securityKey: key)
        holding.securityMetadata = metadata
        securityMetadataCache[key] = metadata
        return metadata
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

    private func midPrice(sell: Decimal?, buy: Decimal?) -> Decimal? {
        switch (sell, buy) {
        case let (sell?, buy?):
            return (sell + buy) / 2
        case let (sell?, nil):
            return sell
        case let (nil, buy?):
            return buy
        case (nil, nil):
            return nil
        }
    }

    private func latestStockAnalysisRecommendation(from html: String) -> [String: Any]? {
        guard let markerRange = html.range(of: "recommendations:[") else { return nil }
        let start = html.index(markerRange.upperBound, offsetBy: -1)
        guard let arrayText = balancedSubstring(in: html, from: start, open: "[", close: "]"),
              let jsonData = normalizeJavaScriptNumbers(quoteJavaScriptObjectKeys(arrayText)).data(using: .utf8),
              let recommendations = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return nil
        }
        return recommendations.last
    }

    private func balancedSubstring(in text: String, from start: String.Index, open: Character, close: Character) -> String? {
        guard text[start] == open else { return nil }
        var depth = 0
        var inString = false
        var previous: Character?
        var index = start

        while index < text.endIndex {
            let character = text[index]
            if character == "\"", previous != "\\" {
                inString.toggle()
            } else if !inString {
                if character == open {
                    depth += 1
                } else if character == close {
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...index])
                    }
                }
            }
            previous = character
            index = text.index(after: index)
        }

        return nil
    }

    private func quoteJavaScriptObjectKeys(_ objectText: String) -> String {
        var result = ""
        var inString = false
        var previous: Character?
        let characters = Array(objectText)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"", previous != "\\" {
                inString.toggle()
                result.append(character)
                previous = character
                index += 1
                continue
            }

            if !inString,
               (character == "{" || character == ",") {
                result.append(character)
                var lookahead = index + 1
                while lookahead < characters.count, characters[lookahead].isWhitespace {
                    result.append(characters[lookahead])
                    lookahead += 1
                }

                let keyStart = lookahead
                while lookahead < characters.count,
                      (characters[lookahead].isLetter || characters[lookahead].isNumber || characters[lookahead] == "_") {
                    lookahead += 1
                }

                if lookahead > keyStart, lookahead < characters.count, characters[lookahead] == ":" {
                    result.append("\"")
                    result.append(contentsOf: characters[keyStart..<lookahead])
                    result.append("\":")
                    index = lookahead + 1
                    previous = ":"
                    continue
                }

                previous = character
                index += 1
                continue
            }

            result.append(character)
            previous = character
            index += 1
        }

        return result
    }

    private func normalizeJavaScriptNumbers(_ objectText: String) -> String {
        objectText
            .replacingOccurrences(of: ":.", with: ":0.")
            .replacingOccurrences(of: ":-.", with: ":-0.")
    }

    private func decimal(from value: Any?) -> Decimal? {
        switch value {
        case let value as Double:
            return Decimal(value)
        case let value as Int:
            return Decimal(value)
        case let value as String:
            return Decimal(string: value)
        default:
            return nil
        }
    }

    private func int(from value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as Double:
            return Int(value)
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private func date(from value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func nextDataJSON(from html: String) -> Data? {
        let startMarker = "<script id=\"__NEXT_DATA__\" type=\"application/json\">"
        let endMarker = "</script>"
        guard let startRange = html.range(of: startMarker) else { return nil }
        let jsonStart = startRange.upperBound
        guard let endRange = html.range(of: endMarker, range: jsonStart..<html.endIndex) else { return nil }
        let json = String(html[jsonStart..<endRange.lowerBound])
        return json.data(using: .utf8)
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
    case sourceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "FMP API key not configured. Go to Settings to add it."
        case .noData: "No price data available for this security."
        case .rateLimited: "API rate limit reached. Try again later."
        case let .sourceUnavailable(message): message
        }
    }
}
