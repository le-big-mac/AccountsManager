import Foundation

enum PortfolioImportService {
    static func parseCSV(at url: URL) async throws -> CSVParser.ParsedCSV {
        try await Task.detached(priority: .userInitiated) {
            try CSVParser().parse(url: url)
        }.value
    }

    @MainActor
    static func importCSV(at url: URL, into account: Account, rememberSource: Bool = true) async throws -> CSVParser.ParsedCSV {
        let parsed = try await parseCSV(at: url)
        importSnapshot(parsed, into: account)

        if rememberSource {
            account.investmentSourceType = .csvFile
            account.csvSourcePath = url.path
            account.csvSourceFormatRaw = parsed.detectedFormat.rawValue
            account.csvSourceImportedAt = Date()
        }

        return parsed
    }

    @MainActor
    static func refreshLinkedCSV(for account: Account) async {
        guard account.investmentSourceType == .csvFile,
              let path = account.csvSourcePath,
              !path.isEmpty else { return }

        _ = try? await importCSV(at: URL(fileURLWithPath: path), into: account, rememberSource: true)
    }

    @MainActor
    static func importSnapshot(
        _ parsed: CSVParser.ParsedCSV,
        into account: Account,
        cashFirst: Bool = false,
        preserveExistingCashWhenEmpty: Bool = false
    ) {
        if cashFirst {
            importCashBalances(
                parsed.cashBalances,
                into: account,
                preserveExistingWhenEmpty: preserveExistingCashWhenEmpty
            )
            importHoldings(parsed.holdings, into: account)
        } else {
            importHoldings(parsed.holdings, into: account)
            importCashBalances(
                parsed.cashBalances,
                into: account,
                preserveExistingWhenEmpty: preserveExistingCashWhenEmpty
            )
        }
    }

    @MainActor
    private static func importHoldings(_ holdings: [ParsedHolding], into account: Account) {
        let activeKeys = Set(holdings.map(holdingKey))

        for h in holdings {
            if let existing = account.holdings.first(where: { existing in
                keys(for: existing).contains(holdingKey(h))
            }) {
                existing.name = h.name
                existing.ticker = h.ticker
                existing.isin = h.isin
                existing.sedol = h.sedol
                existing.units = h.units
                existing.priceCurrency = h.priceCurrency
                existing.averagePurchasePrice = h.averagePurchasePrice
                applyCSVOnlyFields(h, to: existing)
                if let assetClass = h.assetClass {
                    existing.assetClass = assetClass
                }
            } else {
                let holding = Holding(
                    name: h.name,
                    ticker: h.ticker,
                    isin: h.isin,
                    sedol: h.sedol,
                    units: h.units,
                    priceCurrency: h.priceCurrency,
                    assetClass: h.assetClass
                )
                holding.averagePurchasePrice = h.averagePurchasePrice
                applyCSVOnlyFields(h, to: holding)
                account.holdings.append(holding)
            }
        }

        account.holdings.removeAll { existing in
            activeKeys.isDisjoint(with: keys(for: existing))
        }
    }

    @MainActor
    private static func applyCSVOnlyFields(_ parsed: ParsedHolding, to holding: Holding) {
        if let lastPrice = parsed.lastPrice {
            holding.lastPrice = lastPrice
            holding.lastPriceDate = Date()
        }

        holding.giltCouponRate = parsed.giltCouponRate
        holding.giltMaturityDate = parsed.giltMaturityDate
        holding.giltSettlementDate = parsed.giltSettlementDate
        holding.giltCleanPricePaid = parsed.giltCleanPricePaid
        holding.giltDirtyPricePaid = parsed.giltDirtyPricePaid
        holding.giltCouponDatesRaw = parsed.giltCouponDates
    }

    @MainActor
    private static func importCashBalances(
        _ cashBalances: [ParsedCashBalance],
        into account: Account,
        preserveExistingWhenEmpty: Bool = false
    ) {
        if preserveExistingWhenEmpty && cashBalances.isEmpty {
            return
        }

        let activeKeys = Set(cashBalances.map(cashKey))

        for cash in cashBalances {
            if let existing = account.cashBalances.first(where: { cashKey($0) == cashKey(cash) }) {
                existing.name = cash.name
                existing.amount = cash.amount
                existing.currency = cash.currency
                if let fxRate = cash.fxRateToGBP {
                    existing.fxRateToGBP = fxRate
                    existing.fxRateDate = Date()
                }
                existing.updatedAt = Date()
            } else {
                account.cashBalances.append(CashBalance(
                    name: cash.name,
                    amount: cash.amount,
                    currency: cash.currency,
                    fxRateToGBP: cash.fxRateToGBP
                ))
            }
        }

        account.cashBalances.removeAll { existing in
            !activeKeys.contains(cashKey(existing))
        }
    }

    private static func holdingKey(_ holding: ParsedHolding) -> String {
        if let isin = normalized(holding.isin), !isin.isEmpty { return "isin:\(isin)" }
        if let ticker = normalized(holding.ticker), !ticker.isEmpty { return "ticker:\(ticker)" }
        if let sedol = normalized(holding.sedol), !sedol.isEmpty { return "sedol:\(sedol)" }
        return "name:\(normalized(holding.name) ?? "")"
    }

    private static func keys(for holding: Holding) -> Set<String> {
        var keys = Set<String>()
        if let isin = normalized(holding.isin), !isin.isEmpty { keys.insert("isin:\(isin)") }
        if let ticker = normalized(holding.ticker), !ticker.isEmpty { keys.insert("ticker:\(ticker)") }
        if let sedol = normalized(holding.sedol), !sedol.isEmpty { keys.insert("sedol:\(sedol)") }
        keys.insert("name:\(normalized(holding.name) ?? "")")
        return keys
    }

    private static func cashKey(_ cash: ParsedCashBalance) -> String {
        "cash:\(normalized(cash.currency) ?? ""):\(normalized(cash.name) ?? "")"
    }

    private static func cashKey(_ cash: CashBalance) -> String {
        "cash:\(normalized(cash.currency) ?? ""):\(normalized(cash.name) ?? "")"
    }

    private static func normalized(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
