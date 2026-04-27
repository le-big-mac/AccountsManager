import Foundation

@MainActor
enum BankSyncService {
    static func sync(
        account: Account,
        accessToken: String,
        knownResources: [TrueLayerService.LinkedResource] = []
    ) async {
        guard let accountIds = account.trueLayerAccountId else { return }
        let ids = accountIds.split(separator: ",").map(String.init)
        let knownById = Dictionary(uniqueKeysWithValues: knownResources.map { ($0.resourceId, $0) })

        var totalGBP: Decimal = 0
        var activeBalanceIds = Set<String>()

        for (index, id) in ids.enumerated() {
            if index.isMultiple(of: 2) {
                await Task.yield()
            }
            let balance: TrueLayerService.BalanceSnapshot?
            switch account.trueLayerResourceType {
            case .account:
                balance = try? await TrueLayerService.shared.fetchBalanceSnapshot(
                    accountId: id,
                    accessToken: accessToken
                )
            case .card:
                balance = try? await TrueLayerService.shared.fetchCardBalanceSnapshot(
                    cardId: id,
                    accessToken: accessToken
                )
            }

            guard let balance else {
                continue
            }

            let fxRate = (try? await PriceService.shared.fetchFXRateToGBP(from: balance.currency)) ?? 0
            let displayName = displayName(for: knownById[id], type: account.trueLayerResourceType, currency: balance.currency)
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
        for resource: TrueLayerService.LinkedResource?,
        type: TrueLayerResourceType,
        currency: String
    ) -> String {
        if let label = resource?.label {
            return label
        }
        switch type {
        case .account:
            return "\(currency) Balance"
        case .card:
            return "\(currency) Card Balance"
        }
    }
}
