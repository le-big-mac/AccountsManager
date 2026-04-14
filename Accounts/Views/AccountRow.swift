import SwiftUI
import SwiftData

struct AccountRow: View {
    let account: Account

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: account.accountType.sfSymbol)
                .foregroundStyle(account.accountType.defaultColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.system(.body, weight: .medium))
                if let lastUpdated = account.lastUpdated {
                    Text(lastUpdated.relativeFormatted())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(account.currentBalance.formattedGBP())
                    .font(.system(.body, design: .rounded, weight: .semibold))

                Text(account.accountType == .bankAccount ? "sync" : "live")
                    .font(.caption2)
                    .foregroundStyle(account.accountType == .bankAccount ? .blue : .green)
            }
        }
        .padding(.vertical, 4)
    }
}
