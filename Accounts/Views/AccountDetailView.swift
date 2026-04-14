import SwiftUI
import SwiftData

struct AccountDetailView: View {
    @Bindable var account: Account
    @Environment(\.modelContext) private var modelContext
    @State private var isRefreshing = false
    @State private var showingCSVImport = false
    @State private var showingBankConnection = false

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
                    Text(account.currentBalance.formattedGBP())
                        .font(.system(.title, design: .rounded, weight: .bold))
                }

                Divider()

                if account.accountType == .investment {
                    HoldingsView(account: account)

                    HStack {
                        Button {
                            showingCSVImport = true
                        } label: {
                            Label("Import CSV", systemImage: "doc.badge.plus")
                        }

                        Button {
                            Task { await refreshPrices() }
                        } label: {
                            Label(isRefreshing ? "Refreshing..." : "Refresh Prices",
                                  systemImage: "arrow.clockwise")
                        }
                        .disabled(isRefreshing)
                    }
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

                    balanceHistorySection
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
    }

    @ViewBuilder
    private var balanceHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Balance History")
                .font(.headline)

            let sorted = account.balanceEntries.sorted { $0.date > $1.date }
            if sorted.isEmpty {
                Text("No balance history yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sorted.prefix(20)) { entry in
                    HStack {
                        Text(entry.date, style: .date)
                            .font(.subheadline)
                        Spacer()
                        Text(entry.amount.formattedGBP())
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                        Text(entry.source.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Divider()
                }
            }
        }
    }

    private func refreshPrices() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await PriceService.shared.refreshHoldings(account.holdings)
    }

    private func syncBalance() async {
        isRefreshing = true
        defer { isRefreshing = false }
        guard let accountIds = account.trueLayerAccountId else { return }

        do {
            let accessToken = try await getValidAccessToken()
            let ids = accountIds.split(separator: ",").map(String.init)
            var total: Decimal = 0
            for id in ids {
                if let balance = try? await TrueLayerService.shared.fetchBalance(
                    accountId: id, accessToken: accessToken
                ) {
                    total += balance
                }
            }
            let entry = BalanceEntry(amount: total, source: .bankSync)
            account.balanceEntries.append(entry)
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
