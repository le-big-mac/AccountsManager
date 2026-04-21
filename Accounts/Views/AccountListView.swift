import AppKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @State private var isExporting = false
    @State private var draggedAccount: Account?
    @State private var dropTargetAccountID: UUID?
    @State private var hasMigratedSecurityMetadata = false
    @State private var exportAlert: ExportAlert?
    @FocusState private var isSidebarFocused: Bool

    private var grandTotal: Decimal {
        accounts.reduce(Decimal.zero) { $0 + $1.currentBalance }
    }

    var body: some View {
        NavigationSplitView {
            ScrollViewReader { proxy in
                sidebarContent(proxy: proxy)
                .focusable()
                .focusEffectDisabled()
                .focused($isSidebarFocused)
                .contentShape(Rectangle())
                .onTapGesture {
                    isSidebarFocused = true
                }
                .onMoveCommand { direction in
                    handleSidebarMove(direction, proxy: proxy)
                }
                .onChange(of: selectedAccount?.id) { _, _ in
                    scrollToSelection(using: proxy)
                }
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
                        exportPortfolioCSV()
                    } label: {
                        Label(isExporting ? "Exporting..." : "Export CSV",
                              systemImage: "square.and.arrow.up")
                    }
                    .disabled(isExporting || accounts.isEmpty)
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
            migrateSecurityMetadataIfNeeded()
            DispatchQueue.main.async {
                isSidebarFocused = true
            }
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
        .alert(item: $exportAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private func sidebarContent(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            overviewButton

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(accounts) { account in
                        sidebarAccountRow(account)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }

            Divider()

            sidebarFooter
        }
    }

    private var overviewButton: some View {
        Button {
            selectOverview()
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
        .id(sidebarOverviewID)
    }

    @ViewBuilder
    private func sidebarAccountRow(_ account: Account) -> some View {
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
                selectAccount(account)
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
            .id(account.id)
    }

    private var sidebarFooter: some View {
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

    private var sidebarOverviewID: String { "sidebar-overview" }

    private func exportPortfolioCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText, .text]
        panel.nameFieldStringValue = PortfolioCSVExporter.defaultFilename()
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        defer { isExporting = false }

        do {
            try PortfolioCSVExporter.export(accounts: accounts, to: url)
            exportAlert = ExportAlert(
                title: "Export Complete",
                message: "Portfolio exported to \(url.lastPathComponent)."
            )
        } catch {
            exportAlert = ExportAlert(
                title: "Export Failed",
                message: error.localizedDescription
            )
        }
    }

    private func normalizeSortOrderIfNeeded() {
        let orders = accounts.map(\.sortOrder)
        guard Set(orders).count != orders.count || orders.contains(0) else { return }
        normalizeSortOrder()
    }

    private func migrateSecurityMetadataIfNeeded() {
        guard !hasMigratedSecurityMetadata else { return }
        hasMigratedSecurityMetadata = true

        let holdingsDescriptor = FetchDescriptor<Holding>()
        let metadataDescriptor = FetchDescriptor<SecurityMetadata>()
        guard let allHoldings = try? modelContext.fetch(holdingsDescriptor) else { return }
        let existingMetadata = (try? modelContext.fetch(metadataDescriptor)) ?? []

        var metadataByKey = Dictionary(uniqueKeysWithValues: existingMetadata.map { ($0.securityKey, $0) })

        for holding in allHoldings {
            let key = holdingIdentifierKey(for: holding)
            let metadata: SecurityMetadata
            if let existing = metadataByKey[key] {
                metadata = existing
            } else {
                let created = SecurityMetadata(securityKey: key)
                modelContext.insert(created)
                metadataByKey[key] = created
                metadata = created
            }

            if metadata.analystConsensusTarget == nil, let value = holding.analystConsensusTarget {
                metadata.analystConsensusTarget = value
            }
            if metadata.analystTargetLow == nil, let value = holding.analystTargetLow {
                metadata.analystTargetLow = value
            }
            if metadata.analystTargetHigh == nil, let value = holding.analystTargetHigh {
                metadata.analystTargetHigh = value
            }
            if metadata.analystTargetCurrencyRaw.isEmpty, !holding.analystTargetCurrencyRaw.isEmpty {
                metadata.analystTargetCurrencyRaw = holding.analystTargetCurrencyRaw
            }
            if metadata.analystTargetUpdatedAt == nil, let updatedAt = holding.analystTargetUpdatedAt {
                metadata.analystTargetUpdatedAt = updatedAt
            }

            holding.securityMetadata = metadata
        }

        PriceService.shared.primeSecurityMetadata(Array(metadataByKey.values))

        for orphan in allHoldings where orphan.account == nil {
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

    private func selectOverview() {
        selectedAccount = nil
        isSidebarFocused = true
    }

    private func selectAccount(_ account: Account) {
        selectedAccount = account
        isSidebarFocused = true
    }

    private func handleSidebarMove(_ direction: MoveCommandDirection, proxy: ScrollViewProxy) {
        switch direction {
        case .up:
            moveSelection(by: -1)
        case .down:
            moveSelection(by: 1)
        default:
            return
        }
        scrollToSelection(using: proxy)
    }

    private func moveSelection(by delta: Int) {
        if accounts.isEmpty { return }

        let currentIndex: Int
        if let selectedAccount,
           let index = accounts.firstIndex(of: selectedAccount) {
            currentIndex = index + 1
        } else {
            currentIndex = 0
        }

        let nextIndex = currentIndex + delta
        if nextIndex <= 0 {
            selectedAccount = nil
            return
        }
        guard nextIndex <= accounts.count else { return }
        selectedAccount = accounts[nextIndex - 1]
    }

    private func scrollToSelection(using proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.12)) {
            if let selectedAccount {
                proxy.scrollTo(selectedAccount.id, anchor: .center)
            } else {
                proxy.scrollTo(sidebarOverviewID, anchor: .center)
            }
        }
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
                await PortfolioImportService.refreshLinkedCSV(for: account)
            } else if account.investmentSourceType == .snapTrade {
                try? await SnapTradeImportService.sync(account: account, refreshConnection: true)
            }
            await Task.yield()
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
            await Task.yield()
        }
    }
}

private struct ExportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
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
