import Foundation

enum CSVPlatformFormat {
    case vanguardUK
    case robinhood
    case interactiveInvestor
    case unknown

    var description: String {
        switch self {
        case .vanguardUK: "Vanguard UK"
        case .robinhood: "Robinhood"
        case .interactiveInvestor: "Interactive Investor"
        case .unknown: "Unknown"
        }
    }
}

struct ParsedHolding {
    let name: String
    let ticker: String?
    let isin: String?
    let units: Decimal
    let priceCurrency: String
}

struct CSVParser {

    struct ParsedCSV {
        let headers: [String]
        let rows: [[String]]
        let detectedFormat: CSVPlatformFormat
        let holdings: [ParsedHolding]
    }

    func parse(url: URL) throws -> ParsedCSV {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let headerLine = lines.first else {
            throw CSVError.emptyFile
        }

        let headers = parseRow(headerLine)
        let rows = lines.dropFirst().map { parseRow($0) }
        let format = detectFormat(headers: headers)
        let holdings = extractHoldings(headers: headers, rows: rows, format: format)

        return ParsedCSV(
            headers: headers,
            rows: Array(rows),
            detectedFormat: format,
            holdings: holdings
        )
    }

    private func parseRow(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
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
            ParsedHolding(name: name, ticker: nil, isin: nil, units: abs(units), priceCurrency: "GBP")
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
            ParsedHolding(name: value.name, ticker: key, isin: nil, units: abs(value.units), priceCurrency: "USD")
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
            ParsedHolding(name: value.name, ticker: nil, isin: nil, units: abs(value.units), priceCurrency: "GBP")
        }.filter { $0.units > 0 }
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
