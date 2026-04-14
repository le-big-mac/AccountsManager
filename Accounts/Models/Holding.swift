import Foundation
import SwiftData

@Model
final class Holding {
    var id: UUID
    var name: String
    var ticker: String?
    var isin: String?
    var units: Decimal
    var lastPrice: Decimal?
    var lastPriceDate: Date?
    var account: Account?

    var currentValue: Decimal {
        guard let price = lastPrice else { return 0 }
        return units * price
    }

    var priceIdentifier: String? {
        ticker ?? isin
    }

    init(
        name: String,
        ticker: String? = nil,
        isin: String? = nil,
        units: Decimal
    ) {
        self.id = UUID()
        self.name = name
        self.ticker = ticker
        self.isin = isin
        self.units = units
    }
}
