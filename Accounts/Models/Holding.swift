import Foundation
import SwiftData

@Model
final class Holding {
    var id: UUID
    var name: String
    var ticker: String?
    var isin: String?
    var sedol: String?
    var units: Decimal
    var lastPrice: Decimal?
    var priceCurrencyRaw: String = ""
    var fxRateToGBP: Decimal?
    var fxRateDate: Date?
    var lastPriceDate: Date?
    var account: Account?

    var currentValue: Decimal {
        currentValueGBP
    }

    var localCurrentValue: Decimal {
        guard let price = lastPrice else { return 0 }
        return units * price
    }

    var currentValueGBP: Decimal {
        localCurrentValue * effectiveFXRateToGBP
    }

    var priceCurrency: String {
        get {
            let stored = normalizedCurrency(priceCurrencyRaw)
            return stored.isEmpty ? inferredPriceCurrency : stored
        }
        set { priceCurrencyRaw = normalizedCurrency(newValue) }
    }

    var effectiveFXRateToGBP: Decimal {
        switch priceCurrency {
        case "GBP":
            return 1
        case "GBX":
            return Decimal(string: "0.01") ?? 0.01
        default:
            return fxRateToGBP ?? 0
        }
    }

    var priceIdentifier: String? {
        ticker ?? isin ?? sedol
    }

    private var inferredPriceCurrency: String {
        guard let ticker else { return "GBP" }
        let uppercased = ticker.uppercased()
        if uppercased.hasSuffix(".L") || uppercased.hasSuffix(".LON") {
            return "GBP"
        }
        return "USD"
    }

    private func normalizedCurrency(_ currency: String) -> String {
        let trimmed = currency.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "GBp" || trimmed == "GBX" {
            return "GBX"
        }
        return trimmed.uppercased()
    }

    init(
        name: String,
        ticker: String? = nil,
        isin: String? = nil,
        sedol: String? = nil,
        units: Decimal,
        priceCurrency: String = "GBP"
    ) {
        self.id = UUID()
        self.name = name
        self.ticker = ticker
        self.isin = isin
        self.sedol = sedol
        self.units = units
        self.priceCurrency = priceCurrency
    }
}
