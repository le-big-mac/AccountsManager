import AppKit
import SwiftUI

struct SnapTradeConnectionView: View {
    @Bindable var account: Account
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var isWorking = false
    @State private var status = "Connect Robinhood in SnapTrade, then return here."
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("SnapTrade Robinhood Sync", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)

            Text(status)
                .foregroundStyle(.secondary)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("I Finished Connecting") {
                    Task { await importRobinhoodAccount() }
                }
                .disabled(isWorking)

                Button("Open Connection Portal") {
                    Task { await openPortal() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
            }
        }
        .padding()
        .frame(width: 460, height: 220)
        .onChange(of: appState.snapTradeCallbackReceived) { _, received in
            guard received else { return }
            appState.snapTradeCallbackReceived = false
            Task { await importRobinhoodAccount() }
        }
    }

    private func openPortal() async {
        isWorking = true
        error = nil
        defer { isWorking = false }

        do {
            let url = try await SnapTradeService.shared.connectionPortalURL()
            NSWorkspace.shared.open(url)
            status = "Finish the Robinhood connection in your browser. The app will sync when SnapTrade redirects back."
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func importRobinhoodAccount() async {
        isWorking = true
        error = nil
        defer { isWorking = false }

        do {
            let accounts = try await SnapTradeService.shared.listAccounts()
            let robinhoodAccounts = accounts.filter {
                ($0.institutionName ?? "").localizedCaseInsensitiveContains("Robinhood")
            }
            guard let snapAccount = robinhoodAccounts.first ?? accounts.first else {
                throw SnapTradeError.api("No SnapTrade brokerage accounts were found yet.")
            }

            account.investmentSourceType = .snapTrade
            account.snapTradeAccountId = snapAccount.id
            account.snapTradeAuthorizationId = snapAccount.brokerageAuthorization
            account.snapTradeInstitutionName = snapAccount.institutionName
            if account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let name = snapAccount.name {
                account.name = name
            }

            try await SnapTradeImportService.sync(account: account)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            status = "SnapTrade may still be finishing the initial sync. Wait a few seconds, then try again."
        }
    }
}
