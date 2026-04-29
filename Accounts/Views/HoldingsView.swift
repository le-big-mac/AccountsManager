import SwiftUI
import SwiftData

struct HoldingsView: View {
    @Bindable var account: Account
    @State private var showingAddHolding = false
    @State private var sortMode: HoldingSortMode = .name

    private var canAddManualHoldings: Bool {
        account.investmentSourceType != .snapTrade
    }

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
                if canAddManualHoldings {
                    Button {
                        showingAddHolding = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if account.holdings.isEmpty && account.cashBalances.isEmpty {
                Text(emptyStateMessage)
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

    private var emptyStateMessage: String {
        switch account.investmentSourceType {
        case .snapTrade:
            return "No holdings synced yet. Use Sync to refresh this SnapTrade account."
        case .csvFile:
            return "No holdings yet. Import a CSV or add manually."
        case nil:
            return "No holdings yet. Add manually."
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

    private let robinhoodLossColor = Color(
        red: 235.0 / 255.0,
        green: 93.0 / 255.0,
        blue: 42.0 / 255.0
    )

    private func percentColor(_ value: Decimal) -> Color {
        let displayValue = value.roundedForPercentDisplay()
        if displayValue < 0 {
            return robinhoodLossColor
        }
        if displayValue > 0 {
            return .green
        }
        return .secondary
    }

    private func analystRatingColor(_ rating: AnalystConsensusRating) -> Color {
        switch rating {
        case .strongBuy:
            return .green
        case .buy:
            return Color(red: 82.0 / 255.0, green: 168.0 / 255.0, blue: 104.0 / 255.0)
        case .hold:
            return Color(red: 128.0 / 255.0, green: 128.0 / 255.0, blue: 134.0 / 255.0)
        case .sell:
            return Color(red: 205.0 / 255.0, green: 100.0 / 255.0, blue: 70.0 / 255.0)
        case .strongSell:
            return robinhoodLossColor
        }
    }

    private var unitsText: String {
        if holding.assetClass == .gilt {
            return "\(holding.units.formattedCurrency(code: "GBP")) nominal"
        }
        return "\(holding.units as NSDecimalNumber) units"
    }

    private var priceLabel: String {
        if holding.assetClass == .gilt {
            return "clean \(holding.priceCurrency) \(holding.lastPrice.map { NSDecimalNumber(decimal: $0).stringValue } ?? "--")/100"
        }
        guard let price = holding.lastPrice else { return "" }
        return "@ \(price.formattedCurrency(code: holding.priceCurrency))"
    }

    private var maturityText: String? {
        guard let maturityDate = holding.giltMaturityDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateStyle = .medium
        return "Matures \(formatter.string(from: maturityDate))"
    }

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
                    Text(unitsText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if holding.lastPrice != nil {
                        Text(priceLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if holding.assetClass == .gilt {
                    HStack(spacing: 8) {
                        if let maturityText {
                            Text(maturityText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let metrics = holding.giltMetrics {
                            Text("HTM \(metrics.grossHTMYield.formattedPercent()) p.a.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Total \(metrics.grossTotalReturn.formattedPercent())")
                                .font(.caption)
                                .foregroundStyle(percentColor(metrics.grossTotalReturn))
                        }
                    }
                }
                if let rating = holding.resolvedAnalystConsensusRating {
                    Text(rating.rawValue)
                        .font(.caption)
                        .foregroundStyle(analystRatingColor(rating))
                } else if let error = holding.resolvedAnalystRatingError, !error.isEmpty {
                    Text("Analyst rating unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(error)
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
                        if let openPnLPercent = holding.openPnLPercent {
                            Text(openPnLPercent.formattedPercent())
                                .font(.caption2)
                                .foregroundStyle(percentColor(openPnLPercent))
                        }
                    } else if let openPnLPercent = holding.openPnLPercent {
                        Text(openPnLPercent.formattedPercent())
                            .font(.caption2)
                            .foregroundStyle(percentColor(openPnLPercent))
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
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var ticker = ""
    @State private var isin = ""
    @State private var unitsText = ""
    @State private var averagePurchasePriceText = ""
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
            TextField("Average Purchase Price (optional)", text: $averagePurchasePriceText)
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
        .frame(width: 400, height: 340)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    guard let units = Decimal(string: unitsText) else { return }
                    let trimmedTicker = trimmedIdentifier(ticker)
                    let trimmedISIN = trimmedIdentifier(isin)
                    let averagePurchasePrice = Decimal(string: averagePurchasePriceText)

                    if let existing = existingHolding(ticker: trimmedTicker, isin: trimmedISIN) {
                        merge(
                            units: units,
                            averagePurchasePrice: averagePurchasePrice,
                            into: existing,
                            name: name,
                            ticker: trimmedTicker,
                            isin: trimmedISIN
                        )
                    } else {
                        let holding = Holding(
                            name: name,
                            ticker: trimmedTicker,
                            isin: trimmedISIN,
                            units: units,
                            priceCurrency: priceCurrency,
                            assetClass: assetClass
                        )
                        holding.averagePurchasePrice = averagePurchasePrice
                        account.holdings.append(holding)
                    }
                    dismiss()
                }
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || Decimal(string: unitsText) == nil
                        || (!averagePurchasePriceText.isEmpty && Decimal(string: averagePurchasePriceText) == nil)
                )
            }
        }
    }

    private func existingHolding(ticker: String?, isin: String?) -> Holding? {
        account.holdings.first { holding in
            if let isin, normalizedIdentifier(holding.isin) == isin {
                return true
            }
            if let ticker, normalizedIdentifier(holding.ticker) == ticker {
                return true
            }
            return false
        }
    }

    private func merge(
        units newUnits: Decimal,
        averagePurchasePrice newAveragePurchasePrice: Decimal?,
        into existing: Holding,
        name: String,
        ticker: String?,
        isin: String?
    ) {
        let existingUnits = existing.units
        let totalUnits = existingUnits + newUnits

        if totalUnits > 0 {
            existing.averagePurchasePrice = mergedAveragePurchasePrice(
                existingUnits: existingUnits,
                existingAveragePurchasePrice: existing.averagePurchasePrice,
                newUnits: newUnits,
                newAveragePurchasePrice: newAveragePurchasePrice
            )
        }

        existing.units = totalUnits
        existing.name = name
        if existing.ticker == nil {
            existing.ticker = ticker
        }
        if existing.isin == nil {
            existing.isin = isin
        }
        existing.priceCurrency = priceCurrency
        existing.assetClass = assetClass
    }

    private func mergedAveragePurchasePrice(
        existingUnits: Decimal,
        existingAveragePurchasePrice: Decimal?,
        newUnits: Decimal,
        newAveragePurchasePrice: Decimal?
    ) -> Decimal? {
        switch (existingAveragePurchasePrice, newAveragePurchasePrice) {
        case let (existingPrice?, newPrice?):
            let totalUnits = existingUnits + newUnits
            guard totalUnits > 0 else { return nil }
            return ((existingUnits * existingPrice) + (newUnits * newPrice)) / totalUnits
        case let (existingPrice?, nil):
            return existingPrice
        case let (nil, newPrice?):
            return newPrice
        case (nil, nil):
            return nil
        }
    }

    private func trimmedIdentifier(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedIdentifier(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}
