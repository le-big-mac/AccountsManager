import SwiftUI
import SwiftData

struct BankConnectionView: View {
    let account: Account
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @Query(filter: #Predicate<Account> { !$0.isArchived })
    private var allAccounts: [Account]

    @State private var status: ConnectionStatus = .ready
    @State private var error: String?
    @State private var bankAccounts: [TrueLayerService.BankAccount] = []
    @State private var balancePreviews: [String: TrueLayerService.BalanceSnapshot] = [:]
    @State private var accessToken: String?
    @State private var expectedState: String?

    /// Provider names already connected to other accounts in the app
    private var alreadyConnectedProviders: Set<String> {
        var providers = Set<String>()
        for a in allAccounts where a.id != account.id {
            if let provider = a.trueLayerProvider {
                providers.insert(normalizedProviderKey(provider))
            }
        }
        return providers
    }

    private func normalizedProviderKey(_ provider: String) -> String {
        provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func providerKeys(for bankAccount: TrueLayerService.BankAccount) -> Set<String> {
        [
            bankAccount.provider?.providerId,
            bankAccount.provider?.displayName,
        ]
        .compactMap { $0 }
        .map(normalizedProviderKey)
        .reduce(into: Set<String>()) { $0.insert($1) }
    }

    private func providerStorageValue(for bankAccount: TrueLayerService.BankAccount) -> String? {
        bankAccount.provider?.providerId ?? bankAccount.provider?.displayName
    }

    enum ConnectionStatus {
        case ready
        case waitingForAuth
        case selectingAccount
        case connected
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Connect \(account.name)")
                .font(.title2.bold())

            switch status {
            case .ready:
                readyView
            case .waitingForAuth:
                waitingView
            case .selectingAccount:
                accountSelectionView
            case .connected:
                connectedView
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
        .frame(width: 420, height: 400)
        .padding()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onChange(of: appState.trueLayerCallback?.state) { _, _ in
            if let callback = appState.trueLayerCallback,
               status == .waitingForAuth,
               callback.state == expectedState {
                appState.trueLayerCallback = nil
                Task { await handleAuthCode(callback.code) }
            }
        }
    }

    private var readyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Connect your bank account via Open Banking")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("You'll be redirected to select your bank and log in. TrueLayer is FCA-regulated. Read-only access, 90-day consent.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button("Connect Bank Account") {
                Task { await openTrueLayerAuth() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var waitingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text("Waiting for bank authorisation...")
                .font(.headline)

            Text("Complete the login in your browser. The app will connect automatically when done.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var accountSelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(bankAccounts.count) accounts found")
                .font(.headline)

            // Connect all button
            Button {
                connectAllAccounts()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect all accounts")
                            .font(.subheadline.weight(.medium))
                        Text("Balances will be summed together")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !balancePreviews.isEmpty {
                        Text(previewBreakdown)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    }
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Divider()

            Text("Or select one:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(bankAccounts) { bankAccount in
                        Button {
                            selectAccount(bankAccount)
                        } label: {
                            HStack {
                                Text(bankAccount.label)
                                    .foregroundStyle(.primary)
                                    .font(.subheadline)
                                Spacer()
                                if let balance = balancePreviews[bankAccount.accountId] {
                                    Text(balance.amount.formattedCurrency(code: balance.currency))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(.quaternary.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var connectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Connected!")
                .font(.headline)

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func openTrueLayerAuth() async {
        guard let result = await TrueLayerService.shared.buildAuthURL() else {
            error = "TrueLayer not configured. Add credentials in Settings."
            return
        }
        expectedState = result.state
        NSWorkspace.shared.open(result.url)
        status = .waitingForAuth
    }

    private func log(_ message: String) {
        DebugLog.write(message)
    }

    private var previewBreakdown: String {
        let totals = Dictionary(grouping: balancePreviews.values, by: \.currency)
            .mapValues { snapshots in
                snapshots.reduce(Decimal.zero) { $0 + $1.amount }
            }
        return totals
            .sorted { $0.key < $1.key }
            .map { $0.value.formattedCurrencyBreakdown(code: $0.key) }
            .joined(separator: ", ")
    }

    private func handleAuthCode(_ code: String) async {
        do {
            log("Exchanging code: \(code.prefix(30))...")
            let tokenPair = try await TrueLayerService.shared.exchangeCode(code)
            self.accessToken = tokenPair.accessToken
            log("Got access token: \(tokenPair.accessToken.prefix(20))...")

            // Store refresh token on this specific account
            guard let refresh = tokenPair.refreshToken else {
                self.error = "TrueLayer did not return a refresh token. Check that offline_access is enabled for this client."
                status = .ready
                return
            }
            account.trueLayerRefreshToken = refresh

            let allBankAccounts = try await TrueLayerService.shared.listAccounts(accessToken: tokenPair.accessToken)
            log("Returned \(allBankAccounts.count) accounts:")
            for ba in allBankAccounts {
                log("  - id=\(ba.accountId.prefix(16))... providerId=\(ba.provider?.providerId ?? "nil") provider=\(ba.provider?.displayName ?? "nil") type=\(ba.accountType ?? "nil") name=\(ba.displayName ?? "nil")")
            }

            // Filter out accounts from providers already connected
            let excluded = alreadyConnectedProviders
            log("Already connected providers: \(excluded)")
            bankAccounts = allBankAccounts.filter { ba in
                let keys = providerKeys(for: ba)
                guard !keys.isEmpty else { return true }
                return excluded.isDisjoint(with: keys)
            }
            log("After filtering: \(bankAccounts.count) accounts")

            if bankAccounts.isEmpty {
                error = "No new accounts found. All banks are already connected."
                status = .ready
            } else if bankAccounts.count == 1 {
                selectAccount(bankAccounts[0])
            } else {
                status = .selectingAccount
                // Fetch balance previews in background
                for ba in bankAccounts {
                    Task {
                        if let balance = try? await TrueLayerService.shared.fetchBalanceSnapshot(
                            accountId: ba.accountId, accessToken: tokenPair.accessToken
                        ) {
                            balancePreviews[ba.accountId] = balance
                        }
                    }
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func connectAllAccounts() {
        let allIds = bankAccounts.map { $0.accountId }.joined(separator: ",")
        account.trueLayerAccountId = allIds
        account.trueLayerProvider = bankAccounts.first.flatMap(providerStorageValue)
        status = .connected

        Task {
            guard let token = accessToken else { return }
            await BankSyncService.sync(account: account, accessToken: token, knownAccounts: bankAccounts)
        }
    }

    private func selectAccount(_ bankAccount: TrueLayerService.BankAccount) {
        account.trueLayerAccountId = bankAccount.accountId
        account.trueLayerProvider = providerStorageValue(for: bankAccount)
        status = .connected

        Task {
            guard let token = accessToken else { return }
            await BankSyncService.sync(account: account, accessToken: token, knownAccounts: [bankAccount])
        }
    }
}
