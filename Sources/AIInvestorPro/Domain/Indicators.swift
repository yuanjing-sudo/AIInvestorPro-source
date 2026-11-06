// MARK: - Technical Indicators
import Foundation

/// Snapshot of the most common technical indicators for one symbol.
///
/// All values are computed from complete windows and never from partial
/// windows. When there is not enough history the neutral defaults are used,
/// so callers never have to force-unwrap.
public struct TechnicalIndicators: Sendable, Equatable {
    public let rsi: Double
    public let macd: Double
    public let macdSignal: Double
    public let macdHistogram: Double
    public let sma20: Double
    public let sma50: Double
    public let ema12: Double
    public let ema26: Double
    public let bollingerUpper: Double
    public let bollingerLower: Double
    public let bollingerMiddle: Double
    public let stochasticK: Double
    public let stochasticD: Double
    public let williamsR: Double
    public let atr: Double
    public let momentum: Double

    public init(
        rsi: Double = 50,
        macd: Double = 0,
        macdSignal: Double = 0,
        macdHistogram: Double = 0,
        sma20: Double = 0,
        sma50: Double = 0,
        ema12: Double = 0,
        ema26: Double = 0,
        bollingerUpper: Double = 0,
        bollingerLower: Double = 0,
        bollingerMiddle: Double = 0,
        stochasticK: Double = 50,
        stochasticD: Double = 50,
        williamsR: Double = -50,
        atr: Double = 0,
        momentum: Double = 0
    ) {
        self.rsi = rsi
        self.macd = macd
        self.macdSignal = macdSignal
        self.macdHistogram = macdHistogram
        self.sma20 = sma20
        self.sma50 = sma50
        self.ema12 = ema12
        self.ema26 = ema26
        self.bollingerUpper = bollingerUpper
        self.bollingerLower = bollingerLower
        self.bollingerMiddle = bollingerMiddle
        self.stochasticK = stochasticK
        self.stochasticD = stochasticD
        self.williamsR = williamsR
        self.atr = atr
        self.momentum = momentum
    }

    /// Calculate all supported indicators from closing prices. High, low and
    /// volume arrays are optional; close prices are used when they are absent,
    /// which keeps this usable with close-only data.
    public static func calculate(
        from prices: [Double],
        high: [Double]? = nil,
        low: [Double]? = nil,
        volume: [Double]? = nil
    ) -> TechnicalIndicators {
        guard prices.count >= 2, let last = prices.last else {
            return TechnicalIndicators()
        }

        let highs = validSeries(high, count: prices.count) ?? prices
        let lows = validSeries(low, count: prices.count) ?? prices

        let rsi = wilderRSI(prices, period: 14).last ?? 50

        let ema12Series = emaSeries(prices, period: 12)
        let ema26Series = emaSeries(prices, period: 26)
        let macdSeries = zip(ema12Series, ema26Series).compactMap { pair -> Double? in
            guard pair.0.isFinite, pair.1.isFinite else { return nil }
            return pair.0 - pair.1
        }
        let signalSeries = emaSeries(macdSeries, period: 9)
        let macd = macdSeries.last ?? 0
        let macdSignal = signalSeries.last.flatMap { $0.isFinite ? $0 : nil } ?? macd
        let macdHistogram = macd - macdSignal

        let sma20 = windowMean(prices, period: 20) ?? last
        let sma50 = windowMean(prices, period: 50) ?? last
        let ema12 = ema12Series.last.flatMap { $0.isFinite ? $0 : nil } ?? last
        let ema26 = ema26Series.last.flatMap { $0.isFinite ? $0 : nil } ?? last

        let bollinger = bollingerBands(prices, period: 20, deviations: 2)
        let stochastic = stochasticOscillator(highs: highs, lows: lows, close: prices, period: 14)
        let williams = williamsPercentR(highs: highs, lows: lows, close: prices, period: 14)
        let atr = averageTrueRange(highs: highs, lows: lows, closes: prices, period: 14)
        let momentum = momentumValue(prices, period: 10)

        return TechnicalIndicators(
            rsi: rsi,
            macd: macd,
            macdSignal: macdSignal,
            macdHistogram: macdHistogram,
            sma20: sma20,
            sma50: sma50,
            ema12: ema12,
            ema26: ema26,
            bollingerUpper: bollinger.upper,
            bollingerLower: bollinger.lower,
            bollingerMiddle: bollinger.middle,
            stochasticK: stochastic.k,
            stochasticD: stochastic.d,
            williamsR: williams,
            atr: atr,
            momentum: momentum
        )
    }

    // MARK: - Helpers

    private static func validSeries(_ series: [Double]?, count: Int) -> [Double]? {
        guard let series, series.count == count else { return nil }
        return series
    }

    /// Wilder's RSI with an SMA seed and Wilder smoothing thereafter.
    private static func wilderRSI(_ prices: [Double], period: Int) -> [Double] {
        guard period > 0, prices.count > period else { return [50] }

        var gains: [Double] = []
        var losses: [Double] = []
        for index in 1..<prices.count {
            let change = prices[index] - prices[index - 1]
            gains.append(max(change, 0))
            losses.append(max(-change, 0))
        }

        var averageGain = gains.prefix(period).reduce(0, +) / Double(period)
        var averageLoss = losses.prefix(period).reduce(0, +) / Double(period)
        var values: [Double] = [rsiValue(gain: averageGain, loss: averageLoss)]

        guard gains.count > period else { return values }
        for index in period..<gains.count {
            averageGain = (averageGain * Double(period - 1) + gains[index]) / Double(period)
            averageLoss = (averageLoss * Double(period - 1) + losses[index]) / Double(period)
            values.append(rsiValue(gain: averageGain, loss: averageLoss))
        }
        return values
    }

    private static func rsiValue(gain: Double, loss: Double) -> Double {
        guard loss > 0 else { return gain > 0 ? 100 : 50 }
        let relativeStrength = gain / loss
        return 100 - 100 / (1 + relativeStrength)
    }

    /// EMA series aligned with the input. Values before the SMA seed are
    /// `NaN` so callers can align MACD and its signal line instead of
    /// accidentally mixing warm-up placeholders into the calculation.
    private static func emaSeries(_ values: [Double], period: Int) -> [Double] {
        guard period > 0, !values.isEmpty else { return values }
        guard values.count >= period else {
            return Array(repeating: Double.nan, count: values.count)
        }

        let alpha = 2.0 / (Double(period) + 1)
        let seedIndex = period - 1
        var result = Array(repeating: Double.nan, count: values.count)
        result[seedIndex] = values.prefix(period).reduce(0, +) / Double(period)
        if seedIndex + 1 < values.count {
            for index in (seedIndex + 1)..<values.count {
                result[index] = result[index - 1] + alpha * (values[index] - result[index - 1])
            }
        }
        return result
    }

    private static func windowMean(_ values: [Double], period: Int) -> Double? {
        guard period > 0, values.count >= period else { return nil }
        return values.suffix(period).reduce(0, +) / Double(period)
    }

    private static func bollingerBands(
        _ prices: [Double],
        period: Int,
        deviations: Double
    ) -> (upper: Double, middle: Double, lower: Double) {
        guard let middle = windowMean(prices, period: period) else {
            let last = prices.last ?? 0
            return (last, last, last)
        }
        let window = prices.suffix(period)
        let variance = window.reduce(0) { $0 + pow($1 - middle, 2) } / Double(period)
        let standardDeviation = sqrt(max(0, variance))
        return (
            middle + deviations * standardDeviation,
            middle,
            middle - deviations * standardDeviation
        )
    }

    private static func stochasticOscillator(
        highs: [Double],
        lows: [Double],
        close: [Double],
        period: Int
    ) -> (k: Double, d: Double) {
        guard period > 0, close.count >= period else { return (50, 50) }
        let start = close.count - period
        let high = highs[start...].max() ?? close.last ?? 0
        let low = lows[start...].min() ?? close.last ?? 0
        let current = close.last ?? 0
        guard high > low else { return (50, 50) }
        let k = (current - low) / (high - low) * 100
        // %D is the 3-period SMA of %K. With one %K observation available we
        // return the same value rather than fabricating a smoothed series.
        return (clamp(k, 0, 100), clamp(k, 0, 100))
    }

    private static func williamsPercentR(
        highs: [Double],
        lows: [Double],
        close: [Double],
        period: Int
    ) -> Double {
        guard period > 0, close.count >= period else { return -50 }
        let start = close.count - period
        let high = highs[start...].max() ?? close.last ?? 0
        let low = lows[start...].min() ?? close.last ?? 0
        let current = close.last ?? 0
        guard high > low else { return -50 }
        return -(high - current) / (high - low) * 100
    }

    /// Wilder ATR over the last `period` true ranges.
    private static func averageTrueRange(
        highs: [Double],
        lows: [Double],
        closes: [Double],
        period: Int
    ) -> Double {
        guard period > 0, closes.count > period else { return 0 }
        var trueRanges: [Double] = []
        trueRanges.reserveCapacity(closes.count - 1)
        for index in 1..<closes.count {
            let range = highs[index] - lows[index]
            let highGap = abs(highs[index] - closes[index - 1])
            let lowGap = abs(lows[index] - closes[index - 1])
            trueRanges.append(max(range, max(highGap, lowGap)))
        }
        guard trueRanges.count >= period else { return 0 }
        var atr = trueRanges.prefix(period).reduce(0, +) / Double(period)
        if trueRanges.count > period {
            for index in period..<trueRanges.count {
                atr = (atr * Double(period - 1) + trueRanges[index]) / Double(period)
            }
        }
        return atr
    }

    private static func momentumValue(_ prices: [Double], period: Int) -> Double {
        guard period > 0, prices.count > period else { return 0 }
        let previous = prices[prices.count - 1 - period]
        return prices[prices.count - 1] - previous
    }
}
