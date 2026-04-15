import SwiftUI
import SwiftData

struct AccountDetailView: View {
    @Bindable var account: Account
    @Environment(\.modelContext) private var modelContext
    @State private var isRefreshing = false
    @State private var showingCSVImport = false
    @State private var showingBankConnection = false
    @State private var showingSnapTradeConnection = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Image(systemName: account.accountType.sfSymbol)
                        .font(.title2)
                        .foregroundStyle(account.accountType.defaultColor)
                    VStack(alignment: .leading) {
                        Text(account.name)
                            .font(.title2.bold())
                        Text(account.accountType.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(account.currentBalance.formattedGBP())
                            .font(.system(.title, design: .rounded, weight: .bold))
                        if let breakdown = account.originalCurrencyBreakdownText {
                            Text(breakdown)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                if account.accountType == .investment {
                    investmentActions
                    HoldingsView(account: account)
                } else {
                    // Bank account
                    if account.trueLayerAccountId == nil {
                        Button {
                            showingBankConnection = true
                        } label: {
                            Label("Connect Bank Account", systemImage: "building.columns.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        HStack {
                            Label("Connected via Open Banking", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Button {
                                Task { await syncBalance() }
                            } label: {
                                Label(isRefreshing ? "Syncing..." : "Sync Balance",
                                      systemImage: "arrow.clockwise")
                            }
                            .disabled(isRefreshing)
                        }
                    }

                    bankHoldingsSection
                    recentTransactionsSection
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingCSVImport) {
            CSVImportView(account: account)
        }
        .sheet(isPresented: $showingBankConnection) {
            BankConnectionView(account: account)
        }
        .sheet(isPresented: $showingSnapTradeConnection) {
            SnapTradeConnectionView(account: account)
        }
    }

    private var refreshLabel: String {
        account.investmentSourceType == .snapTrade ? "Sync SnapTrade" : "Refresh Prices"
    }

    private var investmentActions: some View {
        HStack {
            if account.investmentSourceType == .snapTrade {
                Label(account.snapTradeInstitutionName ?? "SnapTrade", systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let csvSourcePath = account.csvSourcePath {
                Label(URL(fileURLWithPath: csvSourcePath).lastPathComponent, systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if account.investmentSourceType == .snapTrade {
                Button {
                    showingSnapTradeConnection = true
                } label: {
                    Label(account.snapTradeAccountId == nil ? "Connect Brokerage" : "Reconnect", systemImage: "link.badge.plus")
                }
            } else {
                Button {
                    showingCSVImport = true
                } label: {
                    Label("Import CSV", systemImage: "doc.badge.plus")
                }
            }

            Button {
                Task { await refreshPrices() }
            } label: {
                Label(isRefreshing ? "Refreshing..." : refreshLabel,
                      systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)
        }
    }

    @ViewBuilder
    private var bankHoldingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Balances")
                .font(.headline)

            let sorted = account.bankBalances.sorted { lhs, rhs in
                if lhs.currency == rhs.currency {
                    return lhs.effectiveDisplayName < rhs.effectiveDisplayName
                }
                return lhs.currency < rhs.currency
            }
            if sorted.isEmpty {
                Text("No bank balances synced yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sorted, id: \.id) { balance in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(balance.effectiveDisplayName)
                                .font(.subheadline)
                            Text("Updated \(balance.updatedAt.relativeFormatted())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(balance.amount.formattedCurrency(code: balance.currency))
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            if balance.currency != "GBP" {
                                Text(balance.amountGBP.formattedGBP())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Transactions")
                .font(.headline)

            let recentTransactions: [BankTransaction] = account.bankTransactions
                .sorted { $0.date > $1.date }
                .prefix(10)
                .map { $0 }
            if recentTransactions.isEmpty {
                Text("No transactions synced yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(0..<recentTransactions.count), id: \.self) { index in
                    transactionRow(recentTransactions[index])
                    Divider()
                }
            }
        }
    }

    private func transactionRow(_ transaction: BankTransaction) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.descriptionText)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(transaction.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(transaction.amount.formattedCurrency(code: transaction.currency))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(transaction.amount < 0 ? Color.primary : Color.green)
        }
    }

    private func refreshPrices() async {
        isRefreshing = true
        defer { isRefreshing = false }
        if account.investmentSourceType == .snapTrade {
            try? await SnapTradeImportService.sync(account: account, refreshConnection: true)
            return
        }

        PortfolioImportService.refreshLinkedCSV(for: account)
        await PriceService.shared.refreshHoldings(account.holdings)
        await PriceService.shared.refreshCashBalances(account.cashBalances)
    }

    private func syncBalance() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let accessToken = try await getValidAccessToken()
            await BankSyncService.sync(account: account, accessToken: accessToken)
        } catch {
            // Token refresh failed
        }
    }

    private func getValidAccessToken() async throws -> String {
        guard let refreshToken = account.trueLayerRefreshToken else {
            throw TrueLayerError.notConfigured
        }
        let result = try await TrueLayerService.shared.refreshAccessToken(refreshToken: refreshToken)
        if let newRefresh = result.refreshToken {
            account.trueLayerRefreshToken = newRefresh
        }
        return result.accessToken
    }
}
