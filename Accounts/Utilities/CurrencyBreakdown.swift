import Foundation

struct CurrencyBreakdownItem: Identifiable {
    let currency: String
    let amount: Decimal

    var id: String { currency }
}

extension Account {
    var originalCurrencyBreakdown: [CurrencyBreakdownItem] {
        guard accountType == .investment else { return [] }

        var totals: [String: Decimal] = [:]

        for holding in holdings {
            let currency = reportingCurrency(for: holding.priceCurrency)
            let amount = reportingAmount(
                holding.localCurrentValue,
                currency: holding.priceCurrency
            )
            totals[currency, default: 0] += amount
        }

        for cash in cashBalances {
            totals[reportingCurrency(for: cash.currency), default: 0] += reportingAmount(
                cash.amount,
                currency: cash.currency
            )
        }

        let nonZero = totals
            .filter { $0.value != 0 }
            .map { CurrencyBreakdownItem(currency: $0.key, amount: $0.value) }
            .sorted { lhs, rhs in
                if lhs.currency == "GBP" { return true }
                if rhs.currency == "GBP" { return false }
                return lhs.currency < rhs.currency
            }

        guard !nonZero.isEmpty,
              !(nonZero.count == 1 && nonZero[0].currency == "GBP") else {
            return []
        }

        return nonZero
    }

    var originalCurrencyBreakdownText: String? {
        let breakdown = originalCurrencyBreakdown
        guard !breakdown.isEmpty else { return nil }
        return breakdown
            .map { $0.amount.formattedCurrencyBreakdown(code: $0.currency) }
            .joined(separator: ", ")
    }

    private func reportingCurrency(for currency: String) -> String {
        currency.uppercased() == "GBX" ? "GBP" : currency.uppercased()
    }

    private func reportingAmount(_ amount: Decimal, currency: String) -> Decimal {
        currency.uppercased() == "GBX" ? amount * 0.01 : amount
    }
}
