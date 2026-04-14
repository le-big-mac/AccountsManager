import Foundation

@MainActor
enum SnapTradeImportService {
    static func sync(account: Account, refreshConnection: Bool = false) async throws {
        if refreshConnection, let authorizationId = account.snapTradeAuthorizationId {
            try await SnapTradeService.shared.refreshConnection(authorizationId: authorizationId)
        }

        guard let accountId = account.snapTradeAccountId else {
            throw SnapTradeError.invalidResponse
        }

        let response = try await SnapTradeService.shared.holdings(accountId: accountId)
        importHoldings(response.positions ?? [], into: account)
        importCashBalances(response.balances ?? [], into: account)
        account.snapTradeSyncedAt = Date()

        if let snapTradeAccount = response.account {
            account.snapTradeAuthorizationId = snapTradeAccount.brokerageAuthorization
            account.snapTradeInstitutionName = snapTradeAccount.institutionName
        }

        await PriceService.shared.refreshHoldingFXRates(account.holdings)
        await PriceService.shared.refreshCashBalances(account.cashBalances)
    }

    static func importHoldings(_ positions: [SnapTradePosition], into account: Account) {
        let mapped = positions.compactMap { position -> ParsedHolding? in
            guard position.cashEquivalent != true else { return nil }
            let units = position.fractionalUnits ?? position.units ?? 0
            guard units != 0 else { return nil }

            let security = position.symbol?.symbol
            let ticker = security?.symbol ?? security?.rawSymbol
            let name = security?.description ?? ticker ?? "Security"
            let currency = position.currency?.code ?? security?.currency?.code ?? "USD"

            return ParsedHolding(
                name: name,
                ticker: ticker,
                isin: nil,
                sedol: nil,
                units: abs(units),
                priceCurrency: currency
            )
        }

        PortfolioImportService.importSnapshot(
            CSVParser.ParsedCSV(
                headers: [],
                rows: [],
                detectedFormat: .unknown,
                holdings: mapped,
                cashBalances: []
            ),
            into: account
        )

        for holding in account.holdings {
            guard let position = positions.first(where: { ($0.symbol?.symbol?.symbol ?? $0.symbol?.symbol?.rawSymbol) == holding.ticker }),
                  let price = position.price else { continue }
            holding.lastPrice = price
            holding.priceCurrency = position.currency?.code ?? position.symbol?.symbol?.currency?.code ?? holding.priceCurrency
            holding.lastPriceDate = Date()
        }
    }

    static func importCashBalances(_ balances: [SnapTradeBalance], into account: Account) {
        let cashBalances = balances.compactMap { balance -> ParsedCashBalance? in
            guard let cash = balance.cash,
                  cash != 0 else { return nil }
            let currency = balance.currency?.code ?? "USD"
            return ParsedCashBalance(name: "\(currency) Cash", amount: cash, currency: currency)
        }

        PortfolioImportService.importSnapshot(
            CSVParser.ParsedCSV(
                headers: [],
                rows: [],
                detectedFormat: .unknown,
                holdings: account.holdings.map {
                    ParsedHolding(
                        name: $0.name,
                        ticker: $0.ticker,
                        isin: $0.isin,
                        sedol: $0.sedol,
                        units: $0.units,
                        priceCurrency: $0.priceCurrency
                    )
                },
                cashBalances: cashBalances
            ),
            into: account
        )
    }
}
