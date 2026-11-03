// MARK: - Num Utils
import Foundation

public func clamp<T: Comparable>(_ value: T, _ min: T, _ max: T) -> T {
    min(max(value, min), max)
}

public func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

public func normalize(_ value: Double, _ range: ClosedRange<Double>) -> Double {
    let lower = range.lowerBound
    let upper = range.upperBound
    return clamp((value - lower) / (upper - lower), 0, 1)
}

public func denormalize(_ value: Double, _ range: ClosedRange<Double>) -> Double {
    lerp(range.lowerBound, range.upperBound, normalize(value, range))
}

public func smooth(_ current: Double, _ target: Double, _ factor: Double) -> Double {
    current + (target - current) * factor
}

public func movingAverage(_ values: [Double], _ period: Int) -> [Double] {
    guard !values.isEmpty, period > 0 else { return values }
    guard period >= values.count else { return [] }
    
    var result: [Double] = []
    var sum = 0.0
    let count = min(period, values.count)
    for i in 0..<count {
        sum += values[i]
    }
    result.append(sum / Double(count))
    
    for i in period..<values.count {
        sum += values[i] - values[i - period]
        result.append(sum / Double(period))
    }
    
    return result
}

public func exponentialMovingAverage(_ values: [Double], _ alpha: Double) -> [Double] {
    guard !values.isEmpty, alpha > 0, alpha <= 1 else { return values }
    
    var result: [Double] = [values.first!]
    for i in 1..<values.count {
        result.append(result[i-1] * alpha + values[i] * (1 - alpha))
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
    return sqrt(variance)
}

public func zScore(_ value: Double, _ values: [Double]) -> Double {
    let m = mean(values)
    let std = standardDeviation(values)
    guard std != 0 else { return 0 }
    return (value - m) / std
}

public func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty, p > 0, p < 100 else { return 0 }
    let sorted = values.sorted()
    let idx = Int(ceil(p / 100.0 * Double(sorted.count)) - 1)
    guard idx >= 0, idx < sorted.count else { return 0 }
    return sorted[idx]
}

// Helper extension for Array of Doubles
public extension Array where Element == Double {
    func sum() -> Double {
        reduce(0, +)
    }
    
    func product() -> Double {
        reduce(1, *)
    }
}
