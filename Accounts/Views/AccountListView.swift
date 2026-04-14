import SwiftUI
import SwiftData

struct AccountListView: View {
    @Query(filter: #Predicate<Account> { !$0.isArchived },
           sort: \Account.sortOrder)
    private var accounts: [Account]

    @Environment(\.modelContext) private var modelContext
    @State private var showingAddAccount = false
    @State private var showingCSVImport = false
    @State private var showingSettings = false
    @State private var selectedAccount: Account?
    @State private var isRefreshing = false

    private var grandTotal: Decimal {
        accounts.reduce(Decimal.zero) { $0 + $1.currentBalance }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(accounts, selection: $selectedAccount) { account in
                    AccountRow(account: account)
                        .tag(account)
                        .contextMenu {
                            Button("Archive") {
                                account.isArchived = true
                            }
                            Button("Delete", role: .destructive) {
                                if selectedAccount == account {
                                    selectedAccount = nil
                                }
                                modelContext.delete(account)
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
                ContentUnavailableView(
                    "Select an Account",
                    systemImage: "chart.bar.fill",
                    description: Text("Choose an account from the sidebar to view details")
                )
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AddAccountSheet()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }

        // Refresh investment prices
        let investmentHoldings = accounts
            .filter { $0.accountType == .investment }
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
