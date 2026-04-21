import Foundation

enum PortfolioCSVExporter {
    static func export(accounts: [Account], to url: URL) throws {
        let rows = makeRows(from: accounts)
        let csv = buildCSV(rows: rows)
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    static func defaultFilename(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "yyyy-MM-dd"
        return "accounts-portfolio-\(formatter.string(from: now)).csv"
    }

    private static func makeRows(from accounts: [Account]) -> [[String]] {
        let header = [
            "accountName",
            "accountType",
            "sourceType",
            "name",
            "assetClass",
            "units",
            "currency",
            "averagePurchasePrice",
            "ticker",
            "isin",
            "sedol"
        ]

        let accountRows = accounts.sorted { $0.sortOrder < $1.sortOrder }.flatMap { account in
            rows(for: account)
        }

        return [header] + accountRows
    }

    private static func rows(for account: Account) -> [[String]] {
        switch account.accountType {
        case .bankAccount:
            let balanceRows = account.bankBalances
                .sorted {
                    if $0.currency == $1.currency {
                        return $0.effectiveDisplayName.localizedCaseInsensitiveCompare($1.effectiveDisplayName) == .orderedAscending
                    }
                    return $0.currency.localizedCaseInsensitiveCompare($1.currency) == .orderedAscending
                }
                .map { balance in
                    [
                        account.name,
                        account.accountType.rawValue,
                        "trueLayer",
                        balance.effectiveDisplayName,
                        HoldingAssetClass.cash.rawValue,
                        decimalString(balance.amount),
                        balance.currency,
                        "",
                        "",
                        "",
                        ""
                    ]
                }

            if !balanceRows.isEmpty {
                return balanceRows
            }

            guard let latestBalance = account.balanceEntries.sorted(by: { $0.date > $1.date }).first else {
                return []
            }

            return [[
                account.name,
                account.accountType.rawValue,
                "trueLayer",
                account.name,
                HoldingAssetClass.cash.rawValue,
                decimalString(latestBalance.amount),
                "GBP",
                "",
                "",
                "",
                ""
            ]]
        case .investment:
            let holdingRows = account.holdings
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { holding in
                    [
                        account.name,
                        account.accountType.rawValue,
                        account.investmentSourceType?.rawValue ?? "",
                        holding.name,
                        holding.assetClass.rawValue,
                        decimalString(holding.units),
                        holding.priceCurrency,
                        decimalString(holding.averagePurchasePrice),
                        holding.ticker ?? "",
                        holding.isin ?? "",
                        holding.sedol ?? ""
                    ]
                }

            let cashRows = account.cashBalances
                .sorted {
                    if $0.currency == $1.currency {
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    return $0.currency.localizedCaseInsensitiveCompare($1.currency) == .orderedAscending
                }
                .map { cash in
                    [
                        account.name,
                        account.accountType.rawValue,
                        account.investmentSourceType?.rawValue ?? "",
                        cash.name,
                        HoldingAssetClass.cash.rawValue,
                        decimalString(cash.amount),
                        cash.currency,
                        "",
                        "",
                        "",
                        ""
                    ]
                }

            return holdingRows + cashRows
        }
    }

    private static func buildCSV(rows: [[String]]) -> String {
        rows
            .map { row in row.map(csvField).joined(separator: ",") }
            .joined(separator: "\n")
            + "\n"
    }

    private static func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private static func decimalString(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return NSDecimalNumber(decimal: value).stringValue
    }
}
