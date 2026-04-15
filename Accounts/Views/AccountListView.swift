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
    @State private var draggedAccount: Account?
    @State private var dropTargetAccountID: UUID?
    @State private var hasRecoveredDetachedHoldings = false

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
                    .contentShape(Rectangle())
                    .background(selectedAccount == nil ? Color.accentColor.opacity(0.14) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.top, 8)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(accounts) { account in
                            AccountRow(account: account)
                                .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .background(selectedAccount == account ? Color.accentColor.opacity(0.14) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .top) {
                                    if showsDropIndicator(for: account, edge: .top) {
                                        AccountDropIndicator()
                                    }
                                }
                                .overlay(alignment: .bottom) {
                                    if showsDropIndicator(for: account, edge: .bottom) {
                                        AccountDropIndicator()
                                    }
                                }
                                .onTapGesture {
                                    selectedAccount = account
                                }
                                .draggable(account.id.uuidString) {
                                    Color.clear
                                        .frame(width: 1, height: 1)
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    guard let id = items.first,
                                          let dragged = accounts.first(where: { $0.id.uuidString == id }) else {
                                        return false
                                    }
                                    moveAccount(dragged, before: account)
                                    draggedAccount = nil
                                    dropTargetAccountID = nil
                                    return true
                                } isTargeted: { targeted in
                                    if targeted {
                                        dropTargetAccountID = account.id
                                    } else if dropTargetAccountID == account.id {
                                        dropTargetAccountID = nil
                                    }
                                }
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 2)
                                        .onChanged { _ in
                                            draggedAccount = account
                                        }
                                )
                            .contextMenu {
                                Button("Archive") {
                                    account.isArchived = true
                                    normalizeSortOrder()
                                }
                                Button("Delete", role: .destructive) {
                                    accountPendingDeletion = account
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
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
            .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 460)
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
        .onAppear {
            normalizeSortOrderIfNeeded()
            recoverDetachedHoldingMetadataIfNeeded()
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
                normalizeSortOrder()
                accountPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                accountPendingDeletion = nil
            }
        } message: { account in
            Text("This removes \(account.name), including holdings, balances, and connection tokens.")
        }
    }

    private func normalizeSortOrderIfNeeded() {
        let orders = accounts.map(\.sortOrder)
        guard Set(orders).count != orders.count || orders.contains(0) else { return }
        normalizeSortOrder()
    }

    private func recoverDetachedHoldingMetadataIfNeeded() {
        guard !hasRecoveredDetachedHoldings else { return }
        hasRecoveredDetachedHoldings = true

        let descriptor = FetchDescriptor<Holding>()
        guard let allHoldings = try? modelContext.fetch(descriptor) else { return }

        let orphanHoldings = allHoldings.filter { $0.account == nil }
        guard !orphanHoldings.isEmpty else { return }

        let liveHoldings = accounts.flatMap(\.holdings)
        var matchedOrphanIDs = Set<PersistentIdentifier>()

        for liveHolding in liveHoldings {
            guard let orphan = orphanHoldings.first(where: { orphan in
                holdingIdentifierKey(for: orphan) == holdingIdentifierKey(for: liveHolding)
            }) else {
                continue
            }

            if liveHolding.analystConsensusTarget == nil, let value = orphan.analystConsensusTarget {
                liveHolding.analystConsensusTarget = value
            }
            if liveHolding.analystTargetLow == nil, let value = orphan.analystTargetLow {
                liveHolding.analystTargetLow = value
            }
            if liveHolding.analystTargetHigh == nil, let value = orphan.analystTargetHigh {
                liveHolding.analystTargetHigh = value
            }
            if liveHolding.analystTargetCurrencyRaw.isEmpty, !orphan.analystTargetCurrencyRaw.isEmpty {
                liveHolding.analystTargetCurrencyRaw = orphan.analystTargetCurrencyRaw
            }
            if liveHolding.analystTargetUpdatedAt == nil, let updatedAt = orphan.analystTargetUpdatedAt {
                liveHolding.analystTargetUpdatedAt = updatedAt
            }
            if liveHolding.averagePurchasePrice == nil, let averagePurchasePrice = orphan.averagePurchasePrice {
                liveHolding.averagePurchasePrice = averagePurchasePrice
            }

            matchedOrphanIDs.insert(orphan.persistentModelID)
        }

        for orphan in orphanHoldings where matchedOrphanIDs.contains(orphan.persistentModelID) {
            modelContext.delete(orphan)
        }
    }

    private func holdingIdentifierKey(for holding: Holding) -> String {
        if let ticker = normalizedIdentifier(holding.ticker), !ticker.isEmpty {
            return "ticker:\(ticker)"
        }
        if let isin = normalizedIdentifier(holding.isin), !isin.isEmpty {
            return "isin:\(isin)"
        }
        if let sedol = normalizedIdentifier(holding.sedol), !sedol.isEmpty {
            return "sedol:\(sedol)"
        }
        return "name:\(normalizedIdentifier(holding.name) ?? "")"
    }

    private func normalizedIdentifier(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private func normalizeSortOrder() {
        applySortOrder(to: accounts)
    }

    private func moveAccount(_ dragged: Account, before target: Account) {
        guard dragged != target,
              let fromIndex = accounts.firstIndex(of: dragged),
              let toIndex = accounts.firstIndex(of: target) else {
            return
        }

        var reordered = accounts
        reordered.move(
            fromOffsets: IndexSet(integer: fromIndex),
            toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
        )
        applySortOrder(to: reordered)
    }

    private func showsDropIndicator(for account: Account, edge: VerticalEdge) -> Bool {
        guard dropTargetAccountID == account.id,
              let draggedAccount,
              draggedAccount != account,
              let fromIndex = accounts.firstIndex(of: draggedAccount),
              let toIndex = accounts.firstIndex(of: account) else {
            return false
        }

        return fromIndex < toIndex ? edge == .bottom : edge == .top
    }

    private func applySortOrder(to orderedAccounts: [Account]) {
        for (index, account) in orderedAccounts.enumerated() {
            account.sortOrder = (index + 1) * 10
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
            guard let refreshToken = account.trueLayerRefreshToken else { continue }
            do {
                let result = try await TrueLayerService.shared.refreshAccessToken(refreshToken: refreshToken)
                if let newRefresh = result.refreshToken {
                    account.trueLayerRefreshToken = newRefresh
                }
                await BankSyncService.sync(account: account, accessToken: result.accessToken)
            } catch {
                continue
            }
        }
    }
}

private struct AccountDropIndicator: View {
    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 3)
            .padding(.horizontal, 6)
            .shadow(color: Color.accentColor.opacity(0.4), radius: 2)
    }
}
