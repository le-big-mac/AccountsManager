import Foundation
import SwiftData

@Model
final class CashBalance {
    var id: UUID
    var name: String
    var amount: Decimal
    var currencyRaw: String
    var fxRateToGBP: Decimal?
    var fxRateDate: Date?
    var updatedAt: Date
    var account: Account?

    var currency: String {
        get {
            let normalized = Self.normalizedCurrency(currencyRaw)
            return normalized.isEmpty ? "GBP" : normalized
        }
        set { currencyRaw = Self.normalizedCurrency(newValue) }
    }

    var amountGBP: Decimal {
        amount * effectiveFXRateToGBP
    }

    var effectiveFXRateToGBP: Decimal {
        switch currency {
        case "GBP":
            return 1
        case "GBX":
            return Decimal(string: "0.01") ?? 0.01
        default:
            return fxRateToGBP ?? 0
        }
    }

    init(
        name: String,
        amount: Decimal,
        currency: String = "GBP",
        fxRateToGBP: Decimal? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.amount = amount
        self.currencyRaw = Self.normalizedCurrency(currency)
        self.fxRateToGBP = fxRateToGBP
        self.updatedAt = updatedAt
    }

    private static func normalizedCurrency(_ currency: String) -> String {
        let trimmed = currency.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "GBp" || trimmed == "GBX" {
            return "GBX"
        }
        return trimmed.uppercased()
    }
}
