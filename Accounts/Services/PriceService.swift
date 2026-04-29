import Foundation

@MainActor
final class PriceService {
    static let shared = PriceService()

    private let stableBaseURL = "https://financialmodelingprep.com/stable"
    private let alphaVantageBaseURL = "https://www.alphavantage.co/query"
    private var cache: [String: CachedQuote] = [:]
    private var fxCache: [String: CachedFXRate] = [:]
    private var analystTargetCache: [String: CachedAnalystTarget] = [:]
    private var securityMetadataCache: [String: SecurityMetadata] = [:]
    private var vanguardProductsCache: [VanguardProduct]?
    private var analystTargetRefreshTask: Task<Void, Never>?
    private var queuedAnalystTargetTickers: Set<String> = []
    private var refreshedAnalystTargetTickers: Set<String> = []
    private var pendingAnalystTargetHoldings: [Holding] = []
    private var lastAlphaVantageRequestAt: Date?

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

    struct CachedAnalystTarget {
        let consensus: Decimal?
        let low: Decimal?
        let high: Decimal?
        let currency: String
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

    private var alphaVantageApiKey: String? {
        KeychainHelper.load(.alphaVantageApiKey)
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
        scheduleAnalystTargetRefresh(holdings)
    }

    func scheduleAnalystTargetRefresh(_ holdings: [Holding]) {
        guard alphaVantageApiKey != nil else { return }

        for holding in holdings {
            guard supportsAnalystTargets(for: holding),
                  needsAnalystTargetRefresh(for: holding),
                  let ticker = holding.ticker,
                  !ticker.isEmpty,
                  !queuedAnalystTargetTickers.contains(ticker),
                  !refreshedAnalystTargetTickers.contains(ticker) else {
                continue
            }
            queuedAnalystTargetTickers.insert(ticker)
            pendingAnalystTargetHoldings.append(holding)
        }

        guard analystTargetRefreshTask == nil else { return }
        analystTargetRefreshTask = Task { @MainActor in
            defer { self.analystTargetRefreshTask = nil }
            await self.refreshQueuedAnalystTargets()
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

    private func refreshQueuedAnalystTargets() async {
        guard alphaVantageApiKey != nil else { return }

        while !pendingAnalystTargetHoldings.isEmpty {
            guard !Task.isCancelled else { return }
            guard canUseAlphaVantageRequestBudget() else { return }
            let holding = pendingAnalystTargetHoldings.removeFirst()
            guard let ticker = holding.ticker else { continue }
            queuedAnalystTargetTickers.remove(ticker)

            guard supportsAnalystTargets(for: holding),
                  needsAnalystTargetRefresh(for: holding) else {
                continue
            }

            do {
                let metadata = securityMetadata(for: holding)
                if let target = try await fetchAnalystTarget(ticker: ticker, currency: holding.priceCurrency) {
                    metadata.analystConsensusTarget = target.consensus
                    metadata.analystTargetLow = target.low
                    metadata.analystTargetHigh = target.high
                    metadata.analystTargetCurrency = target.currency
                    metadata.analystTargetUpdatedAt = Date()
                    refreshedAnalystTargetTickers.insert(ticker)
                } else if metadata.analystTargetUpdatedAt == nil {
                    metadata.analystTargetUpdatedAt = Date()
                    refreshedAnalystTargetTickers.insert(ticker)
                }
            } catch {
                if let priceError = error as? PriceError, priceError == .rateLimited {
                    return
                }
                let metadata = securityMetadata(for: holding)
                if metadata.analystConsensusTarget != nil || metadata.analystTargetLow != nil || metadata.analystTargetHigh != nil {
                    metadata.analystTargetUpdatedAt = metadata.analystTargetUpdatedAt ?? Date()
                    refreshedAnalystTargetTickers.insert(ticker)
                }
            }
        }
    }

    private func fetchAnalystTarget(ticker: String, currency: String) async throws -> CachedAnalystTarget? {
        if let cached = analystTargetCache[ticker],
           Date().timeIntervalSince(cached.fetchedAt) < 21_600 {
            return cached
        }

        guard let alphaVantageApiKey else { throw PriceError.notConfigured }
        try await respectAlphaVantageThrottle()

        var components = URLComponents(string: alphaVantageBaseURL)!
        components.queryItems = [
            URLQueryItem(name: "function", value: "OVERVIEW"),
            URLQueryItem(name: "symbol", value: ticker),
            URLQueryItem(name: "apikey", value: alphaVantageApiKey)
        ]
        let url = components.url!
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PriceError.noData
        }

        if object["Information"] != nil || object["Note"] != nil {
            throw PriceError.rateLimited
        }

        let consensus = decimalString(object["AnalystTargetPrice"])
        let low = decimalString(object["AnalystTargetLowPrice"])
        let high = decimalString(object["AnalystTargetHighPrice"])
        let responseCurrency = normalizedCurrency((object["Currency"] as? String) ?? currency)

        guard consensus != nil || low != nil || high != nil else {
            analystTargetCache[ticker] = CachedAnalystTarget(
                consensus: nil,
                low: nil,
                high: nil,
                currency: responseCurrency,
                fetchedAt: Date()
            )
            return nil
        }

        let cached = CachedAnalystTarget(
            consensus: consensus,
            low: low,
            high: high,
            currency: responseCurrency,
            fetchedAt: Date()
        )
        analystTargetCache[ticker] = cached
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
        analystTargetCache.removeAll()
        securityMetadataCache.removeAll()
        queuedAnalystTargetTickers.removeAll()
        refreshedAnalystTargetTickers.removeAll()
        pendingAnalystTargetHoldings.removeAll()
    }

    private func supportsAnalystTargets(for holding: Holding) -> Bool {
        switch holding.assetClass {
        case .stock, .etf:
            return holding.ticker != nil
        case .cash, .fund, .gilt, .other:
            return false
        }
    }

    private func needsAnalystTargetRefresh(for holding: Holding) -> Bool {
        guard let updatedAt = securityMetadata(for: holding).analystTargetUpdatedAt else { return true }
        return Date().timeIntervalSince(updatedAt) > 7 * 24 * 60 * 60
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

    private func respectAlphaVantageThrottle() async throws {
        let minimumInterval: TimeInterval = 12
        if let lastAlphaVantageRequestAt {
            let elapsed = Date().timeIntervalSince(lastAlphaVantageRequestAt)
            if elapsed < minimumInterval {
                let remaining = minimumInterval - elapsed
                try await Task.sleep(for: .seconds(remaining))
            }
        }
        lastAlphaVantageRequestAt = Date()
    }

    private func canUseAlphaVantageRequestBudget() -> Bool {
        let defaults = UserDefaults.standard
        let dayKey = "alphaVantage.requestDay"
        let countKey = "alphaVantage.requestCount"
        let today = alphaVantageDayString(for: Date())
        let storedDay = defaults.string(forKey: dayKey)
        var count = defaults.integer(forKey: countKey)

        if storedDay != today {
            defaults.set(today, forKey: dayKey)
            count = 0
        }

        guard count < 25 else { return false }
        defaults.set(count + 1, forKey: countKey)
        return true
    }

    private func alphaVantageDayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func decimalString(_ value: Any?) -> Decimal? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "None" else { return nil }
        return Decimal(string: trimmed)
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

    var errorDescription: String? {
        switch self {
        case .notConfigured: "FMP API key not configured. Go to Settings to add it."
        case .noData: "No price data available for this security."
        case .rateLimited: "API rate limit reached. Try again later."
        }
    }
}
