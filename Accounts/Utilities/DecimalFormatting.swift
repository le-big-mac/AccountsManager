import Foundation

extension Decimal {
    func formattedGBP() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "GBP"
        formatter.locale = Locale(identifier: "en_GB")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: self as NSDecimalNumber) ?? "£0.00"
    }

    func formattedCompact() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "GBP"
        formatter.locale = Locale(identifier: "en_GB")
        if self >= 1_000_000 {
            formatter.maximumFractionDigits = 1
            let millions = self / 1_000_000
            return formatter.string(from: millions as NSDecimalNumber)
                .map { "\($0)M" } ?? "£0"
        } else if self >= 10_000 {
            formatter.maximumFractionDigits = 0
        }
        return formatter.string(from: self as NSDecimalNumber) ?? "£0.00"
    }
}

extension Date {
    func relativeFormatted() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
