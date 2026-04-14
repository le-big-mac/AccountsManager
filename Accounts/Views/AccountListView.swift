import SwiftUI
import SwiftData

struct AccountListView: View {
    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.sortOrder)
    private var accounts: [Account]

    @Environment(\.modelContext) private var modelContext
    @State private var showingAddAccount = false
    @State private var importingCSVAccount: Account?
    @State private var queuedCSVImportAccount: Account?
    @State private var connectingSnapTradeAccount: Account?
    @State private var queuedSnapTradeAccount: Account?
    @State private var showingSettings = false
    @State private var selectedAccount: Account?
    @State private var accountPendingDeletion: Account?
    @State private var isRefreshing = false

    private var grandTotal: Decimal {
        accounts.reduce(Decimal.zero) { $0 + $1.currentBalance }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Button {
                    selectedAccount = nil
                } label: {
                    HStack {
                        Image(systemName: "chart.pie.fill")
                            .foregroundStyle(.blue)
                        Text("Overview")
                        Spacer()
                        Text(grandTotal.formattedGBP())
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(selectedAccount == nil ? Color.accentColor.opacity(0.14) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.top, 8)

                List(accounts, selection: $selectedAccount) { account in
                    AccountRow(account: account)
                        .tag(account)
                        .contextMenu {
                            Button("Archive") {
                                account.isArchived = true
                            }
                            Button("Delete", role: .destructive) {
                                accountPendingDeletion = account
                            }
                        }
                }

                Divider()

                HStack {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                    Text(grandTotal.formattedGBP())
                        .font(.system(.headline, design: .rounded, weight: .bold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddAccount = true
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                }
                ToolbarItem {
                    Button {
                        Task { await refreshAll() }
                    } label: {
                        Label(isRefreshing ? "Refreshing..." : "Refresh All",
                              systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                }
                ToolbarItem {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        } detail: {
            if let account = selectedAccount {
                AccountDetailView(account: account)
            } else {
                CombinedAccountsView(accounts: accounts)
            }
        }
        .sheet(isPresented: $showingAddAccount, onDismiss: {
            if let account = queuedCSVImportAccount {
                queuedCSVImportAccount = nil
                importingCSVAccount = account
            } else if let account = queuedSnapTradeAccount {
                queuedSnapTradeAccount = nil
                connectingSnapTradeAccount = account
            }
        }) {
            AddAccountSheet { account in
                selectedAccount = account
                if account.investmentSourceType == .csvFile {
                    queuedCSVImportAccount = account
                } else if account.investmentSourceType == .snapTrade {
                    queuedSnapTradeAccount = account
                }
            }
        }
        .sheet(item: $importingCSVAccount) { account in
            CSVImportView(account: account)
        }
        .sheet(item: $connectingSnapTradeAccount) { account in
            SnapTradeConnectionView(account: account)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .alert(
            "Delete Account?",
            isPresented: Binding(
                get: { accountPendingDeletion != nil },
                set: { if !$0 { accountPendingDeletion = nil } }
            ),
            presenting: accountPendingDeletion
        ) { account in
            Button("Delete", role: .destructive) {
                if selectedAccount == account {
                    selectedAccount = nil
                }
                modelContext.delete(account)
                accountPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                accountPendingDeletion = nil
            }
        } message: { account in
            Text("This removes \(account.name), including holdings, balances, and connection tokens.")
        }
    }

    private func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }

        // Refresh investment prices
        for account in accounts where account.accountType == .investment {
            if account.investmentSourceType == .csvFile {
                PortfolioImportService.refreshLinkedCSV(for: account)
            } else if account.investmentSourceType == .snapTrade {
                try? await SnapTradeImportService.sync(account: account, refreshConnection: true)
            }
        }

        let investmentHoldings = accounts
            .filter { $0.accountType == .investment && $0.investmentSourceType == .csvFile }
            .flatMap { $0.holdings }
        let investmentCash = accounts
            .filter { $0.accountType == .investment }
            .flatMap { $0.cashBalances }
        await PriceService.shared.refreshHoldings(investmentHoldings)
        await PriceService.shared.refreshCashBalances(investmentCash)

        // Refresh bank balances (each account has its own refresh token)
        for account in accounts where account.accountType == .bankAccount {
            guard let accountIds = account.trueLayerAccountId,
                  let refreshToken = account.trueLayerRefreshToken else { continue }
            do {
                let result = try await TrueLayerService.shared.refreshAccessToken(refreshToken: refreshToken)
                if let newRefresh = result.refreshToken {
                    account.trueLayerRefreshToken = newRefresh
                }
                let ids = accountIds.split(separator: ",").map(String.init)
                var total: Decimal = 0
                for id in ids {
                    if let balance = try? await TrueLayerService.shared.fetchBalance(
                        accountId: id, accessToken: result.accessToken
                    ) {
                        total += balance
                    }
                }
                let entry = BalanceEntry(amount: total, source: .bankSync)
                account.balanceEntries.append(entry)
            } catch {
                continue
            }
        }
    }
}
