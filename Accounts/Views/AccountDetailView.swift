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
                    Image(systemName: accountIcon)
                        .font(.title2)
                        .foregroundStyle(accountColor)
                    VStack(alignment: .leading) {
                        Text(account.name)
                            .font(.title2.bold())
                        Text(accountDisplayName)
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
                            Label("Connect Account or Card", systemImage: "building.columns.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        HStack {
                            Label("Connected via TrueLayer", systemImage: "checkmark.circle.fill")
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

    private var accountDisplayName: String {
        if account.accountType == .bankAccount {
            return account.trueLayerResourceType.displayName
        }
        return account.accountType.displayName
    }

    private var accountIcon: String {
        if account.accountType == .bankAccount && account.trueLayerResourceType == .card {
            return "creditcard.fill"
        }
        return account.accountType.sfSymbol
    }

    private var accountColor: Color {
        if account.accountType == .bankAccount && account.trueLayerResourceType == .card {
            return .red
        }
        return account.accountType.defaultColor
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
            Text(account.trueLayerResourceType == .card ? "Outstanding Balance" : "Current Balances")
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

    private func refreshPrices() async {
        isRefreshing = true
        defer { isRefreshing = false }
        if account.investmentSourceType == .snapTrade {
            try? await SnapTradeImportService.sync(account: account, refreshConnection: true)
            return
        }

        await PortfolioImportService.refreshLinkedCSV(for: account)
        await PriceService.shared.refreshHoldings(account.holdings)
        await PriceService.shared.refreshCashBalances(account.cashBalances)
    }

    private func syncBalance() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let accessToken = try await getValidAccessToken()
            await BankSyncService.sync(account: account, accessToken: accessToken)
            try? modelContext.save()
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
