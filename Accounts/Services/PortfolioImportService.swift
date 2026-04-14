import Foundation

@MainActor
enum PortfolioImportService {
    static func importCSV(at url: URL, into account: Account, rememberSource: Bool = true) throws -> CSVParser.ParsedCSV {
        let parsed = try CSVParser().parse(url: url)
        importSnapshot(parsed, into: account)

        if rememberSource {
            account.investmentSourceType = .csvFile
            account.csvSourcePath = url.path
            account.csvSourceFormatRaw = parsed.detectedFormat.rawValue
            account.csvSourceImportedAt = Date()
        }

        return parsed
    }

    static func refreshLinkedCSV(for account: Account) {
        guard account.investmentSourceType == .csvFile,
              let path = account.csvSourcePath,
              !path.isEmpty else { return }

        _ = try? importCSV(at: URL(fileURLWithPath: path), into: account, rememberSource: true)
    }

    static func importSnapshot(_ parsed: CSVParser.ParsedCSV, into account: Account) {
        importHoldings(parsed.holdings, into: account)
        importCashBalances(parsed.cashBalances, into: account)
    }

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
            } else {
                let holding = Holding(
                    name: h.name,
                    ticker: h.ticker,
                    isin: h.isin,
                    sedol: h.sedol,
                    units: h.units,
                    priceCurrency: h.priceCurrency
                )
                account.holdings.append(holding)
            }
        }

        account.holdings.removeAll { existing in
            activeKeys.isDisjoint(with: keys(for: existing))
        }
    }

    private static func importCashBalances(_ cashBalances: [ParsedCashBalance], into account: Account) {
        let activeKeys = Set(cashBalances.map(cashKey))

        for cash in cashBalances {
            if let existing = account.cashBalances.first(where: { cashKey($0) == cashKey(cash) }) {
                existing.name = cash.name
                existing.amount = cash.amount
                existing.currency = cash.currency
                existing.updatedAt = Date()
            } else {
                account.cashBalances.append(CashBalance(
                    name: cash.name,
                    amount: cash.amount,
                    currency: cash.currency
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
