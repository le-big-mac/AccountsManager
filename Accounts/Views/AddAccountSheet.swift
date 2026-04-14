import SwiftUI
import SwiftData

struct AddAccountSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var accountType: AccountType = .investment
    @State private var pendingAccount: Account?
    @State private var showingBankConnection = false

    var body: some View {
        Form {
            TextField("Account Name", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("Type", selection: $accountType) {
                ForEach(AccountType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }

            Text(accountType.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 200)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(accountType == .bankAccount ? "Add & Connect" : "Add") {
                    let account = Account(name: name, accountType: accountType)
                    if accountType == .bankAccount {
                        // Don't insert yet -- wait for successful connection
                        pendingAccount = account
                        showingBankConnection = true
                    } else {
                        modelContext.insert(account)
                        dismiss()
                    }
                }
                .disabled(name.isEmpty)
            }
        }
        .sheet(isPresented: $showingBankConnection, onDismiss: {
            if let account = pendingAccount, account.trueLayerAccountId != nil {
                // Connection succeeded -- insert the account
                modelContext.insert(account)
            }
            dismiss()
        }) {
            if let account = pendingAccount {
                BankConnectionView(account: account)
            }
        }
    }
}
