import Foundation

@MainActor
enum BankSyncService {
    static func sync(
        account: Account,
        accessToken: String,
        knownAccounts: [TrueLayerService.BankAccount] = []
    ) async {
        guard let accountIds = account.trueLayerAccountId else { return }
        let ids = accountIds.split(separator: ",").map(String.init)
        let knownById = Dictionary(uniqueKeysWithValues: knownAccounts.map { ($0.accountId, $0) })

        var totalGBP: Decimal = 0
        var activeBalanceIds = Set<String>()

        for id in ids {
            guard let balance = try? await TrueLayerService.shared.fetchBalanceSnapshot(
                accountId: id,
                accessToken: accessToken
            ) else {
                continue
            }

            let fxRate = (try? await PriceService.shared.fetchFXRateToGBP(from: balance.currency)) ?? 0
            let displayName = displayName(for: knownById[id], fallbackId: id, currency: balance.currency)
            activeBalanceIds.insert(id)
            totalGBP += balance.amount * fxRate

            if let existing = account.bankBalances.first(where: { $0.trueLayerAccountId == id }) {
                existing.displayName = displayName
                existing.amount = balance.amount
                existing.currency = balance.currency
                existing.fxRateToGBP = fxRate
                existing.fxRateDate = Date()
                existing.updatedAt = Date()
            } else {
                account.bankBalances.append(BankBalance(
                    trueLayerAccountId: id,
                    displayName: displayName,
                    amount: balance.amount,
                    currency: balance.currency,
                    fxRateToGBP: fxRate
                ))
            }

            if let transactions = try? await TrueLayerService.shared.fetchTransactions(
                accountId: id,
                accessToken: accessToken
            ) {
                mergeTransactions(transactions, into: account)
            }
        }

        account.bankBalances.removeAll { !activeBalanceIds.contains($0.trueLayerAccountId) }

        if !activeBalanceIds.isEmpty {
            account.balanceEntries.append(BalanceEntry(amount: totalGBP, source: .bankSync))
        }
    }

    private static func mergeTransactions(
        _ transactions: [TrueLayerService.TransactionSnapshot],
        into account: Account
    ) {
        for transaction in transactions {
            if let existing = account.bankTransactions.first(where: { $0.trueLayerTransactionId == transaction.id }) {
                existing.trueLayerAccountId = transaction.accountId
                existing.date = transaction.date
                existing.descriptionText = transaction.description
                existing.amount = transaction.amount
                existing.currency = transaction.currency
            } else {
                account.bankTransactions.append(BankTransaction(
                    trueLayerTransactionId: transaction.id,
                    trueLayerAccountId: transaction.accountId,
                    date: transaction.date,
                    descriptionText: transaction.description,
                    amount: transaction.amount,
                    currency: transaction.currency
                ))
            }
        }

        let sorted = account.bankTransactions.sorted { $0.date > $1.date }
        let retainedIds = Set(sorted.prefix(50).map(\.id))
        account.bankTransactions.removeAll { !retainedIds.contains($0.id) }
    }

    private static func displayName(
        for bankAccount: TrueLayerService.BankAccount?,
        fallbackId _: String,
        currency: String
    ) -> String {
        if let label = bankAccount?.label {
            return label
        }
        return "\(currency) Balance"
    }
}
