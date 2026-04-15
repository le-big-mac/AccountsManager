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
        let positions = response.positions ?? []
        let balances = response.balances ?? []
        let parsedHoldings = parsedHoldings(from: positions)
        let parsedCashBalances = await parsedCashBalances(from: balances)

        PortfolioImportService.importSnapshot(
            CSVParser.ParsedCSV(
                headers: [],
                rows: [],
                detectedFormat: .unknown,
                holdings: parsedHoldings,
                cashBalances: parsedCashBalances
            ),
            into: account
        )

        updateHoldingPrices(from: positions, in: account)
        account.snapTradeSyncedAt = Date()

        if let snapTradeAccount = response.account {
            account.snapTradeAuthorizationId = snapTradeAccount.brokerageAuthorization
            account.snapTradeInstitutionName = snapTradeAccount.institutionName
        }

        await PriceService.shared.refreshHoldingFXRates(account.holdings)
        await PriceService.shared.refreshCashBalances(account.cashBalances)
    }

    private static func parsedHoldings(from positions: [SnapTradePosition]) -> [ParsedHolding] {
        positions.compactMap { position -> ParsedHolding? in
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
                priceCurrency: currency,
                assetClass: HoldingAssetClass.from(name) ?? .stock
            )
        }
    }

    private static func updateHoldingPrices(from positions: [SnapTradePosition], in account: Account) {
        for holding in account.holdings {
            guard let position = positions.first(where: { ($0.symbol?.symbol?.symbol ?? $0.symbol?.symbol?.rawSymbol) == holding.ticker }),
                  let price = position.price else { continue }
            holding.lastPrice = price
            holding.priceCurrency = position.currency?.code ?? position.symbol?.symbol?.currency?.code ?? holding.priceCurrency
            holding.lastPriceDate = Date()
        }
    }

    private static func parsedCashBalances(from balances: [SnapTradeBalance]) async -> [ParsedCashBalance] {
        var fxRates: [String: Decimal] = [:]
        let currencies = Set(balances.compactMap { balance -> String? in
            guard let cash = balance.cash, cash != 0 else { return nil }
            return (balance.currency?.code ?? "USD").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        })

        for currency in currencies {
            switch currency {
            case "GBP":
                fxRates[currency] = 1
            case "GBX":
                fxRates[currency] = Decimal(string: "0.01") ?? 0.01
            default:
                fxRates[currency] = try? await PriceService.shared.fetchFXRateToGBP(from: currency)
            }
        }

        return balances.compactMap { balance -> ParsedCashBalance? in
            guard let cash = balance.cash,
                  cash != 0 else { return nil }
            let currency = (balance.currency?.code ?? "USD").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return ParsedCashBalance(
                name: "\(currency) Cash",
                amount: cash,
                currency: currency,
                fxRateToGBP: fxRates[currency]
            )
        }
    }
}
