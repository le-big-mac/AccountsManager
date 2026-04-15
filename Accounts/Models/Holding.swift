import Foundation
import SwiftData

enum HoldingAssetClass: String, CaseIterable, Identifiable {
    case cash
    case stock
    case etf
    case fund
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cash: "Cash"
        case .stock: "Securities"
        case .etf: "ETFs"
        case .fund: "Funds"
        case .other: "Other"
        }
    }

    static func from(_ value: String?) -> HoldingAssetClass? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        switch normalized {
        case "cash":
            return .cash
        case "stock", "stocks", "share", "shares", "equity", "equities", "security", "securities":
            return .stock
        case "etf", "etfs", "exchangetradedfund":
            return .etf
        case "fund", "funds", "mutualfund", "oeic", "unittrust":
            return .fund
        default:
            return nil
        }
    }
}

@Model
final class Holding {
    var id: UUID
    var name: String
    var ticker: String?
    var isin: String?
    var sedol: String?
    var units: Decimal
    var lastPrice: Decimal?
    var averagePurchasePrice: Decimal?
    var priceCurrencyRaw: String = ""
    var assetClassRaw: String?
    var fxRateToGBP: Decimal?
    var fxRateDate: Date?
    var lastPriceDate: Date?
    var analystConsensusTarget: Decimal?
    var analystTargetLow: Decimal?
    var analystTargetHigh: Decimal?
    var analystTargetCurrencyRaw: String = ""
    var analystTargetUpdatedAt: Date?
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

    var assetClass: HoldingAssetClass {
        get { HoldingAssetClass(rawValue: assetClassRaw ?? "") ?? inferredAssetClass }
        set { assetClassRaw = newValue.rawValue }
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

    var analystTargetCurrency: String {
        get {
            let stored = normalizedCurrency(analystTargetCurrencyRaw)
            return stored.isEmpty ? priceCurrency : stored
        }
        set { analystTargetCurrencyRaw = normalizedCurrency(newValue) }
    }

    var analystConsensusUpsidePercent: Decimal? {
        guard let target = analystConsensusTarget,
              let price = lastPrice,
              price != 0,
              analystTargetCurrency == priceCurrency else {
            return nil
        }
        return (target - price) / price
    }

    var openPnLPercent: Decimal? {
        guard let averagePurchasePrice,
              let price = lastPrice,
              averagePurchasePrice > 0 else {
            return nil
        }
        let currentValue = units * price
        guard currentValue > 0 else { return nil }
        let costBasis = units * averagePurchasePrice
        return (currentValue - costBasis) / currentValue
    }

    private var inferredPriceCurrency: String {
        guard let ticker else { return "GBP" }
        let uppercased = ticker.uppercased()
        if uppercased.hasSuffix(".L") || uppercased.hasSuffix(".LON") {
            return "GBP"
        }
        return "USD"
    }

    private var inferredAssetClass: HoldingAssetClass {
        let text = [name, ticker, isin, sedol]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if text.contains(" etf")
            || text.contains(" ucits")
            || text.contains("ishares")
            || text.contains("vanguard ftse")
            || text.contains("vanguard s&p")
            || text.contains("vanguard sp") {
            return .etf
        }

        if text.contains("fund")
            || text.contains("oeic")
            || text.contains("index")
            || text.contains("accumulation")
            || text.contains("income")
            || text.contains("acc ") {
            return .fund
        }

        return .stock
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
        priceCurrency: String = "GBP",
        assetClass: HoldingAssetClass? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.ticker = ticker
        self.isin = isin
        self.sedol = sedol
        self.units = units
        self.priceCurrency = priceCurrency
        self.assetClassRaw = assetClass?.rawValue
    }
}
