import XCTest
@testable import InvestorKit

final class BacktestTests: XCTestCase {

    func testBuyAndHoldPerformance() {
        let prices = (0..<120).map { 100.0 + Double($0) }
        let candles = makeCandles(prices)
        let result = BacktestEngine().run(
            strategy: BuyAndHoldStrategy(),
            candles: candles,
            config: BacktestConfig(initialCash: 10_000, commissionBps: 0, slippageBps: 0)
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.equityCurve.count, candles.count)
        XCTAssertGreaterThan(result!.finalEquity, 10_000)
        XCTAssertNotNil(result!.report)
        XCTAssertGreaterThan(result!.report!.totalReturn, 0)
    }

    func testNextBarExecutionHasNoLookahead() {
        let prices = (0..<60).map { 100.0 + Double($0) }
        let candles = makeCandles(prices)
        let result = BacktestEngine().run(
            strategy: SMACrossoverStrategy(fastPeriod: 5, slowPeriod: 20),
            candles: candles,
            config: BacktestConfig(initialCash: 10_000, commissionBps: 0, slippageBps: 0)
        )
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.fills.isEmpty)
        // The first signal is available on bar 19, so execution must happen on
        // bar 20's open — never on the signal bar itself.
        XCTAssertEqual(result!.fills.first!.date, candles[20].date)
    }

    func testInvalidInputReturnsNil() {
        XCTAssertNil(BacktestEngine().run(strategy: BuyAndHoldStrategy(), candles: []))
        let bad = [Candle(date: Date(), open: 0, high: 0, low: 0, close: 0, volume: 0)]
        XCTAssertNil(BacktestEngine().run(strategy: BuyAndHoldStrategy(), candles: bad))
    }

    private func makeCandles(_ prices: [Double]) -> [Candle] {
        let start = Date(timeIntervalSince1970: 1_600_000_000)
        return prices.enumerated().map { index, price in
            Candle(
                date: start.addingTimeInterval(Double(index) * 86_400),
                open: price,
                high: price * 1.01,
                low: price * 0.99,
                close: price,
                volume: 1_000_000
            )
        }
    }
}

final class TaxLotTests: XCTestCase {

    func testFIFOAndLIFO() throws {
        let day1 = Date(timeIntervalSince1970: 0)
        let day2 = day1.addingTimeInterval(86_400 * 400)
        let day3 = day2.addingTimeInterval(86_400 * 400)

        var fifo = TaxLotLedger()
        try fifo.buy(symbol: "AAPL", quantity: 100, price: 10, date: day1)
        try fifo.buy(symbol: "AAPL", quantity: 100, price: 20, date: day2)
        let fifoSale = try fifo.sell(symbol: "AAPL", quantity: 100, price: 30, date: day3, method: .fifo)
        XCTAssertEqual(fifoSale.gain, 2_000, accuracy: 1e-9)
        XCTAssertEqual(fifo.position(symbol: "AAPL")?.quantity ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(fifo.position(symbol: "AAPL")?.averageCost ?? 0, 20, accuracy: 1e-9)

        var lifo = TaxLotLedger()
        try lifo.buy(symbol: "AAPL", quantity: 100, price: 10, date: day1)
        try lifo.buy(symbol: "AAPL", quantity: 100, price: 20, date: day2)
        let lifoSale = try lifo.sell(symbol: "AAPL", quantity: 100, price: 30, date: day3, method: .lifo)
        XCTAssertEqual(lifoSale.gain, 1_000, accuracy: 1e-9)
        XCTAssertEqual(lifo.position(symbol: "AAPL")?.averageCost ?? 0, 10, accuracy: 1e-9)
        XCTAssertTrue(fifoSale.lots.first!.isLongTerm)
    }

    func testInsufficientQuantityThrows() throws {
        var ledger = TaxLotLedger()
        try ledger.buy(symbol: "MSFT", quantity: 10, price: 100, date: Date())
        XCTAssertThrowsError(try ledger.sell(symbol: "MSFT", quantity: 11, price: 110))
    }

    func testPartialLotConsumption() throws {
        var ledger = TaxLotLedger()
        try ledger.buy(symbol: "NVDA", quantity: 100, price: 50, date: Date(timeIntervalSince1970: 0))
        let sale = try ledger.sell(
            symbol: "NVDA",
            quantity: 40,
            price: 60,
            fees: 4,
            date: Date(timeIntervalSince1970: 86_400 * 30)
        )
        XCTAssertEqual(sale.gain, 396, accuracy: 1e-9)
        XCTAssertEqual(ledger.position(symbol: "NVDA")?.quantity ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(ledger.totalCostBasis(), 3_000, accuracy: 1e-9)
    }
}

final class AlertRuleEngineTests: XCTestCase {

    func testCrossAboveRequiresPreviousPrice() {
        var engine = AlertRuleEngine()
        engine.add(AlertRule(symbol: "AAPL", condition: .crossesAbove, threshold: 200, cooldown: 0))

        let first = engine.evaluate([Quote(symbol: "AAPL", price: 201)], at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(first.isEmpty, "A crossing cannot be detected without a previous price")

        let second = engine.evaluate([Quote(symbol: "AAPL", price: 199)], at: Date(timeIntervalSince1970: 1))
        XCTAssertTrue(second.isEmpty)

        let third = engine.evaluate([Quote(symbol: "AAPL", price: 200.5)], at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(third.count, 1)
        XCTAssertEqual(third[0].condition, .crossesAbove)
    }

    func testPriceAboveIsEdgeTriggered() {
        var engine = AlertRuleEngine()
        engine.add(AlertRule(symbol: "MSFT", condition: .priceAbove, threshold: 100, cooldown: 0))

        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(engine.evaluate([Quote(symbol: "MSFT", price: 101)], at: date).count, 1)
        XCTAssertEqual(engine.evaluate([Quote(symbol: "MSFT", price: 102)], at: date).count, 0)
        XCTAssertEqual(engine.evaluate([Quote(symbol: "MSFT", price: 99)], at: date).count, 0)
        XCTAssertEqual(engine.evaluate([Quote(symbol: "MSFT", price: 103)], at: date).count, 1)
    }

    func testOneShotDisablesRule() {
        var engine = AlertRuleEngine()
        engine.add(AlertRule(
            symbol: "TSLA",
            condition: .percentChangeAbove,
            threshold: 5,
            isOneShot: true,
            cooldown: 0
        ))
        let quote = Quote(symbol: "TSLA", price: 105, previousClose: 100)
        XCTAssertEqual(engine.evaluate([quote], at: Date()).count, 1)
        XCTAssertFalse(engine.rules[0].isEnabled)
        XCTAssertEqual(engine.evaluate([quote], at: Date()).count, 0)
    }

    func testCooldownSuppressesRepeat() {
        var engine = AlertRuleEngine()
        engine.add(AlertRule(symbol: "SPY", condition: .priceAbove, threshold: 400, cooldown: 3_600))
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(engine.evaluate([Quote(symbol: "SPY", price: 401)], at: start).count, 1)
        _ = engine.evaluate([Quote(symbol: "SPY", price: 399)], at: start.addingTimeInterval(10))
        XCTAssertEqual(
            engine.evaluate([Quote(symbol: "SPY", price: 402)], at: start.addingTimeInterval(20)).count,
            0
        )
    }
}
