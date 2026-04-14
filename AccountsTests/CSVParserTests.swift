import XCTest
@testable import Accounts

final class CSVParserTests: XCTestCase {

    let parser = CSVParser()

    func testParseVanguardCSV() throws {
        let csv = """
        Account Number,Trade Date,Process Date,Transaction Type,Transaction Description,Investment Name,Share Price,Shares,Gross Amount,Net Amount
        12345,01/01/2026,02/01/2026,Buy,Purchase,Vanguard FTSE Global All Cap Index Fund,1.50,100,150.00,150.00
        12345,15/01/2026,16/01/2026,Buy,Purchase,Vanguard FTSE All-World UCITS ETF,82.00,10,820.00,820.00
        """

        let url = writeTempCSV(csv)
        let result = try parser.parse(url: url)

        XCTAssertEqual(result.detectedFormat, .vanguardUK)
        XCTAssertEqual(result.holdings.count, 2)

        let allCap = result.holdings.first { $0.name.contains("All Cap") }
        XCTAssertNotNil(allCap)
        XCTAssertEqual(allCap?.units, 100)
    }

    func testParseEmptyCSV() {
        let url = writeTempCSV("")
        XCTAssertThrowsError(try parser.parse(url: url))
    }

    func testCSVRowParsingWithQuotes() throws {
        let csv = """
        Name,Description,Amount
        "Smith, John","A ""quoted"" value",100.50
        """

        let url = writeTempCSV(csv)
        let result = try parser.parse(url: url)

        XCTAssertEqual(result.headers.count, 3)
        XCTAssertEqual(result.rows.first?[0], "Smith, John")
    }

    // MARK: - Helpers

    private func writeTempCSV(_ content: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("csv")
        try! content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
