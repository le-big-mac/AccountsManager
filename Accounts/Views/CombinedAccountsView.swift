import Charts
import SwiftUI

struct CombinedAccountsView: View {
    let accounts: [Account]

    private var entries: [AllocationEntry] {
        AllocationCalculator.entries(for: accounts)
    }

    private var total: Decimal {
        entries.reduce(Decimal.zero) { $0 + $1.value }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Overview")
                            .font(.title2.bold())
                        Text("Across all accounts")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(total.formattedGBP())
                        .font(.system(.title, design: .rounded, weight: .bold))
                }

                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Wealth Data",
                        systemImage: "chart.pie",
                        description: Text("Add bank balances, cash, or holdings to see your allocation.")
                    )
                } else {
                    HStack(alignment: .center, spacing: 32) {
                        Chart(entries) { entry in
                            SectorMark(
                                angle: .value("Value", entry.valueDouble),
                                innerRadius: .ratio(0.62),
                                angularInset: 1.5
                            )
                            .foregroundStyle(entry.color)
                        }
                        .chartLegend(.hidden)
                        .frame(width: 280, height: 280)

                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(entries) { entry in
                                AllocationRow(entry: entry, total: total)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accounts")
                            .font(.headline)

                        ForEach(accounts) { account in
                            HStack {
                                Label(account.name, systemImage: account.accountType.sfSymbol)
                                    .foregroundStyle(account.accountType.defaultColor)
                                Spacer()
                                Text(account.currentBalance.formattedGBP())
                                    .font(.system(.body, design: .rounded, weight: .semibold))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

private struct AllocationRow: View {
    let entry: AllocationEntry
    let total: Decimal

    private var percent: Decimal {
        guard total != 0 else { return 0 }
        return entry.value / total
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(entry.color)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.subheadline.weight(.medium))
                Text(percent.formattedPercent())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            Text(entry.value.formattedGBP())
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
        }
        .frame(minWidth: 260)
    }
}

struct AllocationEntry: Identifiable {
    let id: String
    let name: String
    let value: Decimal
    let color: Color

    var valueDouble: Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

enum AllocationCalculator {
    static func entries(for accounts: [Account]) -> [AllocationEntry] {
        var totals: [String: Decimal] = [:]

        for account in accounts {
            switch account.accountType {
            case .bankAccount:
                totals["Cash", default: 0] += account.currentBalance
            case .investment:
                let cash = account.cashBalances.reduce(Decimal.zero) { $0 + $1.amountGBP }
                totals["Cash", default: 0] += cash

                for holding in account.holdings {
                    totals[holding.assetClass.displayName, default: 0] += holding.currentValueGBP
                }
            }
        }

        let order = ["Cash", "Securities", "ETFs", "Funds", "Other"]
        return totals
            .filter { $0.value > 0 }
            .map { name, value in
                AllocationEntry(id: name, name: name, value: value, color: color(for: name))
            }
            .sorted { lhs, rhs in
                let lhsIndex = order.firstIndex(of: lhs.name) ?? order.count
                let rhsIndex = order.firstIndex(of: rhs.name) ?? order.count
                if lhsIndex == rhsIndex { return lhs.value > rhs.value }
                return lhsIndex < rhsIndex
            }
    }

    private static func color(for name: String) -> Color {
        switch name {
        case "Cash": .green
        case "Securities": .blue
        case "ETFs": .teal
        case "Funds": .indigo
        default: .gray
        }
    }
}
