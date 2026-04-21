import Foundation

enum CSVPlatformFormat: String {
    case genericPortfolio
    case vanguardUK
    case robinhood
    case interactiveInvestor
    case unknown

    var description: String {
        switch self {
        case .genericPortfolio: "Generic Portfolio"
        case .vanguardUK: "Vanguard UK"
        case .robinhood: "Robinhood"
        case .interactiveInvestor: "Interactive Investor"
        case .unknown: "Unknown"
        }
    }
}

struct ParsedHolding: Sendable {
    let name: String
    let ticker: String?
    let isin: String?
    let sedol: String?
    let units: Decimal
    let priceCurrency: String
    let assetClass: HoldingAssetClass?
    let averagePurchasePrice: Decimal?
}

struct ParsedCashBalance: Sendable {
    let name: String
    let amount: Decimal
    let currency: String
    let fxRateToGBP: Decimal?
}

struct CSVParser {

    struct ParsedCSV: Sendable {
        let headers: [String]
        let rows: [[String]]
        let detectedFormat: CSVPlatformFormat
        let holdings: [ParsedHolding]
        let cashBalances: [ParsedCashBalance]
    }

    func parse(url: URL) throws -> ParsedCSV {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let headerLine = lines.first else {
            throw CSVError.emptyFile
        }

        let delimiter = detectDelimiter(headerLine)
        let headers = parseRow(headerLine, delimiter: delimiter)
        let rows = lines.dropFirst().map { parseRow($0, delimiter: delimiter) }
        let format = detectFormat(headers: headers)
        let holdings = extractHoldings(headers: headers, rows: rows, format: format)
        let cashBalances = extractCashBalances(headers: headers, rows: rows, format: format)

        return ParsedCSV(
            headers: headers,
            rows: Array(rows),
            detectedFormat: format,
            holdings: holdings,
            cashBalances: cashBalances
        )
    }

    private func detectDelimiter(_ line: String) -> Character {
        line.filter { $0 == "\t" }.count > line.filter { $0 == "," }.count ? "\t" : ","
    }

    private func parseRow(_ line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == delimiter && !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    private func detectFormat(headers: [String]) -> CSVPlatformFormat {
        let joined = headers.joined(separator: " ").lowercased()
        let normalized = headers.map(normalizedHeader)

        if normalized.contains("assetclass") &&
            normalized.contains("units") &&
            normalized.contains("currency") {
            return .genericPortfolio
        }

        if joined.contains("investment name") && joined.contains("share price") && joined.contains("trade date") {
            return .vanguardUK
        }

        if joined.contains("instrument") || (joined.contains("activity") && joined.contains("quantity")) {
            return .robinhood
        }

        if joined.contains("stock") && joined.contains("sedol") {
            return .interactiveInvestor
        }

        return .unknown
    }

    private func extractHoldings(headers: [String], rows: [[String]], format: CSVPlatformFormat) -> [ParsedHolding] {
        switch format {
        case .genericPortfolio:
            return extractGenericPortfolioHoldings(headers: headers, rows: rows)
        case .vanguardUK:
            return extractVanguardHoldings(headers: headers, rows: rows)
        case .robinhood:
            return extractRobinhoodHoldings(headers: headers, rows: rows)
        case .interactiveInvestor:
            return extractIIHoldings(headers: headers, rows: rows)
        case .unknown:
            return []
        }
    }

    private func extractCashBalances(headers: [String], rows: [[String]], format: CSVPlatformFormat) -> [ParsedCashBalance] {
        switch format {
        case .genericPortfolio:
            return extractGenericCashBalances(headers: headers, rows: rows)
        default:
            return []
        }
    }

    // MARK: - Generic Portfolio

    private func extractGenericPortfolioHoldings(headers: [String], rows: [[String]]) -> [ParsedHolding] {
        let index = headerIndex(headers)
        guard let nameIdx = index["name"],
              let unitsIdx = index["units"],
              let currencyIdx = index["currency"] else {
            return []
        }

        guard let assetClassIdx = index["assetclass"] else { return [] }
        let tickerIdx = index["ticker"]
        let isinIdx = index["isin"]
        let sedolIdx = index["sedol"]
        let averagePurchasePriceIdx = index["averagepurchaseprice"] ?? index["averageprice"] ?? index["costbasis"]

        return rows.compactMap { row in
            let assetClass = HoldingAssetClass.from(value(row, at: assetClassIdx))
            guard let assetClass, assetClass != .cash else { return nil }
            guard let name = value(row, at: nameIdx), !name.isEmpty,
                  let unitsText = value(row, at: unitsIdx),
                  let units = parseDecimal(unitsText),
                  units != 0 else { return nil }

            return ParsedHolding(
                name: name,
                ticker: value(row, at: tickerIdx).flatMap(nonEmpty),
                isin: value(row, at: isinIdx).flatMap(nonEmpty),
                sedol: value(row, at: sedolIdx).flatMap(nonEmpty),
                units: abs(units),
                priceCurrency: value(row, at: currencyIdx).flatMap(nonEmpty) ?? "GBP",
                assetClass: assetClass,
                averagePurchasePrice: value(row, at: averagePurchasePriceIdx).flatMap(parseDecimal)
            )
        }
    }

    private func extractGenericCashBalances(headers: [String], rows: [[String]]) -> [ParsedCashBalance] {
        let index = headerIndex(headers)
        guard let currencyIdx = index["currency"] else {
            return []
        }

        guard let assetClassIdx = index["assetclass"] else { return [] }
        let nameIdx = index["name"]
        guard let amountIdx = index["units"] else { return [] }

        return rows.compactMap { row in
            let assetClass = HoldingAssetClass.from(value(row, at: assetClassIdx))
            guard assetClass == .cash,
                  let amountText = value(row, at: amountIdx),
                  let amount = parseDecimal(amountText) else { return nil }

            let currency = value(row, at: currencyIdx).flatMap(nonEmpty) ?? "GBP"
            let name = value(row, at: nameIdx).flatMap(nonEmpty) ?? "\(currency) Cash"
            return ParsedCashBalance(name: name, amount: amount, currency: currency, fxRateToGBP: nil)
        }
    }

    // MARK: - Vanguard UK

    private func extractVanguardHoldings(headers: [String], rows: [[String]]) -> [ParsedHolding] {
        let lowerHeaders = headers.map { $0.lowercased() }
        guard let nameIdx = lowerHeaders.firstIndex(where: { $0.contains("investment name") }),
              let sharesIdx = lowerHeaders.firstIndex(where: { $0.contains("shares") || $0.contains("units") }) else {
            return []
        }

        // Group by investment name and take the latest shares count
        var holdingMap: [String: Decimal] = [:]
        for row in rows {
            guard row.count > max(nameIdx, sharesIdx) else { continue }
            let name = row[nameIdx]
            guard !name.isEmpty else { continue }
            if let units = Decimal(string: row[sharesIdx].replacingOccurrences(of: ",", with: "")) {
                holdingMap[name] = units
            }
        }

        return holdingMap.map { name, units in
            ParsedHolding(name: name, ticker: nil, isin: nil, sedol: nil, units: abs(units), priceCurrency: "GBP", assetClass: .fund, averagePurchasePrice: nil)
        }
    }

    // MARK: - Robinhood

    private func extractRobinhoodHoldings(headers: [String], rows: [[String]]) -> [ParsedHolding] {
        let lowerHeaders = headers.map { $0.lowercased() }
        let nameIdx = lowerHeaders.firstIndex(where: { $0.contains("instrument") || $0.contains("name") || $0.contains("description") })
        let tickerIdx = lowerHeaders.firstIndex(where: { $0.contains("symbol") || $0.contains("ticker") })
        let qtyIdx = lowerHeaders.firstIndex(where: { $0.contains("quantity") || $0.contains("shares") })

        guard let qtyIndex = qtyIdx else { return [] }

        var holdingMap: [String: (name: String, units: Decimal)] = [:]
        for row in rows {
            guard row.count > qtyIndex else { continue }
            let ticker = tickerIdx.flatMap { row.count > $0 ? row[$0] : nil } ?? ""
            let name = nameIdx.flatMap { row.count > $0 ? row[$0] : nil } ?? ticker
            let key = ticker.isEmpty ? name : ticker
            guard !key.isEmpty else { continue }

            if let units = Decimal(string: row[qtyIndex].replacingOccurrences(of: ",", with: "")) {
                let existing = holdingMap[key]?.units ?? 0
                holdingMap[key] = (name: name, units: existing + units)
            }
        }

        return holdingMap.map { key, value in
            ParsedHolding(name: value.name, ticker: key, isin: nil, sedol: nil, units: abs(value.units), priceCurrency: "USD", assetClass: .stock, averagePurchasePrice: nil)
        }.filter { $0.units > 0 }
    }

    // MARK: - Interactive Investor

    private func extractIIHoldings(headers: [String], rows: [[String]]) -> [ParsedHolding] {
        let lowerHeaders = headers.map { $0.lowercased() }
        let nameIdx = lowerHeaders.firstIndex(where: { $0.contains("stock") || $0.contains("name") || $0.contains("description") })
        let sedolIdx = lowerHeaders.firstIndex(where: { $0.contains("sedol") })
        let qtyIdx = lowerHeaders.firstIndex(where: { $0.contains("quantity") || $0.contains("units") || $0.contains("shares") })

        guard let qtyIndex = qtyIdx else { return [] }

        var holdingMap: [String: (name: String, sedol: String?, units: Decimal)] = [:]
        for row in rows {
            guard row.count > qtyIndex else { continue }
            let name = nameIdx.flatMap { row.count > $0 ? row[$0] : nil } ?? ""
            let sedol = sedolIdx.flatMap { row.count > $0 ? row[$0] : nil }
            guard !name.isEmpty else { continue }

            if let units = Decimal(string: row[qtyIndex].replacingOccurrences(of: ",", with: "")) {
                let existing = holdingMap[name]?.units ?? 0
                holdingMap[name] = (name: name, sedol: sedol, units: existing + units)
            }
        }

        return holdingMap.map { _, value in
            ParsedHolding(name: value.name, ticker: nil, isin: nil, sedol: value.sedol, units: abs(value.units), priceCurrency: "GBP", assetClass: HoldingAssetClass.from(value.name), averagePurchasePrice: nil)
        }.filter { $0.units > 0 }
    }

    // MARK: - Helpers

    private func headerIndex(_ headers: [String]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: headers.enumerated().map { index, header in
            (normalizedHeader(header), index)
        })
    }

    private func normalizedHeader(_ header: String) -> String {
        header
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private func value(_ row: [String], at index: Int?) -> String? {
        guard let index, row.indices.contains(index) else { return nil }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    private func parseDecimal(_ value: String) -> Decimal? {
        let cleaned = value
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: cleaned)
    }
}

enum CSVError: LocalizedError {
    case emptyFile
    case invalidFormat
    case missingColumns

    var errorDescription: String? {
        switch self {
        case .emptyFile: "The CSV file is empty."
        case .invalidFormat: "Unable to parse the CSV file."
        case .missingColumns: "Required columns are missing from the CSV."
        }
    }
}
