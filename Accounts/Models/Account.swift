import Foundation
import SwiftData

enum InvestmentSourceType: String {
    case csvFile
    case snapTrade

    var displayName: String {
        switch self {
        case .csvFile: "CSV File"
        case .snapTrade: "SnapTrade"
        }
    }
}

@Model
final class Account {
    var id: UUID
    var name: String
    var accountTypeRaw: String
    var trueLayerAccountId: String?    // comma-separated for multiple accounts
    var trueLayerRefreshToken: String?  // per-account refresh token
    var trueLayerProvider: String?     // provider_id when available, otherwise display name -- used to filter
    var investmentSourceTypeRaw: String?
    var csvSourcePath: String?
    var csvSourceFormatRaw: String?
    var csvSourceImportedAt: Date?
    var snapTradeAccountId: String?
    var snapTradeAuthorizationId: String?
    var snapTradeInstitutionName: String?
    var snapTradeSyncedAt: Date?
    var sortOrder: Int
    var isArchived: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Holding.account)
    var holdings: [Holding]

    @Relationship(deleteRule: .cascade, inverse: \BalanceEntry.account)
    var balanceEntries: [BalanceEntry]

    @Relationship(deleteRule: .cascade, inverse: \CashBalance.account)
    var cashBalances: [CashBalance]

    @Relationship(deleteRule: .cascade, inverse: \BankBalance.account)
    var bankBalances: [BankBalance]

    @Relationship(deleteRule: .cascade, inverse: \BankTransaction.account)
    var bankTransactions: [BankTransaction]

    var accountType: AccountType {
        get { AccountType(rawValue: accountTypeRaw) ?? .investment }
        set { accountTypeRaw = newValue.rawValue }
    }

    var investmentSourceType: InvestmentSourceType? {
        get { investmentSourceTypeRaw.flatMap(InvestmentSourceType.init(rawValue:)) }
        set { investmentSourceTypeRaw = newValue?.rawValue }
    }

    var currentBalance: Decimal {
        switch accountType {
        case .bankAccount:
            if !bankBalances.isEmpty {
                return bankBalances.reduce(Decimal.zero) { total, balance in
                    total + balance.amountGBP
                }
            }
            return balanceEntries
                .sorted { $0.date > $1.date }
                .first?.amount ?? 0
        case .investment:
            let holdingsTotal = holdings.reduce(Decimal.zero) { total, holding in
                total + holding.currentValue
            }
            let cashTotal = cashBalances.reduce(Decimal.zero) { total, cash in
                total + cash.amountGBP
            }
            return holdingsTotal + cashTotal
        }
    }

    var lastUpdated: Date? {
        switch accountType {
        case .bankAccount:
            if let updatedAt = bankBalances.map(\.updatedAt).max() {
                return updatedAt
            }
            return balanceEntries
                .sorted { $0.date > $1.date }
                .first?.date
        case .investment:
            let holdingDate = holdings
                .compactMap { $0.lastPriceDate }
                .max()
            let cashDate = cashBalances
                .map(\.updatedAt)
                .max()
            return [holdingDate, cashDate].compactMap { $0 }.max()
        }
    }

    init(name: String, accountType: AccountType, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.accountTypeRaw = accountType.rawValue
        self.sortOrder = sortOrder
        self.isArchived = false
        self.createdAt = Date()
        self.holdings = []
        self.balanceEntries = []
        self.cashBalances = []
        self.bankBalances = []
        self.bankTransactions = []
    }
}
