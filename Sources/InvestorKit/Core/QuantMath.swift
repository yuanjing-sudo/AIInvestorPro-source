import Foundation

// MARK: - Quant Math

/// Small, dependency-free numerical helpers used across InvestorKit.
///
/// All functions are deterministic and safe on empty or malformed input. Where a
/// result is undefined (for example, the mean of an empty array) the function
/// returns `0` rather than trapping.
public enum QuantMath {

    // MARK: Averages and dispersion

    public static func sum(_ values: [Double]) -> Double {
        values.reduce(0, +)
    }

    public static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Sample (n-1) or population (n) variance.
    public static func variance(_ values: [Double], sample: Bool = true) -> Double {
        guard values.count > 1 else { return 0 }
        let mu = mean(values)
        let divisor = sample ? Double(values.count - 1) : Double(values.count)
        guard divisor > 0 else { return 0 }
        return values.reduce(0) { $0 + ($1 - mu) * ($1 - mu) } / divisor
    }

    public static func standardDeviation(_ values: [Double], sample: Bool = true) -> Double {
        sqrt(max(0, variance(values, sample: sample)))
    }

    /// Covariance between two equally sized series.
    public static func covariance(_ a: [Double], _ b: [Double], sample: Bool = true) -> Double {
        let n = min(a.count, b.count)
        guard n > 1 else { return 0 }
        let meanA = mean(Array(a.prefix(n)))
        let meanB = mean(Array(b.prefix(n)))
        let divisor = sample ? Double(n - 1) : Double(n)
        guard divisor > 0 else { return 0 }
        var total = 0.0
        for i in 0..<n {
            total += (a[i] - meanA) * (b[i] - meanB)
        }
        return total / divisor
    }

    public static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        // Trim both series to the overlapping prefix so the standard
        // deviations and the covariance are computed over the same sample.
        let n = min(a.count, b.count)
        guard n > 1 else { return 0 }
        let x = Array(a.prefix(n))
        let y = Array(b.prefix(n))
        let denom = standardDeviation(x) * standardDeviation(y)
        guard denom > 0 else { return 0 }
        return covariance(x, y) / denom
    }

    public static func dot(_ a: [Double], _ b: [Double]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        var total = 0.0
        for i in 0..<n { total += a[i] * b[i] }
        return total
    }

    // MARK: Percentiles

    /// Linear-interpolated percentile. `p` is in `0...1`.
    public static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let clamped = min(max(p, 0), 1)
        let sorted = values.sorted()
        return percentileSorted(sorted, clamped)
    }

    /// Linear-interpolated percentile for an already sorted array.
    public static func percentileSorted(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let clamped = min(max(p, 0), 1)
        guard sorted.count > 1 else { return sorted[0] }
        let rank = clamped * Double(sorted.count - 1)
        let lower = Int(floor(rank))
        let upper = Int(ceil(rank))
        let weight = rank - Double(lower)
        if lower == upper { return sorted[lower] }
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    // MARK: Distributions

    /// Standard normal CDF using an Abramowitz-Stegun approximation.
    public static func normalCDF(_ value: Double) -> Double {
        let x = value * 0.7071067811865476 // 1 / sqrt(2)
        let sign: Double = x < 0 ? -1 : 1
        let ax = abs(x)
        let t = 1.0 / (1.0 + 0.3275911 * ax)
        let y = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t
            - 0.284496736) * t + 0.254829592) * t * exp(-ax * ax)
        return 0.5 * (1.0 + sign * y)
    }

    /// Inverse standard normal CDF (Acklam's rational approximation).
    ///
    /// Accuracy is roughly 1e-9 in the central region and better than 1e-4 in
    /// the tails, which is plenty for risk sizing.
    public static func inverseNormal(_ p: Double) -> Double {
        let probability = min(max(p, 1e-12), 1 - 1e-12)
        let a: [Double] = [
            -3.969683028665376e+01, 2.209460984245205e+02,
            -2.759285104469687e+02, 1.383577518672690e+02,
            -3.066479806614716e+01, 2.506628277459239e+00,
        ]
        let b: [Double] = [
            -5.447609879822406e+01, 1.615858368580409e+02,
            -1.556989798598866e+02, 6.680131188771972e+01,
            -1.328068155288572e+01,
        ]
        let c: [Double] = [
            -7.784894002430293e-03, -3.223964580411365e-01,
            -2.400758277161838e+00, -2.549732539343734e+00,
            4.374664141464968e+00, 2.938163982698783e+00,
        ]
        let d: [Double] = [
            7.784695709041462e-03, 3.224671290700398e-01,
            2.445134137142996e+00, 3.754408661907416e+00,
        ]
        let low = 0.02425
        let high = 1 - low

        if probability < low {
            let q = sqrt(-2 * log(probability))
            return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        } else if probability > high {
            let q = sqrt(-2 * log(1 - probability))
            return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        } else {
            let q = probability - 0.5
            let r = q * q
            return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
                / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
        }
    }

    // MARK: Linear algebra

    /// Lower-triangular Cholesky factor, or `nil` if the matrix is not
    /// positive-definite.
    public static func cholesky(_ matrix: [[Double]]) -> [[Double]]? {
        let n = matrix.count
        guard n > 0, matrix.allSatisfy({ $0.count == n }) else { return nil }
        var lower = Array(repeating: Array(repeating: 0.0, count: n), count: n)

        for i in 0..<n {
            for j in 0...i {
                var sum = matrix[i][j]
                for k in 0..<j {
                    sum -= lower[i][k] * lower[j][k]
                }
                if i == j {
                    guard sum > 1e-12 else { return nil }
                    lower[i][j] = sqrt(sum)
                } else {
                    guard abs(lower[j][j]) > 1e-12 else { return nil }
                    lower[i][j] = sum / lower[j][j]
                }
            }
        }
        return lower
    }

    public static func matrixVector(_ matrix: [[Double]], _ vector: [Double]) -> [Double] {
        guard !matrix.isEmpty else { return [] }
        return matrix.map { row in dot(row, vector) }
    }

    /// Projects a vector onto `{ w : sum(w) = 1, 0 <= w_i <= maxWeight }`.
    public static func projectToSimplex(_ values: [Double], maxWeight: Double = 1.0) -> [Double] {
        let n = values.count
        guard n > 0 else { return [] }
        let upper = max(maxWeight, 1.0 / Double(n))
        guard n * upper >= 1 else { return Array(repeating: 1.0 / Double(n), count: n) }

        // Find tau such that sum(clamp(v_i - tau, 0, upper)) == 1. The sum is
        // monotonically decreasing in tau, so bisection is sufficient.
        var low = values.min()! - upper - 1.0
        var high = values.max()! + 1.0
        var result = values

        for _ in 0..<80 {
            let mid = (low + high) / 2.0
            result = values.map { min(max($0 - mid, 0), upper) }
            let total = result.reduce(0, +)
            if total > 1.0 {
                low = mid
            } else {
                high = mid
            }
        }
        let total = result.reduce(0, +)
        if total > 0 {
            result = result.map { $0 / total }
        }
        // Scaling to sum to one can nudge a value above the cap; clamp and
        // renormalize the remainder once.
        result = result.map { min(max($0, 0), upper) }
        let secondTotal = result.reduce(0, +)
        if secondTotal > 0 {
            result = result.map { $0 / secondTotal }
        }
        return result
    }

    // MARK: Annualization

    public static func annualizationFactor(periodsPerYear: Double) -> Double {
        max(1, periodsPerYear)
    }
}

// MARK: - Seeded Random Generator

/// Deterministic SplitMix64 generator. Useful for reproducible backtests,
/// Monte Carlo runs, and tests.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64 = 0x9E37_79B9_7F4A_7C15) {
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform value in `0..<1`.
    public mutating func nextDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Standard normal sample via Box-Muller.
    public mutating func nextGaussian() -> Double {
        let u1 = max(nextDouble(), 1e-12)
        let u2 = nextDouble()
        return sqrt(-2.0 * log(u1)) * cos(2.0 * Double.pi * u2)
    }
}
