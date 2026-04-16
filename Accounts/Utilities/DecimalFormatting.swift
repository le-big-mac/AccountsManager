import Foundation

extension Decimal {
    func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }

    func roundedForPercentDisplay(fractionDigits: Int = 1) -> Decimal {
        let roundedValue = rounded(scale: fractionDigits + 2)
        return roundedValue == 0 ? 0 : roundedValue
    }

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

    func formattedCurrencyBreakdown(code: String) -> String {
        let normalizedCode = code.uppercased()
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_GB")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2

        let number = formatter.string(from: self as NSDecimalNumber) ?? "\(self)"
        switch normalizedCode {
        case "GBP":
            return "GB£\(number)"
        case "USD":
            return "US$\(number)"
        default:
            return "\(normalizedCode) \(number)"
        }
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
        let displayValue = roundedForPercentDisplay()
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        return formatter.string(from: displayValue as NSDecimalNumber) ?? "0.0%"
    }
}

extension Date {
    func relativeFormatted() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
