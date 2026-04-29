import Foundation
import SwiftData

enum HoldingAssetClass: String, CaseIterable, Identifiable {
    case cash
    case stock
    case etf
    case fund
    case gilt
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cash: "Cash"
        case .stock: "Securities"
        case .etf: "ETFs"
        case .fund: "Funds"
        case .gilt: "Gilts"
        case .other: "Other"
        }
    }

    static func from(_ value: String?) -> HoldingAssetClass? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        switch normalized {
        case "cash":
            return .cash
        case "stock", "stocks", "share", "shares", "equity", "equities", "security", "securities":
            return .stock
        case "etf", "etfs", "exchangetradedfund":
            return .etf
        case "fund", "funds", "mutualfund", "oeic", "unittrust":
            return .fund
        case "gilt", "gilts", "ukgilt", "ukgilts", "treasurygilt", "treasurygilts":
            return .gilt
        default:
            return nil
        }
    }
}

enum AnalystConsensusRating: String {
    case strongBuy = "Strong Buy"
    case buy = "Buy"
    case hold = "Hold"
    case sell = "Sell"
    case strongSell = "Strong Sell"

    static func from(_ value: String?) -> AnalystConsensusRating? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter }

        switch normalized {
        case "strongbuy":
            return .strongBuy
        case "buy":
            return .buy
        case "hold":
            return .hold
        case "sell":
            return .sell
        case "strongsell":
            return .strongSell
        default:
            return nil
        }
    }
}

@Model
final class Holding {
    var id: UUID
    var name: String
    var ticker: String?
    var isin: String?
    var sedol: String?
    var units: Decimal
    var lastPrice: Decimal?
    var averagePurchasePrice: Decimal?
    var priceCurrencyRaw: String = ""
    var assetClassRaw: String?
    var fxRateToGBP: Decimal?
    var fxRateDate: Date?
    var lastPriceDate: Date?
    var analystConsensusTarget: Decimal?
    var analystTargetLow: Decimal?
    var analystTargetHigh: Decimal?
    var analystTargetCurrencyRaw: String = ""
    var analystTargetUpdatedAt: Date?
    var giltCouponRate: Decimal?
    var giltMaturityDate: Date?
    var giltSettlementDate: Date?
    var giltCleanPricePaid: Decimal?
    var giltDirtyPricePaid: Decimal?
    var giltCouponDatesRaw: String?
    var securityMetadata: SecurityMetadata?
    var account: Account?

    var currentValue: Decimal {
        currentValueGBP
    }

    var localCurrentValue: Decimal {
        guard let price = lastPrice else { return 0 }
        if assetClass == .gilt {
            return units * price / 100
        }
        return units * price
    }

    var currentValueGBP: Decimal {
        localCurrentValue * effectiveFXRateToGBP
    }

    var priceCurrency: String {
        get {
            let stored = normalizedCurrency(priceCurrencyRaw)
            return stored.isEmpty ? inferredPriceCurrency : stored
        }
        set { priceCurrencyRaw = normalizedCurrency(newValue) }
    }

    var assetClass: HoldingAssetClass {
        get { HoldingAssetClass(rawValue: assetClassRaw ?? "") ?? inferredAssetClass }
        set { assetClassRaw = newValue.rawValue }
    }

    var effectiveFXRateToGBP: Decimal {
        switch priceCurrency {
        case "GBP":
            return 1
        case "GBX":
            return Decimal(string: "0.01") ?? 0.01
        default:
            return fxRateToGBP ?? 0
        }
    }

    var priceIdentifier: String? {
        ticker ?? isin ?? sedol
    }

    var securityMetadataKey: String {
        if let ticker = normalizedIdentifier(ticker), !ticker.isEmpty {
            return "ticker:\(ticker)"
        }
        if let isin = normalizedIdentifier(isin), !isin.isEmpty {
            return "isin:\(isin)"
        }
        if let sedol = normalizedIdentifier(sedol), !sedol.isEmpty {
            return "sedol:\(sedol)"
        }
        return "name:\(normalizedIdentifier(name) ?? "")"
    }

    var resolvedAnalystConsensusTarget: Decimal? {
        securityMetadata?.analystConsensusTarget ?? analystConsensusTarget
    }

    var resolvedAnalystTargetLow: Decimal? {
        securityMetadata?.analystTargetLow ?? analystTargetLow
    }

    var resolvedAnalystTargetHigh: Decimal? {
        securityMetadata?.analystTargetHigh ?? analystTargetHigh
    }

    var resolvedAnalystTargetUpdatedAt: Date? {
        securityMetadata?.analystTargetUpdatedAt ?? analystTargetUpdatedAt
    }

    var resolvedAnalystConsensusRating: AnalystConsensusRating? {
        AnalystConsensusRating.from(securityMetadata?.analystConsensusRatingRaw)
    }

    var resolvedAnalystRatingCount: Int? {
        securityMetadata?.analystRatingCount
    }

    var resolvedAnalystRatingUpdatedAt: Date? {
        securityMetadata?.analystRatingUpdatedAt
    }

    var resolvedAnalystRatingError: String? {
        securityMetadata?.analystRatingError
    }

    var analystTargetCurrency: String {
        let metadataCurrency = securityMetadata?.analystTargetCurrency ?? ""
        if !metadataCurrency.isEmpty {
            return metadataCurrency
        }
        let stored = normalizedCurrency(analystTargetCurrencyRaw)
        return stored.isEmpty ? priceCurrency : stored
    }

    var analystConsensusUpsidePercent: Decimal? {
        guard let target = resolvedAnalystConsensusTarget,
              let price = lastPrice,
              price != 0,
              analystTargetCurrency == priceCurrency else {
            return nil
        }
        return (target - price) / price
    }

    var openPnLPercent: Decimal? {
        if assetClass == .gilt {
            return giltMetrics?.grossTotalReturn
        }

        guard let averagePurchasePrice,
              let price = lastPrice,
              averagePurchasePrice > 0 else {
            return nil
        }
        return (price - averagePurchasePrice) / averagePurchasePrice
    }

    var giltMetrics: GiltMetrics? {
        guard assetClass == .gilt,
              let couponRate = giltCouponRate,
              let maturityDate = giltMaturityDate,
              let settlementDate = giltSettlementDate,
              let dirtyPricePaid = giltDirtyPricePaid,
              couponRate >= 0,
              units > 0,
              dirtyPricePaid > 0 else {
            return nil
        }

        let couponDates = GiltCalculator.generateCouponDates(
            couponDateRules: giltCouponDateRules,
            maturityDate: maturityDate,
            settlementDate: settlementDate
        )

        return GiltCalculator.metrics(
            nominal: units,
            annualCouponRate: couponRate,
            settlementDate: settlementDate,
            maturityDate: maturityDate,
            couponDates: couponDates,
            dirtyPricePaid: dirtyPricePaid
        )
    }

    private var giltCouponDateRules: [GiltCouponDateRule] {
        GiltCouponDateRule.parse(giltCouponDatesRaw)
    }

    private var inferredPriceCurrency: String {
        guard let ticker else { return "GBP" }
        let uppercased = ticker.uppercased()
        if uppercased.hasSuffix(".L") || uppercased.hasSuffix(".LON") {
            return "GBP"
        }
        return "USD"
    }

    private var inferredAssetClass: HoldingAssetClass {
        let text = [name, ticker, isin, sedol]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if text.contains(" etf")
            || text.contains(" ucits")
            || text.contains("ishares")
            || text.contains("vanguard ftse")
            || text.contains("vanguard s&p")
            || text.contains("vanguard sp") {
            return .etf
        }

        if text.contains("fund")
            || text.contains("oeic")
            || text.contains("index")
            || text.contains("accumulation")
            || text.contains("income")
            || text.contains("acc ") {
            return .fund
        }

        return .stock
    }

    private func normalizedCurrency(_ currency: String) -> String {
        let trimmed = currency.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "GBp" || trimmed == "GBX" {
            return "GBX"
        }
        return trimmed.uppercased()
    }

    private func normalizedIdentifier(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    init(
        name: String,
        ticker: String? = nil,
        isin: String? = nil,
        sedol: String? = nil,
        units: Decimal,
        priceCurrency: String = "GBP",
        assetClass: HoldingAssetClass? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.ticker = ticker
        self.isin = isin
        self.sedol = sedol
        self.units = units
        self.priceCurrency = priceCurrency
        self.assetClassRaw = assetClass?.rawValue
    }
}

struct GiltMetrics {
    let grossHTMYield: Decimal
    let grossTotalReturn: Decimal
    let totalCashToMaturity: Decimal
    let nextCouponDate: Date?
}

struct GiltCouponDateRule {
    let month: Int
    let day: Int

    static func parse(_ rawValue: String?) -> [GiltCouponDateRule] {
        guard let rawValue, !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return rawValue
            .split(whereSeparator: { $0 == ";" || $0 == "|" })
            .compactMap { component in
                parseComponent(String(component))
            }
            .sorted {
                if $0.month == $1.month {
                    return $0.day < $1.day
                }
                return $0.month < $1.month
            }
    }

    private static func parseComponent(_ component: String) -> GiltCouponDateRule? {
        let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("-") || trimmed.contains("/") {
            let parts = trimmed.split(whereSeparator: { $0 == "-" || $0 == "/" }).map(String.init)
            guard parts.count == 2 else { return nil }

            if let first = Int(parts[0]), let second = Int(parts[1]) {
                if first > 12 {
                    return GiltCouponDateRule(month: second, day: first)
                }
                return GiltCouponDateRule(month: first, day: second)
            }
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        for format in ["d MMM", "dd MMM", "d MMMM", "dd MMMM"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                let components = Calendar.gregorianUTC.dateComponents([.month, .day], from: date)
                if let month = components.month, let day = components.day {
                    return GiltCouponDateRule(month: month, day: day)
                }
            }
        }

        return nil
    }
}

enum GiltCalculator {
    static func generateCouponDates(
        couponDateRules: [GiltCouponDateRule],
        maturityDate: Date,
        settlementDate: Date
    ) -> [Date] {
        let calendar = Calendar.gregorianUTC
        let maturityYear = calendar.component(.year, from: maturityDate)
        let settlementYear = calendar.component(.year, from: settlementDate)
        let rules = couponDateRules.isEmpty
            ? [GiltCouponDateRule(month: calendar.component(.month, from: maturityDate), day: calendar.component(.day, from: maturityDate))]
            : couponDateRules

        var dates: [Date] = []
        for year in settlementYear...maturityYear {
            for rule in rules {
                guard let date = calendar.date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: year, month: rule.month, day: rule.day)),
                      date <= maturityDate,
                      settlementDate < exDividendDate(for: date) else {
                    continue
                }
                dates.append(date)
            }
        }

        if settlementDate < exDividendDate(for: maturityDate), !dates.contains(maturityDate) {
            dates.append(maturityDate)
        }

        return dates.sorted()
    }

    static func metrics(
        nominal: Decimal,
        annualCouponRate: Decimal,
        settlementDate: Date,
        maturityDate: Date,
        couponDates: [Date],
        dirtyPricePaid: Decimal
    ) -> GiltMetrics? {
        let dirtyCashOutlay = nominal * dirtyPricePaid / 100
        guard dirtyCashOutlay > 0 else { return nil }

        let couponCash = nominal * normalizedCouponRate(annualCouponRate) / 2
        let paymentDates = couponDates.filter { $0 > settlementDate && $0 <= maturityDate }

        var cashFlows = [-dirtyCashOutlay]
        var dates = [settlementDate]

        for date in paymentDates {
            let payment = calendarDay(date, equals: maturityDate) ? couponCash + nominal : couponCash
            cashFlows.append(payment)
            dates.append(date)
        }

        guard cashFlows.count > 1 else { return nil }

        let totalCashToMaturity = cashFlows.dropFirst().reduce(Decimal(0), +)
        let grossTotalReturn = (totalCashToMaturity - dirtyCashOutlay) / dirtyCashOutlay
        let grossHTMYield = xirr(cashFlows: cashFlows, dates: dates) ?? 0

        return GiltMetrics(
            grossHTMYield: grossHTMYield,
            grossTotalReturn: grossTotalReturn,
            totalCashToMaturity: totalCashToMaturity,
            nextCouponDate: paymentDates.first
        )
    }

    private static func normalizedCouponRate(_ couponRate: Decimal) -> Decimal {
        couponRate > 1 ? couponRate / 100 : couponRate
    }

    private static func exDividendDate(for paymentDate: Date) -> Date {
        var date = paymentDate
        var businessDays = 0

        while businessDays < 7 {
            date = Calendar.gregorianUTC.date(byAdding: .day, value: -1, to: date) ?? date
            if UKBankHolidayCalendar.isBusinessDay(date) {
                businessDays += 1
            }
        }

        return date
    }

    private static func calendarDay(_ lhs: Date, equals rhs: Date) -> Bool {
        Calendar.gregorianUTC.isDate(lhs, inSameDayAs: rhs)
    }

    private static func xirr(cashFlows: [Decimal], dates: [Date]) -> Decimal? {
        guard cashFlows.count == dates.count,
              cashFlows.contains(where: { $0 < 0 }),
              cashFlows.contains(where: { $0 > 0 }) else {
            return nil
        }

        var low = Decimal(string: "-0.9999") ?? -0.9999
        var high = Decimal(10)
        var lowNPV = npv(rate: low, cashFlows: cashFlows, dates: dates)
        let highNPV = npv(rate: high, cashFlows: cashFlows, dates: dates)
        guard lowNPV * highNPV <= 0 else { return nil }

        for _ in 0..<120 {
            let mid = (low + high) / 2
            let midNPV = npv(rate: mid, cashFlows: cashFlows, dates: dates)

            if abs(midNPV.doubleValue) < 0.0000001 {
                return mid
            }

            if lowNPV * midNPV > 0 {
                low = mid
                lowNPV = midNPV
            } else {
                high = mid
            }
        }

        return (low + high) / 2
    }

    private static func npv(rate: Decimal, cashFlows: [Decimal], dates: [Date]) -> Decimal {
        let start = dates[0]
        var total = Decimal(0)

        for (cashFlow, date) in zip(cashFlows, dates) {
            let years = date.timeIntervalSince(start) / (365.25 * 24 * 60 * 60)
            let discount = pow(1 + rate.doubleValue, years)
            total += cashFlow / Decimal(discount)
        }

        return total
    }
}

enum UKBankHolidayCalendar {
    static func isBusinessDay(_ date: Date) -> Bool {
        let calendar = Calendar.gregorianUTC
        let weekday = calendar.component(.weekday, from: date)
        guard weekday != 1 && weekday != 7 else { return false }
        return !bankHolidays(for: calendar.component(.year, from: date)).contains(startOfDay(date))
    }

    private static func bankHolidays(for year: Int) -> Set<Date> {
        var holidays = Set<Date>()

        holidays.insert(observedFixedHoliday(year: year, month: 1, day: 1))

        let easter = easterSunday(year: year)
        holidays.insert(Calendar.gregorianUTC.date(byAdding: .day, value: -2, to: easter)!)
        holidays.insert(Calendar.gregorianUTC.date(byAdding: .day, value: 1, to: easter)!)

        holidays.insert(firstMonday(year: year, month: 5))
        holidays.insert(lastMonday(year: year, month: 5))
        holidays.insert(lastMonday(year: year, month: 8))

        let christmas = date(year: year, month: 12, day: 25)
        let boxingDay = date(year: year, month: 12, day: 26)
        let weekday = Calendar.gregorianUTC.component(.weekday, from: christmas)

        switch weekday {
        case 1:
            holidays.insert(date(year: year, month: 12, day: 26))
            holidays.insert(date(year: year, month: 12, day: 27))
        case 7:
            holidays.insert(date(year: year, month: 12, day: 27))
            holidays.insert(date(year: year, month: 12, day: 28))
        default:
            holidays.insert(christmas)
            if Calendar.gregorianUTC.component(.weekday, from: boxingDay) == 7 {
                holidays.insert(date(year: year, month: 12, day: 28))
            } else {
                holidays.insert(boxingDay)
            }
        }

        return holidays
    }

    private static func observedFixedHoliday(year: Int, month: Int, day: Int) -> Date {
        let holiday = date(year: year, month: month, day: day)
        switch Calendar.gregorianUTC.component(.weekday, from: holiday) {
        case 1:
            return Calendar.gregorianUTC.date(byAdding: .day, value: 1, to: holiday)!
        case 7:
            return Calendar.gregorianUTC.date(byAdding: .day, value: 2, to: holiday)!
        default:
            return holiday
        }
    }

    private static func firstMonday(year: Int, month: Int) -> Date {
        var date = self.date(year: year, month: month, day: 1)
        while Calendar.gregorianUTC.component(.weekday, from: date) != 2 {
            date = Calendar.gregorianUTC.date(byAdding: .day, value: 1, to: date)!
        }
        return date
    }

    private static func lastMonday(year: Int, month: Int) -> Date {
        var components = DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month + 1, day: 0)
        if month == 12 {
            components = DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: year + 1, month: 1, day: 0)
        }
        var date = Calendar.gregorianUTC.date(from: components)!
        while Calendar.gregorianUTC.component(.weekday, from: date) != 2 {
            date = Calendar.gregorianUTC.date(byAdding: .day, value: -1, to: date)!
        }
        return date
    }

    private static func easterSunday(year: Int) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return date(year: year, month: month, day: day)
    }

    private static func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.gregorianUTC.date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day))!
    }

    private static func startOfDay(_ date: Date) -> Date {
        Calendar.gregorianUTC.startOfDay(for: date)
    }
}

private extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

private extension Calendar {
    static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
