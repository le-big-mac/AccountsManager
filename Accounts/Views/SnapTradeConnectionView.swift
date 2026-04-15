import AppKit
import SwiftUI

struct SnapTradeConnectionView: View {
    @Bindable var account: Account
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var isWorking = false
    @State private var status = "Connect a brokerage in SnapTrade, then return here."
    @State private var error: String?
    @State private var availableAccounts: [SnapTradeAccount] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("SnapTrade Sync", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)

            Text(status)
                .foregroundStyle(.secondary)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !availableAccounts.isEmpty {
                Text("Choose an account to import")
                    .font(.subheadline.weight(.semibold))

                List(availableAccounts, id: \.id) { snapAccount in
                    Button {
                        Task { await connectSelectedAccount(snapAccount) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapAccount.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Unnamed account")
                            if let institution = snapAccount.institutionName?.nonEmpty {
                                Text(institution)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                }
                .frame(height: 180)
            } else {
                Spacer()
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("I Finished Connecting") {
                    Task { await loadConnectedAccounts() }
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
        .frame(width: 460, height: availableAccounts.isEmpty ? 220 : 380)
        .onChange(of: appState.snapTradeCallbackReceived) { _, received in
            guard received else { return }
            appState.snapTradeCallbackReceived = false
            Task { await loadConnectedAccounts() }
        }
    }

    private func openPortal() async {
        isWorking = true
        error = nil
        defer { isWorking = false }

        do {
            let url = try await SnapTradeService.shared.connectionPortalURL()
            NSWorkspace.shared.open(url)
            status = "Finish connecting your brokerage in the browser. The app will import once SnapTrade redirects back."
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadConnectedAccounts() async {
        isWorking = true
        error = nil
        defer { isWorking = false }

        do {
            let accounts = try await SnapTradeService.shared.listAccounts()
            guard !accounts.isEmpty else {
                throw SnapTradeError.api("No SnapTrade brokerage accounts were found yet.")
            }

            if accounts.count == 1, let snapAccount = accounts.first {
                await connectSelectedAccount(snapAccount)
                return
            }

            availableAccounts = accounts.sorted { lhs, rhs in
                let lhsInstitution = lhs.institutionName?.localizedLowercase ?? ""
                let rhsInstitution = rhs.institutionName?.localizedLowercase ?? ""
                if lhsInstitution != rhsInstitution {
                    return lhsInstitution < rhsInstitution
                }
                let lhsName = lhs.name?.localizedLowercase ?? ""
                let rhsName = rhs.name?.localizedLowercase ?? ""
                return lhsName < rhsName
            }
            status = "Select which connected brokerage account to import."
        } catch {
            self.error = error.localizedDescription
            status = "SnapTrade may still be finishing the initial sync. Wait a few seconds, then try again."
        }
    }

    private func connectSelectedAccount(_ snapAccount: SnapTradeAccount) async {
        isWorking = true
        error = nil
        defer { isWorking = false }

        do {
            account.investmentSourceType = .snapTrade
            account.snapTradeAccountId = snapAccount.id
            account.snapTradeAuthorizationId = snapAccount.brokerageAuthorization
            account.snapTradeInstitutionName = snapAccount.institutionName
            if account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let name = snapAccount.name?.nonEmpty {
                account.name = name
            }

            try await SnapTradeImportService.sync(account: account)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
