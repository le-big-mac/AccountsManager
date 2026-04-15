import Foundation
import SwiftData

@Model
final class BankTransaction {
    var id: UUID
    var trueLayerTransactionId: String
    var trueLayerAccountId: String
    var date: Date
    var descriptionText: String
    var amount: Decimal
    var currencyRaw: String
    var account: Account?

    var currency: String {
        get {
            let trimmed = currencyRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "GBP" : trimmed.uppercased()
        }
        set { currencyRaw = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    }

    init(
        trueLayerTransactionId: String,
        trueLayerAccountId: String,
        date: Date,
        descriptionText: String,
        amount: Decimal,
        currency: String
    ) {
        self.id = UUID()
        self.trueLayerTransactionId = trueLayerTransactionId
        self.trueLayerAccountId = trueLayerAccountId
        self.date = date
        self.descriptionText = descriptionText
        self.amount = amount
        self.currencyRaw = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
