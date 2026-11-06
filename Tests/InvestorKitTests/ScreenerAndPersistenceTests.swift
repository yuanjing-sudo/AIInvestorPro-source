import XCTest
@testable import InvestorKit

final class ScreenerTests: XCTestCase {

    private let filter = ScreenFilter(
        minPrice: 20,
        minVolume: 1_000_000,
        maxRSI: 70,
        maxVolatility: 40,
        minPriceToSMA: 1.0
    )

    func testPassingCandidate() {
        let candidate = ScreenCandidate(
            symbol: "AAPL",
            price: 201,
            volume: 12_000_000,
            sector: "Technology",
            metrics: [
                "rsi": 58,
                "momentum": 8,
                "volatility": 22,
                "priceToSMA": 1.04,
                "volumeRatio": 1.3,
            ]
        )
        let result = ScreenerEngine.evaluate(candidate, filter: filter)
        XCTAssertTrue(result.passed)
        XCTAssertGreaterThan(result.score, 0)
    }

    func testFailingCandidateExplainsWhy() {
        let candidate = ScreenCandidate(
            symbol: "XYZ",
            price: 12,
            volume: 400_000,
            metrics: [
                "rsi": 82,
                "volatility": 65,
                "priceToSMA": 0.91,
            ]
        )
        let result = ScreenerEngine.evaluate(candidate, filter: filter)
        XCTAssertFalse(result.passed)
        XCTAssertGreaterThanOrEqual(result.failures.count, 4)
    }

    func testMissingMetricFailsWhenFilterRequiresIt() {
        let candidate = ScreenCandidate(symbol: "ABC", price: 100, volume: 2_000_000)
        let result = ScreenerEngine.evaluate(candidate, filter: filter)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.failures.contains { $0.contains("RSI") })
    }

    func testMissingPEWithPEFilterFails() {
        let candidate = ScreenCandidate(symbol: "NOPE", price: 50)
        let result = ScreenerEngine.evaluate(candidate, filter: ScreenFilter(maxPE: 20))
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.failures.contains { $0.contains("P/E") })
    }

    func testResultsAreSortedAndLimited() {
        let candidates = (0..<5).map { index in
            ScreenCandidate(
                symbol: "S\(index)",
                price: 100,
                volume: 2_000_000,
                metrics: ["momentum": Double(index * 5)]
            )
        }
        var rankedFilter = ScreenFilter(minPrice: 1)
        rankedFilter.maxResults = 3
        let results = ScreenerEngine.run(candidates: candidates, filter: rankedFilter)
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].candidate.symbol, "S4")
    }
}

final class PersistenceAndExportTests: XCTestCase {

    func testPortfolioStoreRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("portfolio.json")
        let store = PortfolioStore(fileURL: url)

        var portfolio = StoredPortfolio(name: "Test", cash: 10_000)
        try portfolio.apply(StoredTransaction(
            symbol: "AAPL",
            side: .long,
            quantity: 10,
            price: 150,
            fees: 1
        ))
        XCTAssertEqual(portfolio.cash, 8_499, accuracy: 1e-9)
        XCTAssertEqual(portfolio.holdings.first?.averageCost ?? 0, 150, accuracy: 1e-9)

        try await store.save(portfolio)
        let loaded = try await store.load()
        XCTAssertEqual(loaded?.name, "Test")
        XCTAssertEqual(loaded?.cash ?? 0, 8_499, accuracy: 1e-9)
        XCTAssertEqual(loaded?.holdings.count, 1)

        let exists = await store.exists()
        XCTAssertTrue(exists)
        try await store.delete()
        let existsAfterDelete = await store.exists()
        XCTAssertFalse(existsAfterDelete)
    }

    func testWeightedAverageCostUpdate() throws {
        var portfolio = StoredPortfolio(name: "Test", cash: 100_000)
        try portfolio.apply(StoredTransaction(symbol: "MSFT", side: .long, quantity: 10, price: 100))
        try portfolio.apply(StoredTransaction(symbol: "MSFT", side: .long, quantity: 10, price: 200))
        XCTAssertEqual(portfolio.holdings.first?.quantity ?? 0, 20, accuracy: 1e-9)
        XCTAssertEqual(portfolio.holdings.first?.averageCost ?? 0, 150, accuracy: 1e-9)

        try portfolio.apply(StoredTransaction(symbol: "MSFT", side: .short, quantity: 20, price: 250))
        XCTAssertTrue(portfolio.holdings.isEmpty)
    }

    func testSellingMoreThanOwnedThrows() throws {
        var portfolio = StoredPortfolio(name: "Test", cash: 100_000)
        try portfolio.apply(StoredTransaction(symbol: "NVDA", side: .long, quantity: 5, price: 100))
        XCTAssertThrowsError(try portfolio.apply(
            StoredTransaction(symbol: "NVDA", side: .short, quantity: 6, price: 110)
        ))
    }

    func testCSVEscaping() {
        let csv = CSV.encode(
            headers: ["a", "b"],
            rows: [["hello, world", "say \"hi\""]]
        )
        XCTAssertEqual(csv, "a,b\n\"hello, world\",\"say \"\"hi\"\"\"\n")
    }

    func testMarkdownAndJSONExport() throws {
        let report = PerformanceAnalytics.analyze(equity: [100, 105, 102, 110])!
        let markdown = ReportExporter.markdown(report: report, title: "Test Report")
        XCTAssertTrue(markdown.contains("# Test Report"))
        XCTAssertTrue(markdown.contains("Total return"))

        let fill = TradeFill(
            date: Date(timeIntervalSince1970: 0),
            symbol: "AAPL",
            side: .long,
            quantity: 1,
            price: 100,
            notional: 100,
            commission: 0.1,
            slippageCost: 0,
            targetExposure: 1,
            cashAfter: 0
        )
        let csv = ReportExporter.tradesCSV([fill])
        XCTAssertTrue(csv.hasPrefix("date,symbol,side"))
        XCTAssertTrue(csv.contains("AAPL"))
    }

    func testWritingToDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("report.md")
        try ReportExporter.write("# Hello", to: url)
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(contents, "# Hello")
    }
}
