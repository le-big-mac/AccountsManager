import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CSVImportView: View {
    let account: Account
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var parsedCSV: CSVParser.ParsedCSV?
    @State private var parsedURL: URL?
    @State private var error: String?
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 16) {
            if let parsed = parsedCSV {
                importPreview(parsed)
            } else {
                dropZone
            }
        }
        .frame(width: 500, height: 400)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 40))
                .foregroundStyle(isDragging ? .blue : .secondary)

            Text("Drop CSV file here")
                .font(.headline)

            Text("or")
                .foregroundStyle(.secondary)

            Button("Choose File...") {
                openFilePicker()
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isDragging ? Color.blue : Color.secondary.opacity(0.3),
                              style: StrokeStyle(lineWidth: 2, dash: [8]))
                .padding()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            handleDrop(providers)
            return true
        }
    }

    private func importPreview(_ parsed: CSVParser.ParsedCSV) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Detected: \(parsed.detectedFormat.description)",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Text("\(parsed.holdings.count) holdings, \(parsed.cashBalances.count) cash lines")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(parsed.holdings.indices, id: \.self) { i in
                        let h = parsed.holdings[i]
                        HStack {
                            VStack(alignment: .leading) {
                                Text(h.name)
                                    .font(.subheadline)
                                if let ticker = h.ticker {
                                    Text("\(ticker) · \(h.priceCurrency)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(h.units as NSDecimalNumber) units")
                                .font(.subheadline.monospacedDigit())
                        }
                        Divider()
                    }
                    ForEach(parsed.cashBalances.indices, id: \.self) { i in
                        let cash = parsed.cashBalances[i]
                        HStack {
                            VStack(alignment: .leading) {
                                Text(cash.name)
                                    .font(.subheadline)
                                Text(cash.currency)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(cash.amount.formattedCurrency(code: cash.currency))
                                .font(.subheadline.monospacedDigit())
                        }
                        Divider()
                    }
                }
            }

            HStack {
                Spacer()
                Button("Import") {
                    if let parsedURL {
                        do {
                            _ = try PortfolioImportService.importCSV(at: parsedURL, into: account)
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            parseFile(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                parseFile(url)
            }
        }
    }

    private func parseFile(_ url: URL) {
        do {
            let parser = CSVParser()
            parsedCSV = try parser.parse(url: url)
            parsedURL = url
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct CSVImportPickerView: View {
    @Query(filter: #Predicate<Account> { !$0.isArchived })
    private var accounts: [Account]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAccount: Account?

    var investmentAccounts: [Account] {
        accounts.filter { $0.accountType == .investment }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Select an account to import into")
                .font(.headline)

            Picker("Account", selection: $selectedAccount) {
                Text("Select...").tag(nil as Account?)
                ForEach(investmentAccounts) { account in
                    Text(account.name).tag(account as Account?)
                }
            }
            .frame(width: 300)

            if let account = selectedAccount {
                CSVImportView(account: account)
            }
        }
        .frame(width: 500, height: 450)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
