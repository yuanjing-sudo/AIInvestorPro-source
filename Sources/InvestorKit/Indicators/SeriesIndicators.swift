import Foundation

// MARK: - Series Indicators

/// Correct, series-aligned technical indicators.
///
/// Every function returns an array aligned with the input. Values that require
/// warm-up data are `nil`, so callers can safely index by the same bar index.
public enum SeriesIndicators {

    // MARK: Simple / exponential averages

    public static func sma(_ values: [Double], period: Int) -> [Double?] {
        guard period > 0, values.count >= period else { return nils(values.count) }
        var result = nils(values.count)
        var total = values[0..<period].reduce(0, +)
        result[period - 1] = total / Double(period)
        if period < values.count {
            for index in period..<values.count {
                total += values[index] - values[index - period]
                result[index] = total / Double(period)
            }
        }
        return result
    }

    public static func ema(_ values: [Double], period: Int) -> [Double?] {
        guard period > 0, values.count >= period else { return nils(values.count) }
        var result = nils(values.count)
        let alpha = 2.0 / (Double(period) + 1.0)
        var previous = values[0..<period].reduce(0, +) / Double(period)
        result[period - 1] = previous
        if period < values.count {
            for index in period..<values.count {
                previous = alpha * values[index] + (1 - alpha) * previous
                result[index] = previous
            }
        }
        return result
    }

    /// Wilder's smoothing (a.k.a. RMA), used by RSI, ATR, and ADX.
    public static func rma(_ values: [Double], period: Int) -> [Double?] {
        guard period > 0, values.count >= period else { return nils(values.count) }
        var result = nils(values.count)
        var previous = values[0..<period].reduce(0, +) / Double(period)
        result[period - 1] = previous
        if period < values.count {
            for index in period..<values.count {
                previous = (previous * Double(period - 1) + values[index]) / Double(period)
                result[index] = previous
            }
        }
        return result
    }

    // MARK: RSI

    public static func rsi(_ values: [Double], period: Int = 14) -> [Double?] {
        guard period > 0, values.count > period else { return nils(values.count) }
        var result = nils(values.count)

        var gainSum = 0.0
        var lossSum = 0.0
        for index in 1...period {
            let change = values[index] - values[index - 1]
            if change > 0 { gainSum += change } else { lossSum -= change }
        }
        var averageGain = gainSum / Double(period)
        var averageLoss = lossSum / Double(period)
        result[period] = rsiValue(averageGain, averageLoss)

        if period + 1 < values.count {
            for index in (period + 1)..<values.count {
                let change = values[index] - values[index - 1]
                let gain = max(change, 0)
                let loss = max(-change, 0)
                averageGain = (averageGain * Double(period - 1) + gain) / Double(period)
                averageLoss = (averageLoss * Double(period - 1) + loss) / Double(period)
                result[index] = rsiValue(averageGain, averageLoss)
            }
        }
        return result
    }

    private static func rsiValue(_ averageGain: Double, _ averageLoss: Double) -> Double {
        if averageLoss == 0 {
            return averageGain == 0 ? 50 : 100
        }
        let relativeStrength = averageGain / averageLoss
        return 100 - 100 / (1 + relativeStrength)
    }

    // MARK: MACD

    public struct MACDResult: Sendable {
        public let macd: [Double?]
        public let signal: [Double?]
        public let histogram: [Double?]
    }

    public static func macd(
        _ values: [Double],
        fastPeriod: Int = 12,
        slowPeriod: Int = 26,
        signalPeriod: Int = 9
    ) -> MACDResult {
        let fast = ema(values, period: fastPeriod)
        let slow = ema(values, period: slowPeriod)
        let macdLine = combine(fast, slow) { $0 - $1 }
        let signalLine = emaOnOptional(macdLine, period: signalPeriod)
        let histogram = combine(macdLine, signalLine) { $0 - $1 }
        return MACDResult(macd: macdLine, signal: signalLine, histogram: histogram)
    }

    // MARK: True range / ATR

    public static func trueRange(
        high: [Double],
        low: [Double],
        close: [Double]
    ) -> [Double] {
        let count = min(high.count, min(low.count, close.count))
        guard count > 0 else { return [] }
        var result = [Double](repeating: 0, count: count)
        result[0] = max(0, high[0] - low[0])
        if count > 1 {
            for index in 1..<count {
                let previousClose = close[index - 1]
                result[index] = max(
                    high[index] - low[index],
                    max(abs(high[index] - previousClose), abs(low[index] - previousClose))
                )
            }
        }
        return result
    }

    public static func atr(
        high: [Double],
        low: [Double],
        close: [Double],
        period: Int = 14
    ) -> [Double?] {
        rma(trueRange(high: high, low: low, close: close), period: period)
    }

    // MARK: ADX

    public struct ADXResult: Sendable {
        public let adx: [Double?]
        public let plusDI: [Double?]
        public let minusDI: [Double?]
    }

    public static func adx(
        high: [Double],
        low: [Double],
        close: [Double],
        period: Int = 14
    ) -> ADXResult {
        let count = min(high.count, min(low.count, close.count))
        guard count > period, period > 0 else {
            let empty = nils(count)
            return ADXResult(adx: empty, plusDI: empty, minusDI: empty)
        }

        var plusDM = [Double](repeating: 0, count: count)
        var minusDM = [Double](repeating: 0, count: count)
        for index in 1..<count {
            let upMove = high[index] - high[index - 1]
            let downMove = low[index - 1] - low[index]
            if upMove > downMove, upMove > 0 {
                plusDM[index] = upMove
            } else if downMove > upMove, downMove > 0 {
                minusDM[index] = downMove
            }
        }

        let atrSeries = atr(high: high, low: low, close: close, period: period)
        let plusSmooth = rma(plusDM, period: period)
        let minusSmooth = rma(minusDM, period: period)

        let plusDI = combine(plusSmooth, atrSeries) { smoothed, atrValue in
            atrValue > 0 ? 100 * smoothed / atrValue : 0
        }
        let minusDI = combine(minusSmooth, atrSeries) { smoothed, atrValue in
            atrValue > 0 ? 100 * smoothed / atrValue : 0
        }
        let dx = zip3(plusDI, minusDI, atrSeries) { plus, minus, _ in
            let denominator = plus + minus
            return denominator > 0 ? 100 * abs(plus - minus) / denominator : 0
        }
        return ADXResult(adx: rmaOnOptional(dx, period: period), plusDI: plusDI, minusDI: minusDI)
    }

    // MARK: Oscillators

    public struct StochasticResult: Sendable {
        public let k: [Double?]
        public let d: [Double?]
    }

    public static func stochastic(
        high: [Double],
        low: [Double],
        close: [Double],
        kPeriod: Int = 14,
        dPeriod: Int = 3
    ) -> StochasticResult {
        let highest = rollingMax(high, period: kPeriod)
        let lowest = rollingMin(low, period: kPeriod)
        let closeOptional = close.map { Optional($0) }
        let k = zip3(closeOptional, lowest, highest) { closeValue, lowValue, highValue in
            let range = highValue - lowValue
            return range > 0 ? (closeValue - lowValue) / range * 100 : 50
        }
        return StochasticResult(k: k, d: smaOnOptional(k, period: dPeriod))
    }

    public static func williamsR(
        high: [Double],
        low: [Double],
        close: [Double],
        period: Int = 14
    ) -> [Double?] {
        let highest = rollingMax(high, period: period)
        let lowest = rollingMin(low, period: period)
        let closeOptional = close.map { Optional($0) }
        return zip3(closeOptional, lowest, highest) { closeValue, lowValue, highValue in
            let range = highValue - lowValue
            return range > 0 ? (closeValue - highValue) / range * 100 : -50
        }
    }

    public static func cci(
        high: [Double],
        low: [Double],
        close: [Double],
        period: Int = 20
    ) -> [Double?] {
        let count = min(high.count, min(low.count, close.count))
        guard count >= period, period > 0 else { return nils(count) }
        let typical = (0..<count).map { (high[$0] + low[$0] + close[$0]) / 3.0 }
        let average = sma(typical, period: period)
        var result = nils(count)
        for index in (period - 1)..<count {
            guard let mean = average[index] else { continue }
            var deviation = 0.0
            for offset in (index - period + 1)...index {
                deviation += abs(typical[offset] - mean)
            }
            deviation /= Double(period)
            result[index] = deviation > 0 ? (typical[index] - mean) / (0.015 * deviation) : 0
        }
        return result
    }

    public static func roc(_ values: [Double], period: Int = 10) -> [Double?] {
        guard period > 0, values.count > period else { return nils(values.count) }
        var result = nils(values.count)
        for index in period..<values.count {
            let previous = values[index - period]
            result[index] = previous != 0 ? (values[index] / previous - 1) * 100 : 0
        }
        return result
    }

    // MARK: Bands and channels

    public struct Bands: Sendable {
        public let upper: [Double?]
        public let middle: [Double?]
        public let lower: [Double?]
    }

    public static func bollingerBands(
        _ values: [Double],
        period: Int = 20,
        multiplier: Double = 2
    ) -> Bands {
        let middle = sma(values, period: period)
        var upper = nils(values.count)
        var lower = nils(values.count)
        guard period > 0, values.count >= period else {
            return Bands(upper: upper, middle: middle, lower: lower)
        }
        for index in (period - 1)..<values.count {
            guard let mean = middle[index] else { continue }
            let window = values[(index - period + 1)...index]
            let variance = window.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(period)
            let deviation = sqrt(max(0, variance)) * multiplier
            upper[index] = mean + deviation
            lower[index] = mean - deviation
        }
        return Bands(upper: upper, middle: middle, lower: lower)
    }

    public static func keltnerChannels(
        high: [Double],
        low: [Double],
        close: [Double],
        period: Int = 20,
        multiplier: Double = 2
    ) -> Bands {
        let middle = ema(close, period: period)
        let atrSeries = atr(high: high, low: low, close: close, period: period)
        let upper = zip3(middle, atrSeries, middle) { mid, atrValue, _ in mid + multiplier * atrValue }
        let lower = zip3(middle, atrSeries, middle) { mid, atrValue, _ in mid - multiplier * atrValue }
        return Bands(upper: upper, middle: middle, lower: lower)
    }

    public static func donchianChannels(
        high: [Double],
        low: [Double],
        period: Int = 20
    ) -> Bands {
        let upper = rollingMax(high, period: period)
        let lower = rollingMin(low, period: period)
        let middle = combine(upper, lower) { ($0 + $1) / 2 }
        return Bands(upper: upper, middle: middle, lower: lower)
    }

    // MARK: Volume

    public static func vwap(
        high: [Double],
        low: [Double],
        close: [Double],
        volume: [Double],
        period: Int = 20
    ) -> [Double?] {
        let count = min(high.count, min(low.count, min(close.count, volume.count)))
        guard count >= period, period > 0 else { return nils(count) }
        let typical = (0..<count).map { (high[$0] + low[$0] + close[$0]) / 3.0 }
        var result = nils(count)
        for index in (period - 1)..<count {
            var priceVolume = 0.0
            var totalVolume = 0.0
            for offset in (index - period + 1)...index {
                priceVolume += typical[offset] * volume[offset]
                totalVolume += volume[offset]
            }
            result[index] = totalVolume > 0 ? priceVolume / totalVolume : nil
        }
        return result
    }

    public static func obv(close: [Double], volume: [Double]) -> [Double] {
        let count = min(close.count, volume.count)
        guard count > 0 else { return [] }
        var result = [Double](repeating: 0, count: count)
        if count > 1 {
            for index in 1..<count {
                if close[index] > close[index - 1] {
                    result[index] = result[index - 1] + volume[index]
                } else if close[index] < close[index - 1] {
                    result[index] = result[index - 1] - volume[index]
                } else {
                    result[index] = result[index - 1]
                }
            }
        }
        return result
    }

    public static func mfi(
        high: [Double],
        low: [Double],
        close: [Double],
        volume: [Double],
        period: Int = 14
    ) -> [Double?] {
        let count = min(high.count, min(low.count, min(close.count, volume.count)))
        guard count > period, period > 0 else { return nils(count) }
        let typical = (0..<count).map { (high[$0] + low[$0] + close[$0]) / 3.0 }
        var positive = [Double](repeating: 0, count: count)
        var negative = [Double](repeating: 0, count: count)
        for index in 1..<count {
            let raw = typical[index] * volume[index]
            if typical[index] > typical[index - 1] {
                positive[index] = raw
            } else if typical[index] < typical[index - 1] {
                negative[index] = raw
            }
        }
        let positiveSum = rollingSum(positive, period: period)
        let negativeSum = rollingSum(negative, period: period)
        var result = nils(count)
        for index in (period - 1)..<count {
            guard let pos = positiveSum[index], let neg = negativeSum[index] else { continue }
            if neg == 0 {
                result[index] = 100
            } else {
                let ratio = pos / neg
                result[index] = 100 - 100 / (1 + ratio)
            }
        }
        return result
    }

    // MARK: Supertrend

    public struct SupertrendResult: Sendable {
        public let line: [Double?]
        /// 1 = uptrend, -1 = downtrend.
        public let direction: [Int?]
    }

    public static func supertrend(
        high: [Double],
        low: [Double],
        close: [Double],
        period: Int = 10,
        multiplier: Double = 3
    ) -> SupertrendResult {
        let count = min(high.count, min(low.count, close.count))
        guard count > period, period > 0 else {
            return SupertrendResult(line: nils(count), direction: [Int?](repeating: nil, count: count))
        }
        let atrSeries = atr(high: high, low: low, close: close, period: period)
        var finalUpper = nils(count)
        var finalLower = nils(count)
        var line = nils(count)
        var direction = [Int?](repeating: nil, count: count)

        for index in 0..<count {
            guard let atrValue = atrSeries[index] else { continue }
            let midpoint = (high[index] + low[index]) / 2.0
            let basicUpper = midpoint + multiplier * atrValue
            let basicLower = midpoint - multiplier * atrValue

            if index > 0, let previousUpper = finalUpper[index - 1] {
                finalUpper[index] = (basicUpper < previousUpper || close[index - 1] > previousUpper)
                    ? basicUpper : previousUpper
            } else {
                finalUpper[index] = basicUpper
            }
            if index > 0, let previousLower = finalLower[index - 1] {
                finalLower[index] = (basicLower > previousLower || close[index - 1] < previousLower)
                    ? basicLower : previousLower
            } else {
                finalLower[index] = basicLower
            }

            if index > 0, let previousDirection = direction[index - 1] {
                if previousDirection == 1 {
                    direction[index] = close[index] >= (finalLower[index] ?? basicLower) ? 1 : -1
                } else {
                    direction[index] = close[index] <= (finalUpper[index] ?? basicUpper) ? -1 : 1
                }
            } else {
                direction[index] = close[index] >= midpoint ? 1 : -1
            }
            line[index] = direction[index] == 1 ? finalLower[index] : finalUpper[index]
        }
        return SupertrendResult(line: line, direction: direction)
    }

    // MARK: Aroon

    public struct AroonResult: Sendable {
        public let up: [Double?]
        public let down: [Double?]
    }

    public static func aroon(
        high: [Double],
        low: [Double],
        period: Int = 25
    ) -> AroonResult {
        let count = min(high.count, low.count)
        guard count > period, period > 0 else {
            return AroonResult(up: nils(count), down: nils(count))
        }
        var up = nils(count)
        var down = nils(count)
        for index in period..<count {
            let windowHigh = Array(high[(index - period)...index])
            let windowLow = Array(low[(index - period)...index])
            // Aroon measures how recently the extreme occurred, so use the
            // *latest* occurrence of the extreme within the window.
            let highOffset = index - (index - period) - (windowHigh.lastIndex(of: windowHigh.max()!) ?? 0)
            let lowOffset = index - (index - period) - (windowLow.lastIndex(of: windowLow.min()!) ?? 0)
            up[index] = 100 * Double(period - highOffset) / Double(period)
            down[index] = 100 * Double(period - lowOffset) / Double(period)
        }
        return AroonResult(up: up, down: down)
    }

    // MARK: Ichimoku

    public struct IchimokuResult: Sendable {
        public let tenkan: [Double?]
        public let kijun: [Double?]
        public let senkouA: [Double?]
        public let senkouB: [Double?]
        public let chikou: [Double?]
    }

    public static func ichimoku(
        high: [Double],
        low: [Double],
        close: [Double],
        conversionPeriod: Int = 9,
        basePeriod: Int = 26,
        spanPeriod: Int = 52,
        displacement: Int = 26
    ) -> IchimokuResult {
        let count = min(high.count, min(low.count, close.count))
        let conversionHigh = rollingMax(high, period: conversionPeriod)
        let conversionLow = rollingMin(low, period: conversionPeriod)
        let tenkan = combine(conversionHigh, conversionLow) { ($0 + $1) / 2 }

        let baseHigh = rollingMax(high, period: basePeriod)
        let baseLow = rollingMin(low, period: basePeriod)
        let kijun = combine(baseHigh, baseLow) { ($0 + $1) / 2 }

        let spanHigh = rollingMax(high, period: spanPeriod)
        let spanLow = rollingMin(low, period: spanPeriod)
        let rawSpanB = combine(spanHigh, spanLow) { ($0 + $1) / 2 }

        let rawSpanA = combine(tenkan, kijun) { ($0 + $1) / 2 }
        var senkouA = nils(count)
        var senkouB = nils(count)
        var chikou = nils(count)

        if displacement > 0, displacement < count {
            for index in 0..<(count - displacement) {
                senkouA[index + displacement] = rawSpanA[index]
                senkouB[index + displacement] = rawSpanB[index]
            }
            for index in displacement..<count {
                chikou[index - displacement] = close[index]
            }
        }
        return IchimokuResult(
            tenkan: tenkan,
            kijun: kijun,
            senkouA: senkouA,
            senkouB: senkouB,
            chikou: chikou
        )
    }

    // MARK: - Helpers

    private static func nils(_ count: Int) -> [Double?] {
        Array(repeating: nil, count: max(0, count))
    }

    private static func combine(
        _ a: [Double?],
        _ b: [Double?],
        _ operation: (Double, Double) -> Double
    ) -> [Double?] {
        let count = min(a.count, b.count)
        var result = nils(count)
        for index in 0..<count {
            guard let left = a[index], let right = b[index] else { continue }
            result[index] = operation(left, right)
        }
        return result
    }

    private static func zip3(
        _ a: [Double?],
        _ b: [Double?],
        _ c: [Double?],
        _ operation: (Double, Double, Double) -> Double
    ) -> [Double?] {
        let count = min(a.count, min(b.count, c.count))
        var result = nils(count)
        for index in 0..<count {
            guard let first = a[index], let second = b[index], let third = c[index] else { continue }
            result[index] = operation(first, second, third)
        }
        return result
    }

    private static func rollingMax(_ values: [Double], period: Int) -> [Double?] {
        guard period > 0, values.count >= period else { return nils(values.count) }
        var result = nils(values.count)
        for index in (period - 1)..<values.count {
            result[index] = values[(index - period + 1)...index].max()
        }
        return result
    }

    private static func rollingMin(_ values: [Double], period: Int) -> [Double?] {
        guard period > 0, values.count >= period else { return nils(values.count) }
        var result = nils(values.count)
        for index in (period - 1)..<values.count {
            result[index] = values[(index - period + 1)...index].min()
        }
        return result
    }

    private static func rollingSum(_ values: [Double], period: Int) -> [Double?] {
        guard period > 0, values.count >= period else { return nils(values.count) }
        var result = nils(values.count)
        var total = values[0..<period].reduce(0, +)
        result[period - 1] = total
        if period < values.count {
            for index in period..<values.count {
                total += values[index] - values[index - period]
                result[index] = total
            }
        }
        return result
    }

    private static func emaOnOptional(_ series: [Double?], period: Int) -> [Double?] {
        let indices = series.indices.filter { series[$0] != nil }
        guard period > 0, indices.count >= period else { return nils(series.count) }
        let compact = indices.map { series[$0]! }
        let smoothed = ema(compact, period: period)
        var result = nils(series.count)
        for (offset, originalIndex) in indices.enumerated() {
            result[originalIndex] = smoothed[offset]
        }
        return result
    }

    private static func rmaOnOptional(_ series: [Double?], period: Int) -> [Double?] {
        let indices = series.indices.filter { series[$0] != nil }
        guard period > 0, indices.count >= period else { return nils(series.count) }
        let compact = indices.map { series[$0]! }
        let smoothed = rma(compact, period: period)
        var result = nils(series.count)
        for (offset, originalIndex) in indices.enumerated() {
            result[originalIndex] = smoothed[offset]
        }
        return result
    }

    private static func smaOnOptional(_ series: [Double?], period: Int) -> [Double?] {
        let indices = series.indices.filter { series[$0] != nil }
        guard period > 0, indices.count >= period else { return nils(series.count) }
        let compact = indices.map { series[$0]! }
        let smoothed = sma(compact, period: period)
        var result = nils(series.count)
        for (offset, originalIndex) in indices.enumerated() {
            result[originalIndex] = smoothed[offset]
        }
        return result
    }
}

// MARK: - Convenience

public extension Array where Element == Double? {
    /// Last non-nil value.
    var latest: Double? {
        for value in reversed() {
            if let value { return value }
        }
        return nil
    }
}
