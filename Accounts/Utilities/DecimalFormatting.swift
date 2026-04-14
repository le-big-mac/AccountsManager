import Foundation

extension Decimal {
    func formattedCurrency(code: String, locale: Locale = Locale(identifier: "en_GB")) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code.uppercased()
        formatter.locale = locale
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: self as NSDecimalNumber) ?? "\(code.uppercased()) \(self)"
    }

    func formattedGBP() -> String {
        formattedCurrency(code: "GBP")
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

    func formattedPercent() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        return formatter.string(from: self as NSDecimalNumber) ?? "0.0%"
    }
}

extension Date {
    func relativeFormatted() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
