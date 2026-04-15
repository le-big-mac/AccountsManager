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
        }

        account.bankBalances.removeAll { !activeBalanceIds.contains($0.trueLayerAccountId) }

        if !activeBalanceIds.isEmpty {
            account.balanceEntries.append(BalanceEntry(amount: totalGBP, source: .bankSync))
        }
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
