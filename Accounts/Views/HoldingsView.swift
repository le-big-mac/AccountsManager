import SwiftUI
import SwiftData

struct HoldingsView: View {
    @Bindable var account: Account
    @Environment(\.modelContext) private var modelContext
    @State private var showingAddHolding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Holdings")
                    .font(.headline)
                Spacer()
                Button {
                    showingAddHolding = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            if account.holdings.isEmpty {
                Text("No holdings yet. Import a CSV or add manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(account.holdings) { holding in
                    HoldingRow(holding: holding)
                    Divider()
                }
            }
        }
        .sheet(isPresented: $showingAddHolding) {
            AddHoldingSheet(account: account)
        }
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
                        if holding.priceCurrency != "GBP", holding.effectiveFXRateToGBP > 0 {
                            Text("FX \(holding.effectiveFXRateToGBP as NSDecimalNumber)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
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

    private let supportedCurrencies = ["GBP", "USD"]

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
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 260)
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
                        priceCurrency: priceCurrency
                    )
                    account.holdings.append(holding)
                    dismiss()
                }
                .disabled(name.isEmpty || Decimal(string: unitsText) == nil)
            }
        }
    }
}
