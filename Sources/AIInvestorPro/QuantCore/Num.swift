// MARK: - Num Utils
import Foundation

public func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    Swift.min(Swift.max(value, lower), upper)
}

public func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

public func normalize(_ value: Double, _ range: ClosedRange<Double>) -> Double {
    let lower = range.lowerBound
    let upper = range.upperBound
    guard upper > lower else { return 0 }
    return clamp((value - lower) / (upper - lower), 0, 1)
}

public func denormalize(_ value: Double, _ range: ClosedRange<Double>) -> Double {
    lerp(range.lowerBound, range.upperBound, clamp(value, 0, 1))
}

public func smooth(_ current: Double, _ target: Double, _ factor: Double) -> Double {
    current + (target - current) * factor
}

/// Simple moving average. Returns one value per complete window, so the
/// result is empty when the input is shorter than `period`.
public func movingAverage(_ values: [Double], _ period: Int) -> [Double] {
    guard !values.isEmpty, period > 0, values.count >= period else { return [] }

    var result: [Double] = []
    result.reserveCapacity(values.count - period + 1)
    var runningSum = values.prefix(period).reduce(0, +)
    result.append(runningSum / Double(period))

    if values.count > period {
        for index in period..<values.count {
            runningSum += values[index] - values[index - period]
            result.append(runningSum / Double(period))
        }
    }
    return result
}

/// Exponential moving average where `alpha` weights the newest observation.
public func exponentialMovingAverage(_ values: [Double], _ alpha: Double) -> [Double] {
    guard let first = values.first, alpha > 0, alpha <= 1 else { return values }

    var result: [Double] = [first]
    result.reserveCapacity(values.count)
    for index in 1..<values.count {
        result.append(result[index - 1] + alpha * (values[index] - result[index - 1]))
    }
    return result
}

/// EMA seeded with an SMA, matching the usual technical-analysis convention.
public func exponentialMovingAverage(_ values: [Double], period: Int) -> [Double] {
    guard period > 0, values.count >= period else { return [] }
    let alpha = 2.0 / (Double(period) + 1.0)
    let seed = values.prefix(period).reduce(0, +) / Double(period)
    var result: [Double] = [seed]
    result.reserveCapacity(values.count - period + 1)
    for index in period..<values.count {
        let previous = result[result.count - 1]
        result.append(previous + alpha * (values[index] - previous))
    }
    return result
}

public func sum(_ values: [Double]) -> Double {
    values.reduce(0, +)
}

public func product(_ values: [Double]) -> Double {
    values.reduce(1, *)
}

public func mean(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
}

public func standardDeviation(_ values: [Double], _ sample: Bool = true) -> Double {
    guard values.count > 1 else { return 0 }
    let m = mean(values)
    let divisor = sample ? values.count - 1 : values.count
    let variance = values.map { pow($0 - m, 2) }.reduce(0, +) / Double(divisor)
    return sqrt(max(0, variance))
}

public func zScore(_ value: Double, _ values: [Double]) -> Double {
    let m = mean(values)
    let std = standardDeviation(values)
    guard std != 0 else { return 0 }
    return (value - m) / std
}

public func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty, p >= 0, p <= 100 else { return 0 }
    let sorted = values.sorted()
    let rank = (p / 100.0) * Double(sorted.count - 1)
    let lower = Int(floor(rank))
    let upper = Int(ceil(rank))
    guard lower >= 0, upper < sorted.count else { return 0 }
    if lower == upper { return sorted[lower] }
    let weight = rank - Double(lower)
    return sorted[lower] * (1 - weight) + sorted[upper] * weight
}

public func currency(_ value: Double, decimals: Int = 2) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.minimumFractionDigits = decimals
    formatter.maximumFractionDigits = decimals
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.\(decimals)f", value)
}

// MARK: - Convenience extensions

public extension Array where Element == Double {
    func sum() -> Double {
        reduce(0, +)
    }

    func product() -> Double {
        reduce(1, *)
    }

    var mean: Double {
        self.isEmpty ? 0 : reduce(0, +) / Double(count)
    }

    /// Sample standard deviation. Returns zero for fewer than two values.
    var standardDeviation: Double {
        guard count > 1 else { return 0 }
        let average = mean
        let variance = reduce(0) { $0 + pow($1 - average, 2) } / Double(count - 1)
        return sqrt(Swift.max(0, variance))
    }

    var absoluteValue: [Double] {
        map { Swift.abs($0) }
    }
}

public extension Double {
    var absoluteValue: Double {
        Swift.abs(self)
    }

    /// Convenience property used by the legacy UI and report renderers.
    var formattedCurrency: String {
        currency(self)
    }

    func formattedPercent(decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f%%", self * 100)
    }
}

public extension String {
    var replacingUnderscoresWithSpaces: String {
        replacingOccurrences(of: "_", with: " ")
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
