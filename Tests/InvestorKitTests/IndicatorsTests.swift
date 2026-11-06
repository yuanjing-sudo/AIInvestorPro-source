import XCTest
@testable import InvestorKit

final class IndicatorsTests: XCTestCase {

    func testSimpleMovingAverageAlignment() {
        let result = SeriesIndicators.sma([1, 2, 3, 4, 5], period: 3)
        XCTAssertEqual(result.count, 5)
        XCTAssertNil(result[0])
        XCTAssertNil(result[1])
        XCTAssertEqual(result[2]!, 2.0, accuracy: 1e-12)
        XCTAssertEqual(result[3]!, 3.0, accuracy: 1e-12)
        XCTAssertEqual(result[4]!, 4.0, accuracy: 1e-12)
    }

    func testExponentialMovingAverageSeedsWithSMA() {
        let result = SeriesIndicators.ema([1, 2, 3, 4, 5], period: 3)
        XCTAssertNil(result[1])
        XCTAssertEqual(result[2]!, 2.0, accuracy: 1e-12)
        XCTAssertEqual(result[3]!, 3.0, accuracy: 1e-12)
        XCTAssertEqual(result[4]!, 4.0, accuracy: 1e-12)
    }

    func testRSIOfMonotonicRiseIsOneHundred() {
        let prices = (1...40).map(Double.init)
        let result = SeriesIndicators.rsi(prices, period: 14)
        XCTAssertNil(result[13])
        XCTAssertEqual(result[14]!, 100.0, accuracy: 1e-9)
        XCTAssertEqual(result.last!!, 100.0, accuracy: 1e-9)
    }

    func testATRWithConstantRange() {
        let close = Array(repeating: 100.0, count: 40)
        let high = close.map { $0 + 1 }
        let low = close.map { $0 - 1 }
        let result = SeriesIndicators.atr(high: high, low: low, close: close, period: 14)
        XCTAssertNil(result[12])
        XCTAssertEqual(result[13]!, 2.0, accuracy: 1e-9)
        XCTAssertEqual(result.last!!, 2.0, accuracy: 1e-9)
    }

    func testMACDAndBollingerShapes() {
        let prices = (1...80).map { 100 + sin(Double($0) / 5) * 10 }
        let macd = SeriesIndicators.macd(prices)
        XCTAssertEqual(macd.macd.count, prices.count)
        XCTAssertEqual(macd.signal.count, prices.count)
        XCTAssertEqual(macd.histogram.count, prices.count)

        let bands = SeriesIndicators.bollingerBands(prices, period: 20)
        XCTAssertEqual(bands.upper.count, prices.count)
        XCTAssertNil(bands.upper[18])
        XCTAssertNotNil(bands.upper[19])
        XCTAssertGreaterThan(bands.upper.last!!, bands.lower.last!!)
    }

    func testAroonUsesMostRecentExtreme() {
        let high = [1.0, 2, 3, 4, 5, 4, 3, 2, 1]
        let low = high.map { $0 - 0.5 }
        let aroon = SeriesIndicators.aroon(high: high, low: low, period: 3)

        XCTAssertNil(aroon.up[2])
        XCTAssertEqual(aroon.up[3]!, 100, accuracy: 1e-9)
        XCTAssertEqual(aroon.up[4]!, 100, accuracy: 1e-9)
        XCTAssertEqual(aroon.up[5]!, 200.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(aroon.up[6]!, 100.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(aroon.up[8]!, 0, accuracy: 1e-9)
    }

    func testStochasticAndWilliamsRanges() {
        let high = (1...60).map { 100 + Double($0 % 5) }
        let low = high.map { $0 - 3 }
        let close = high.map { $0 - 1 }
        let stochastic = SeriesIndicators.stochastic(high: high, low: low, close: close)
        let williams = SeriesIndicators.williamsR(high: high, low: low, close: close)
        XCTAssertNotNil(stochastic.k.last!)
        XCTAssertGreaterThanOrEqual(stochastic.k.last!!, 0)
        XCTAssertLessThanOrEqual(stochastic.k.last!!, 100)
        XCTAssertNotNil(williams.last!)
        XCTAssertGreaterThanOrEqual(williams.last!!, -100)
        XCTAssertLessThanOrEqual(williams.last!!, 0)
    }
}
