import Foundation
import SwiftData

@Model
final class BalanceEntry {
    var id: UUID
    var amount: Decimal
    var date: Date
    var sourceRaw: String
    var account: Account?

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    init(amount: Decimal, date: Date = Date(), source: EntrySource = .manual) {
        self.id = UUID()
        self.amount = amount
        self.date = date
        self.sourceRaw = source.rawValue
    }
}
