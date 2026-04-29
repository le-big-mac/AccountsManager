import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var fmpApiKey: String = KeychainHelper.load(.fmpApiKey) ?? ""
    @State private var tlClientId: String = KeychainHelper.load(.trueLayerClientId) ?? ""
    @State private var tlClientSecret: String = KeychainHelper.load(.trueLayerClientSecret) ?? ""
    @State private var snapTradeClientId: String = KeychainHelper.load(.snapTradeClientId) ?? ""
    @State private var snapTradeConsumerKey: String = KeychainHelper.load(.snapTradeConsumerKey) ?? ""

    var body: some View {
        Form {
            Section("FMP (Financial Modeling Prep)") {
                SecureField("API Key", text: $fmpApiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Get a free key at financialmodelingprep.com (250 requests/day)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("TrueLayer (Open Banking)") {
                TextField("Client ID", text: $tlClientId)
                    .textFieldStyle(.roundedBorder)
                SecureField("Client Secret", text: $tlClientSecret)
                    .textFieldStyle(.roundedBorder)
                Text("Sign up free at console.truelayer.com — supports Santander UK & Revolut")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("SnapTrade") {
                TextField("Client ID", text: $snapTradeClientId)
                    .textFieldStyle(.roundedBorder)
                SecureField("Consumer Key", text: $snapTradeConsumerKey)
                    .textFieldStyle(.roundedBorder)
                Text("Used to connect supported brokerages through SnapTrade's read-only Connection Portal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 500)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveCredentials()
                    dismiss()
                }
            }
        }
    }

    private func saveCredentials() {
        if !fmpApiKey.isEmpty {
            KeychainHelper.save(fmpApiKey, for: .fmpApiKey)
        }
        if !tlClientId.isEmpty {
            KeychainHelper.save(tlClientId, for: .trueLayerClientId)
        }
        if !tlClientSecret.isEmpty {
            KeychainHelper.save(tlClientSecret, for: .trueLayerClientSecret)
        }
        if !snapTradeClientId.isEmpty {
            KeychainHelper.save(snapTradeClientId, for: .snapTradeClientId)
        }
        if !snapTradeConsumerKey.isEmpty {
            KeychainHelper.save(snapTradeConsumerKey, for: .snapTradeConsumerKey)
        }
    }
}
