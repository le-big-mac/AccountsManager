import Foundation
import SwiftData

@Model
final class SecurityMetadata {
    var id: UUID
    var securityKey: String
    var analystConsensusTarget: Decimal?
    var analystTargetLow: Decimal?
    var analystTargetHigh: Decimal?
    var analystTargetCurrencyRaw: String = ""
    var analystTargetUpdatedAt: Date?

    @Relationship(inverse: \Holding.securityMetadata)
    var holdings: [Holding]

    var analystTargetCurrency: String {
        get {
            let trimmed = analystTargetCurrencyRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "GBp" || trimmed == "GBX" {
                return "GBX"
            }
            return trimmed.uppercased()
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "GBp" || trimmed == "GBX" {
                analystTargetCurrencyRaw = "GBX"
            } else {
                analystTargetCurrencyRaw = trimmed.uppercased()
            }
        }
    }

    init(securityKey: String) {
        self.id = UUID()
        self.securityKey = securityKey
        self.holdings = []
    }
}
