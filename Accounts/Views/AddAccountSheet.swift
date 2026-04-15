import SwiftUI
import SwiftData

struct AddAccountSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder)
    private var existingAccounts: [Account]

    var onAccountCreated: (Account) -> Void = { _ in }

    @State private var name = ""
    @State private var accountType: AccountType = .investment
    @State private var investmentSource: InvestmentSourceType = .csvFile
    @State private var pendingAccount: Account?
    @State private var showingBankConnection = false

    var body: some View {
        VStack(spacing: 16) {
            Form {
                TextField("Account Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                Picker("Type", selection: $accountType) {
                    ForEach(AccountType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                if accountType == .investment {
                    Picker("Source", selection: $investmentSource) {
                        Text(InvestmentSourceType.csvFile.displayName).tag(InvestmentSourceType.csvFile)
                        Text(InvestmentSourceType.snapTrade.displayName).tag(InvestmentSourceType.snapTrade)
                    }
                }

                Text(accountType.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }

                Spacer()

                Button(accountType == .bankAccount ? "Add & Connect" : "Add") {
                    addAccount()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(width: 350, height: 270)
        .sheet(isPresented: $showingBankConnection, onDismiss: {
            if let account = pendingAccount, account.trueLayerAccountId != nil {
                // Connection succeeded -- insert the account
                modelContext.insert(account)
                onAccountCreated(account)
            }
            dismiss()
        }) {
            if let account = pendingAccount {
                BankConnectionView(account: account)
            }
        }
    }

    private func addAccount() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = Account(name: trimmedName, accountType: accountType, sortOrder: nextSortOrder)
        if accountType == .bankAccount {
            // Don't insert yet -- wait for successful connection
            pendingAccount = account
            showingBankConnection = true
        } else {
            account.investmentSourceType = investmentSource
            modelContext.insert(account)
            onAccountCreated(account)
            dismiss()
        }
    }

    private var nextSortOrder: Int {
        (existingAccounts.map(\.sortOrder).max() ?? 0) + 10
    }
}
