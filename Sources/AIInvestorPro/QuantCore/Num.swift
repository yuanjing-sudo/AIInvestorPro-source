// MARK: - Num Utils
import Foundation

public func clamp<T: Comparable>(_ value: T, _ min: T, _ max: T) -> T {
    min(max(value, min), max)
}

public func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

public func normalize(_ value: Double, _ range: ClosedRange<Double>) -> Double {
    clamp((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0, 1)
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
    var sum = values[0..<period].reduce(0, +)
    result.append(sum / Double(period))
    
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
    sum(values) / Double(values.count)
}

public func standardDeviation(_ values: [Double], _ sample: Bool = true) -> Double {
    let mean = self.mean
    let count = Double(values.count)
    let divisor = sample ? count - 1 : count
    let variance = map { pow($0 - mean, 2) }.reduce(0, +) / divisor
    return sqrt(variance)
}

public func zScore(_ value: Double, _ values: [Double]) -> Double {
    let mean = values.mean
    let std = values.standardDeviation
    guard std != 0 else { return 0 }
    return (value - mean) / std
}

public func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty, p > 0, p < 100 else { return 0 }
    let sorted = values.sorted()
    let index = Int(ceil(p / 100.0 * Double(sorted.count)) - 1)
    guard index >= 0, index < sorted.count else { return 0 }
    return sorted[index]
}

// MARK: - Probability Distributions
public func normalPDF(_ x: Double, _ mean: Double = 0, _ std: Double = 1) -> Double {
    let coefficient = 1 / (std * sqrt(2 * .pi))
    let exponent = -pow(x - mean, 2) / (2 * pow(std, 2))
    return coefficient * exp(exponent)
}

// MARK: - Random Utilities
public func random(_ range: ClosedRange<Double>) -> Double {
    range.lowerBound + Double.random(in: 0...1) * (range.upperBound - range.lowerBound)
}

public func randomSign() -> Double {
    Double.random(in: 0...1) > 0.5 ? 1 : -1
}

// MARK: - Double Extensions
public extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
    var radiansToDegrees: Double { self * 180 / .pi }
    
    func rounded(to places: Int) -> Double {
        let multiplier = pow(10, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
    
    var formattedCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
    
    var formattedPercent: String {
        "\(String(format: "%.2f", self))%"
    }
}
