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
    @State private var linkedResources: [TrueLayerService.LinkedResource] = []
    @State private var balancePreviews: [String: TrueLayerService.BalanceSnapshot] = [:]
    @State private var accessToken: String?
    @State private var expectedState: String?

    private var alreadyConnectedResourceIds: Set<String> {
        var resourceIds = Set<String>()
        for a in allAccounts where a.id != account.id {
            if let ids = a.trueLayerAccountId {
                for id in ids.split(separator: ",").map(String.init) {
                    resourceIds.insert(id)
                }
            }
        }
        return resourceIds
    }

    private func providerStorageValue(for resource: TrueLayerService.LinkedResource) -> String? {
        resource.provider?.providerId ?? resource.provider?.displayName
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

            Text("Connect via Open Banking")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("You'll be redirected to select your provider and log in. Bank accounts and supported credit cards can be connected.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button("Connect Account or Card") {
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
            Text("\(linkedResources.count) accounts and cards found")
                .font(.headline)

            // Connect all button
            if canConnectAllResources {
                Button {
                    connectAllResources()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connect all \(resourceTypeLabelPlural)")
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
            }

            Divider()

            Text(canConnectAllResources ? "Or select one:" : "Select one:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(linkedResources) { resource in
                        Button {
                            selectResource(resource)
                        } label: {
                            HStack {
                                Image(systemName: resource.resourceType == .card ? "creditcard.fill" : "building.columns.fill")
                                    .foregroundStyle(resource.resourceType == .card ? .red : .blue)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(resource.label)
                                        .foregroundStyle(.primary)
                                        .font(.subheadline)
                                    Text(resource.resourceType.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let balance = balancePreviews[resource.resourceId] {
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
            let tokenPair = try await TrueLayerService.shared.exchangeCode(code)
            self.accessToken = tokenPair.accessToken

            // Store refresh token on this specific account
            guard let refresh = tokenPair.refreshToken else {
                self.error = "TrueLayer did not return a refresh token. Check that offline_access is enabled for this client."
                status = .ready
                return
            }
            account.trueLayerRefreshToken = refresh

            let allResources = try await TrueLayerService.shared.listLinkedResources(accessToken: tokenPair.accessToken)
            log("Returned \(allResources.count) TrueLayer resources:")
            for resource in allResources {
                log("  - id=\(resource.resourceId.prefix(16))... type=\(resource.resourceType.rawValue) providerId=\(resource.provider?.providerId ?? "nil") provider=\(resource.provider?.displayName ?? "nil") name=\(resource.label)")
            }

            let excluded = alreadyConnectedResourceIds
            log("Already connected resource IDs: \(excluded)")
            linkedResources = allResources.filter { resource in
                !excluded.contains(resource.resourceId)
            }
            log("After filtering: \(linkedResources.count) resources")

            if linkedResources.isEmpty {
                error = "No new accounts or cards found. Everything returned by TrueLayer is already connected."
                status = .ready
            } else if linkedResources.count == 1 {
                selectResource(linkedResources[0])
            } else {
                status = .selectingAccount
                // Fetch balance previews in background
                for resource in linkedResources {
                    Task {
                        let balance: TrueLayerService.BalanceSnapshot?
                        switch resource.resourceType {
                        case .account:
                            balance = try? await TrueLayerService.shared.fetchBalanceSnapshot(
                                accountId: resource.resourceId,
                                accessToken: tokenPair.accessToken
                            )
                        case .card:
                            balance = try? await TrueLayerService.shared.fetchCardBalanceSnapshot(
                                cardId: resource.resourceId,
                                accessToken: tokenPair.accessToken
                            )
                        }
                        if let balance { balancePreviews[resource.resourceId] = balance }
                    }
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var canConnectAllResources: Bool {
        guard let first = linkedResources.first?.resourceType else { return false }
        return linkedResources.allSatisfy { $0.resourceType == first }
    }

    private var resourceTypeLabelPlural: String {
        switch linkedResources.first?.resourceType {
        case .account: "accounts"
        case .card: "cards"
        case nil: "resources"
        }
    }

    private func connectAllResources() {
        let allIds = linkedResources.map { $0.resourceId }.joined(separator: ",")
        account.trueLayerAccountId = allIds
        account.trueLayerResourceType = linkedResources.first?.resourceType ?? .account
        account.trueLayerProvider = linkedResources.first.flatMap(providerStorageValue)
        status = .connected

        Task {
            guard let token = accessToken else { return }
            await BankSyncService.sync(account: account, accessToken: token, knownResources: linkedResources)
        }
    }

    private func selectResource(_ resource: TrueLayerService.LinkedResource) {
        account.trueLayerAccountId = resource.resourceId
        account.trueLayerResourceType = resource.resourceType
        account.trueLayerProvider = providerStorageValue(for: resource)
        status = .connected

        Task {
            guard let token = accessToken else { return }
            await BankSyncService.sync(account: account, accessToken: token, knownResources: [resource])
        }
    }
}
