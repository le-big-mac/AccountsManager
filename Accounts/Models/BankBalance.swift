import Foundation
import SwiftData

@Model
final class BankBalance {
    var id: UUID
    var trueLayerAccountId: String
    var displayName: String
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

    var effectiveDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ")

        if parts.count == 2,
           parts[0].uppercased() == currency,
           parts[1].count == 6,
           parts[1].allSatisfy(\.isHexDigit) {
            return "\(currency) Balance"
        }

        return trimmed.isEmpty ? "\(currency) Balance" : trimmed
    }

    init(
        trueLayerAccountId: String,
        displayName: String,
        amount: Decimal,
        currency: String,
        fxRateToGBP: Decimal? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = UUID()
        self.trueLayerAccountId = trueLayerAccountId
        self.displayName = displayName
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
