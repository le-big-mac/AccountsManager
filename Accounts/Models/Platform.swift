import SwiftUI

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case bankAccount
    case investment

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bankAccount: "Bank Account"
        case .investment: "Investment"
        }
    }

    var description: String {
        switch self {
        case .bankAccount: "Auto-syncs balance via Open Banking (TrueLayer)"
        case .investment: "Track holdings with live prices (CSV import or SnapTrade)"
        }
    }

    var sfSymbol: String {
        switch self {
        case .bankAccount: "building.columns.fill"
        case .investment: "chart.line.uptrend.xyaxis"
        }
    }

    var defaultColor: Color {
        switch self {
        case .bankAccount: .blue
        case .investment: .green
        }
    }
}

enum EntrySource: String, Codable {
    case manual
    case csvImport
    case bankSync
}
