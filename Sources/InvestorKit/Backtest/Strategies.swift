import Foundation

// MARK: - Helpers

private func seriesValue(_ series: [Double?], _ index: Int) -> Double? {
    guard index >= 0, index < series.count else { return nil }
    return series[index]
}

// MARK: - Buy and Hold

public struct BuyAndHoldStrategy: TradingStrategy, Sendable {
    public let name = "Buy & Hold"

    public init() {}

    public func generateExposures(candles: [Candle]) -> [Double] {
        Array(repeating: 1, count: candles.count)
    }
}

// MARK: - SMA Crossover

public struct SMACrossoverStrategy: TradingStrategy, Sendable {
    public let fastPeriod: Int
    public let slowPeriod: Int
    public let shortOnBearish: Bool

    public var name: String {
        "SMA \(fastPeriod)/\(slowPeriod)\(shortOnBearish ? " (long/short)" : "")"
    }

    public init(fastPeriod: Int = 50, slowPeriod: Int = 200, shortOnBearish: Bool = false) {
        self.fastPeriod = max(1, fastPeriod)
        self.slowPeriod = max(self.fastPeriod + 1, slowPeriod)
        self.shortOnBearish = shortOnBearish
    }

    public func generateExposures(candles: [Candle]) -> [Double] {
        let closes = candles.map(\.close)
        let fast = SeriesIndicators.sma(closes, period: fastPeriod)
        let slow = SeriesIndicators.sma(closes, period: slowPeriod)
        return closes.indices.map { index in
            guard let fastValue = seriesValue(fast, index),
                  let slowValue = seriesValue(slow, index)
            else { return 0 }
            if fastValue > slowValue { return 1 }
            return shortOnBearish ? -1 : 0
        }
    }
}

// MARK: - RSI Mean Reversion

public struct RSIMeanReversionStrategy: TradingStrategy, Sendable {
    public let period: Int
    public let oversold: Double
    public let overbought: Double
    public let exitLevel: Double
    public let allowShort: Bool

    public var name: String {
        "RSI \(period) mean reversion (\(Int(oversold))/\(Int(overbought)))"
    }

    public init(
        period: Int = 14,
        oversold: Double = 30,
        overbought: Double = 70,
        exitLevel: Double = 50,
        allowShort: Bool = false
    ) {
        self.period = max(2, period)
        self.oversold = min(max(oversold, 0), 100)
        self.overbought = min(max(overbought, 0), 100)
        self.exitLevel = min(max(exitLevel, 0), 100)
        self.allowShort = allowShort
    }

    public func generateExposures(candles: [Candle]) -> [Double] {
        let closes = candles.map(\.close)
        let rsi = SeriesIndicators.rsi(closes, period: period)
        var position = 0.0
        var result = [Double](repeating: 0, count: candles.count)

        for index in closes.indices {
            if let value = seriesValue(rsi, index) {
                if position == 0 {
                    if value < oversold {
                        position = 1
                    } else if allowShort, value > overbought {
                        position = -1
                    }
                } else if position > 0 {
                    if allowShort, value > overbought {
                        position = -1
                    } else if value >= exitLevel {
                        position = 0
                    }
                } else {
                    if value < oversold {
                        position = 1
                    } else if value <= exitLevel {
                        position = 0
                    }
                }
            }
            result[index] = position
        }
        return result
    }
}

// MARK: - MACD

public struct MACDStrategy: TradingStrategy, Sendable {
    public let fastPeriod: Int
    public let slowPeriod: Int
    public let signalPeriod: Int

    public var name: String { "MACD \(fastPeriod)/\(slowPeriod)/\(signalPeriod)" }

    public init(fastPeriod: Int = 12, slowPeriod: Int = 26, signalPeriod: Int = 9) {
        self.fastPeriod = max(1, fastPeriod)
        self.slowPeriod = max(self.fastPeriod + 1, slowPeriod)
        self.signalPeriod = max(1, signalPeriod)
    }

    public func generateExposures(candles: [Candle]) -> [Double] {
        let closes = candles.map(\.close)
        let result = SeriesIndicators.macd(
            closes,
            fastPeriod: fastPeriod,
            slowPeriod: slowPeriod,
            signalPeriod: signalPeriod
        )
        return closes.indices.map { index in
            guard let macd = seriesValue(result.macd, index),
                  let signal = seriesValue(result.signal, index)
            else { return 0 }
            return macd > signal ? 1 : 0
        }
    }
}

// MARK: - Donchian Breakout

public struct DonchianBreakoutStrategy: TradingStrategy, Sendable {
    public let entryPeriod: Int
    public let exitPeriod: Int
    public let allowShort: Bool

    public var name: String {
        "Donchian \(entryPeriod)/\(exitPeriod) breakout\(allowShort ? " (long/short)" : "")"
    }

    public init(entryPeriod: Int = 20, exitPeriod: Int = 10, allowShort: Bool = false) {
        self.entryPeriod = max(1, entryPeriod)
        self.exitPeriod = max(1, exitPeriod)
        self.allowShort = allowShort
    }

    public func generateExposures(candles: [Candle]) -> [Double] {
        var position = 0.0
        var result = [Double](repeating: 0, count: candles.count)

        for index in candles.indices {
            let close = candles[index].close
            let upper: Double? = index >= entryPeriod
                ? candles[(index - entryPeriod)..<index].map(\.high).max()
                : nil
            let lower: Double? = index >= exitPeriod
                ? candles[(index - exitPeriod)..<index].map(\.low).min()
                : nil

            if position == 0 {
                if let upper, close > upper {
                    position = 1
                } else if allowShort, let lower, close < lower {
                    position = -1
                }
            } else if position > 0 {
                if let lower, close < lower { position = 0 }
            } else {
                if let upper, close > upper { position = 0 }
            }
            result[index] = position
        }
        return result
    }
}

// MARK: - Momentum

public struct MomentumStrategy: TradingStrategy, Sendable {
    public let period: Int
    public let threshold: Double
    public let allowShort: Bool

    public var name: String {
        "Momentum \(period) (\(String(format: "%.1f", threshold))%)"
    }

    public init(period: Int = 20, threshold: Double = 2, allowShort: Bool = false) {
        self.period = max(1, period)
        self.threshold = threshold
        self.allowShort = allowShort
    }

    public func generateExposures(candles: [Candle]) -> [Double] {
        let closes = candles.map(\.close)
        let roc = SeriesIndicators.roc(closes, period: period)
        return closes.indices.map { index in
            guard let value = seriesValue(roc, index) else { return 0 }
            if value > threshold { return 1 }
            if allowShort, value < -threshold { return -1 }
            return 0
        }
    }
}

// MARK: - Composite

/// Blends several strategies by averaging their target exposures.
public struct CompositeStrategy: TradingStrategy, Sendable {
    public let strategies: [any TradingStrategy]
    public let weights: [Double]

    public var name: String {
        "Composite(" + strategies.map { $0.name }.joined(separator: " + ") + ")"
    }

    public init(strategies: [any TradingStrategy], weights: [Double]? = nil) {
        self.strategies = strategies
        if let weights, weights.count == strategies.count {
            self.weights = weights.map { max(0, $0) }
        } else {
            self.weights = Array(repeating: 1, count: strategies.count)
        }
    }

    public func generateExposures(candles: [Candle]) -> [Double] {
        guard !strategies.isEmpty, !candles.isEmpty else {
            return Array(repeating: 0, count: candles.count)
        }
        var total = [Double](repeating: 0, count: candles.count)
        var totalWeight = 0.0

        for (index, strategy) in strategies.enumerated() {
            let weight = index < weights.count ? weights[index] : 0
            guard weight > 0 else { continue }
            let exposures = strategy.generateExposures(candles: candles)
            let fallback = exposures.last ?? 0
            for bar in candles.indices {
                total[bar] += weight * (bar < exposures.count ? exposures[bar] : fallback)
            }
            totalWeight += weight
        }

        guard totalWeight > 0 else { return total }
        return total.map { $0 / totalWeight }
    }
}

// MARK: - Catalog

public enum StrategyCatalog {
    /// A small, diversified set of strategies that work well as a starting
    /// point for the demo app or a screener.
    public static func defaults() -> [any TradingStrategy] {
        [
            BuyAndHoldStrategy(),
            SMACrossoverStrategy(fastPeriod: 20, slowPeriod: 50),
            SMACrossoverStrategy(fastPeriod: 50, slowPeriod: 200),
            RSIMeanReversionStrategy(),
            MACDStrategy(),
            DonchianBreakoutStrategy(),
            MomentumStrategy(),
        ]
    }
}
