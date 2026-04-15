import SwiftUI
import SwiftData

struct HoldingsView: View {
    @Bindable var account: Account
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddHolding = false
    @State private var sortMode: HoldingSortMode = .name

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Holdings")
                    .font(.headline)
                Spacer()
                Picker("Sort", selection: $sortMode) {
                    ForEach(HoldingSortMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                Button {
                    showingAddHolding = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            if account.holdings.isEmpty && account.cashBalances.isEmpty {
                Text("No holdings yet. Import a CSV or add manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                if !account.cashBalances.isEmpty {
                    Text("Cash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(account.cashBalances) { cash in
                        CashBalanceRow(cash: cash)
                        Divider()
                    }
                }

                if !account.holdings.isEmpty {
                    Text("Securities")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedHoldings) { holding in
                    HoldingRow(holding: holding)
                    Divider()
                }
            }
        }
        .sheet(isPresented: $showingAddHolding) {
            AddHoldingSheet(account: account)
        }
    }

    private var sortedHoldings: [Holding] {
        switch sortMode {
        case .name:
            return account.holdings.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .value:
            return account.holdings.sorted {
                if $0.currentValueGBP == $1.currentValueGBP {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.currentValueGBP > $1.currentValueGBP
            }
        }
    }
}

enum HoldingSortMode: String, CaseIterable, Identifiable {
    case name
    case value

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name: "A-Z"
        case .value: "Value"
        }
    }
}

struct CashBalanceRow: View {
    let cash: CashBalance

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(cash.name)
                    .font(.subheadline)
                HStack(spacing: 4) {
                    Text(cash.amount.formattedCurrency(code: cash.currency))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(cash.amountGBP.formattedGBP())
                .font(.system(.body, design: .rounded, weight: .semibold))
        }
        .padding(.vertical, 2)
    }
}

struct HoldingRow: View {
    let holding: Holding

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let ticker = holding.ticker {
                        Text(ticker)
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Text(holding.name)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text("\(holding.units as NSDecimalNumber) units")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let price = holding.lastPrice {
                        Text("@ \(price.formattedCurrency(code: holding.priceCurrency))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let target = holding.analystConsensusTarget {
                    HStack(spacing: 4) {
                        Text("Target \(target.formattedCurrency(code: holding.analystTargetCurrency))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let upside = holding.analystConsensusUpsidePercent {
                            Text(upside.formattedPercent())
                                .font(.caption)
                                .foregroundStyle(upside < 0 ? Color.orange : Color.green)
                        }
                    }
                }
            }

            Spacer()

            if holding.lastPrice != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(holding.currentValueGBP.formattedGBP())
                        .font(.system(.body, design: .rounded, weight: .semibold))
                    if holding.priceCurrency != "GBP" {
                        Text(holding.localCurrentValue.formattedCurrency(code: holding.priceCurrency))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("--")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct AddHoldingSheet: View {
    let account: Account
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var ticker = ""
    @State private var isin = ""
    @State private var unitsText = ""
    @State private var priceCurrency = "GBP"
    @State private var assetClass: HoldingAssetClass = .stock

    private let supportedCurrencies = ["GBP", "USD"]
    private let supportedAssetClasses = HoldingAssetClass.allCases.filter { $0 != .cash }

    var body: some View {
        Form {
            TextField("Name (e.g. Vanguard FTSE All-World)", text: $name)
            TextField("Ticker (e.g. VWRL.L or AAPL)", text: $ticker)
            TextField("ISIN (optional, e.g. GB00BD3RZ582)", text: $isin)
            TextField("Units / Shares", text: $unitsText)
            Picker("Price Currency", selection: $priceCurrency) {
                ForEach(supportedCurrencies, id: \.self) { currency in
                    Text(currency).tag(currency)
                }
            }
            Picker("Asset Class", selection: $assetClass) {
                ForEach(supportedAssetClasses) { assetClass in
                    Text(assetClass.displayName).tag(assetClass)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    guard let units = Decimal(string: unitsText) else { return }
                    let holding = Holding(
                        name: name,
                        ticker: ticker.isEmpty ? nil : ticker,
                        isin: isin.isEmpty ? nil : isin,
                        units: units,
                        priceCurrency: priceCurrency,
                        assetClass: assetClass
                    )
                    account.holdings.append(holding)
                    dismiss()
                }
                .disabled(name.isEmpty || Decimal(string: unitsText) == nil)
            }
        }
    }
}
