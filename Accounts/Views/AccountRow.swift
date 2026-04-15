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
                    .lineLimit(1)
                if let lastUpdated = account.lastUpdated {
                    Text(lastUpdated.relativeFormatted())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(account.currentBalance.formattedGBP())
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .lineLimit(1)

                if let breakdown = account.originalCurrencyBreakdownText {
                    Text(breakdown)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
