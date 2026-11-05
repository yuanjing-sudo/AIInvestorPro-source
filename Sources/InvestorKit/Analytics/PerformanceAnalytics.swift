import Foundation

// MARK: - Performance Report

/// A complete set of performance and risk statistics for an equity curve.
///
/// All return/risk values are fractions (`0.12` = 12%), except the
/// `periodCount`. `maxDrawdown`, `var95`, and `cvar95` are positive loss
/// magnitudes.
public struct PerformanceReport: Sendable, Equatable {
    public let startValue: Double
    public let endValue: Double
    public let periodCount: Int
    public let totalReturn: Double
    public let cagr: Double
    public let annualizedVolatility: Double
    public let sharpeRatio: Double
    public let sortinoRatio: Double
    public let calmarRatio: Double
    public let maxDrawdown: Double
    public let ulcerIndex: Double
    public let valueAtRisk95: Double
    public let conditionalValueAtRisk95: Double
    public let bestPeriod: Double
    public let worstPeriod: Double
    public let positivePeriods: Int
    public let negativePeriods: Int
    public let winRate: Double
    public let profitFactor: Double
    public let averageWin: Double
    public let averageLoss: Double
    public let skewness: Double
    public let excessKurtosis: Double
    public let beta: Double?
    public let alpha: Double?
    public let informationRatio: Double?

    public init(
        startValue: Double,
        endValue: Double,
        periodCount: Int,
        totalReturn: Double,
        cagr: Double,
        annualizedVolatility: Double,
        sharpeRatio: Double,
        sortinoRatio: Double,
        calmarRatio: Double,
        maxDrawdown: Double,
        ulcerIndex: Double,
        valueAtRisk95: Double,
        conditionalValueAtRisk95: Double,
        bestPeriod: Double,
        worstPeriod: Double,
        positivePeriods: Int,
        negativePeriods: Int,
        winRate: Double,
        profitFactor: Double,
        averageWin: Double,
        averageLoss: Double,
        skewness: Double,
        excessKurtosis: Double,
        beta: Double?,
        alpha: Double?,
        informationRatio: Double?
    ) {
        self.startValue = startValue
        self.endValue = endValue
        self.periodCount = periodCount
        self.totalReturn = totalReturn
        self.cagr = cagr
        self.annualizedVolatility = annualizedVolatility
        self.sharpeRatio = sharpeRatio
        self.sortinoRatio = sortinoRatio
        self.calmarRatio = calmarRatio
        self.maxDrawdown = maxDrawdown
        self.ulcerIndex = ulcerIndex
        self.valueAtRisk95 = valueAtRisk95
        self.conditionalValueAtRisk95 = conditionalValueAtRisk95
        self.bestPeriod = bestPeriod
        self.worstPeriod = worstPeriod
        self.positivePeriods = positivePeriods
        self.negativePeriods = negativePeriods
        self.winRate = winRate
        self.profitFactor = profitFactor
        self.averageWin = averageWin
        self.averageLoss = averageLoss
        self.skewness = skewness
        self.excessKurtosis = excessKurtosis
        self.beta = beta
        self.alpha = alpha
        self.informationRatio = informationRatio
    }

    /// A compact, human-readable summary.
    public var summary: String {
        var lines: [String] = []
        lines.append("Total return: \(totalReturn.formattedPercent())")
        lines.append("CAGR: \(cagr.formattedPercent())")
        lines.append("Annualized volatility: \(annualizedVolatility.formattedPercent())")
        lines.append("Sharpe: \(String(format: "%.2f", sharpeRatio))")
        lines.append("Sortino: \(String(format: "%.2f", sortinoRatio))")
        lines.append("Calmar: \(String(format: "%.2f", calmarRatio))")
        lines.append("Max drawdown: \(maxDrawdown.formattedPercent())")
        lines.append("Ulcer index: \(ulcerIndex.formattedPercent())")
        lines.append("VaR 95%: \(valueAtRisk95.formattedPercent())")
        lines.append("CVaR 95%: \(conditionalValueAtRisk95.formattedPercent())")
        lines.append("Win rate: \(winRate.formattedPercent())")
        lines.append("Profit factor: \(String(format: "%.2f", profitFactor))")
        lines.append("Skew: \(String(format: "%.2f", skewness))")
        lines.append("Excess kurtosis: \(String(format: "%.2f", excessKurtosis))")
        if let beta {
            lines.append("Beta: \(String(format: "%.2f", beta))")
        }
        if let alpha {
            lines.append("Alpha (annualized): \(alpha.formattedPercent())")
        }
        if let informationRatio {
            lines.append("Information ratio: \(String(format: "%.2f", informationRatio))")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Performance Analytics

public enum PerformanceAnalytics {

    /// Analyze an equity curve. Returns `nil` when fewer than two valid
    /// positive values are supplied.
    public static func analyze(
        equity: [Double],
        benchmark: [Double]? = nil,
        riskFreeRate: Double = 0,
        periodsPerYear: Double = 252
    ) -> PerformanceReport? {
        guard equity.count >= 2,
              equity.allSatisfy({ $0.isFinite && $0 > 0 })
        else { return nil }

        let returns = simpleReturns(equity)
        guard !returns.isEmpty else { return nil }

        let periods = max(1, periodsPerYear)
        let start = equity.first!
        let end = equity.last!
        let totalReturn = end / start - 1
        let years = Double(returns.count) / periods
        let cagr = years > 0 ? pow(end / start, 1 / years) - 1 : 0
        let meanReturn = QuantMath.mean(returns)
        let deviation = QuantMath.standardDeviation(returns)
        let annualizedVolatility = deviation * sqrt(periods)
        let sharpe = deviation > 0
            ? (meanReturn - riskFreeRate / periods) / deviation * sqrt(periods)
            : 0

        let downsideDeviation = sqrt(QuantMath.mean(returns.map { min(0, $0) * min(0, $0) }))
        let sortino = downsideDeviation > 0
            ? (meanReturn - riskFreeRate / periods) / downsideDeviation * sqrt(periods)
            : 0

        let drawdowns = drawdownSeries(equity)
        let maxDrawdown = drawdowns.max() ?? 0
        let ulcer = sqrt(QuantMath.mean(drawdowns.map { $0 * $0 }))
        let calmar = maxDrawdown > 0 ? cagr / maxDrawdown : 0

        let var95 = max(0, -QuantMath.percentile(returns, 0.05))
        let cutoff = QuantMath.percentile(returns, 0.05)
        let tail = returns.filter { $0 <= cutoff }
        let cvar95 = tail.isEmpty ? var95 : max(0, -QuantMath.mean(tail))

        let positive = returns.filter { $0 > 0 }
        let negative = returns.filter { $0 < 0 }
        let grossWins = positive.reduce(0, +)
        let grossLosses = abs(negative.reduce(0, +))
        let profitFactor: Double
        if grossLosses > 0 {
            profitFactor = grossWins / grossLosses
        } else {
            profitFactor = grossWins > 0 ? .infinity : 0
        }

        // Benchmark-relative metrics.
        var beta: Double?
        var alpha: Double?
        var informationRatio: Double?
        if let benchmark, benchmark.count >= 2,
           benchmark.allSatisfy({ $0.isFinite && $0 > 0 }) {
            let benchmarkReturns = simpleReturns(benchmark)
            let count = min(returns.count, benchmarkReturns.count)
            if count > 2 {
                let strategySlice = Array(returns.suffix(count))
                let benchmarkSlice = Array(benchmarkReturns.suffix(count))
                let benchmarkVariance = QuantMath.variance(benchmarkSlice)
                if benchmarkVariance > 0 {
                    let covariance = QuantMath.covariance(strategySlice, benchmarkSlice)
                    let computedBeta = covariance / benchmarkVariance
                    beta = computedBeta
                    let meanBenchmark = QuantMath.mean(benchmarkSlice)
                    alpha = ((meanReturn - riskFreeRate / periods)
                        - computedBeta * (meanBenchmark - riskFreeRate / periods)) * periods
                }
                let active = zip(strategySlice, benchmarkSlice).map { $0 - $1 }
                let activeDeviation = QuantMath.standardDeviation(active)
                if activeDeviation > 0 {
                    informationRatio = QuantMath.mean(active) / activeDeviation * sqrt(periods)
                }
            }
        }

        return PerformanceReport(
            startValue: start,
            endValue: end,
            periodCount: returns.count,
            totalReturn: totalReturn,
            cagr: cagr,
            annualizedVolatility: annualizedVolatility,
            sharpeRatio: sharpe,
            sortinoRatio: sortino,
            calmarRatio: calmar,
            maxDrawdown: maxDrawdown,
            ulcerIndex: ulcer,
            valueAtRisk95: var95,
            conditionalValueAtRisk95: cvar95,
            bestPeriod: returns.max() ?? 0,
            worstPeriod: returns.min() ?? 0,
            positivePeriods: positive.count,
            negativePeriods: negative.count,
            winRate: Double(positive.count) / Double(returns.count),
            profitFactor: profitFactor,
            averageWin: positive.isEmpty ? 0 : QuantMath.mean(positive),
            averageLoss: negative.isEmpty ? 0 : QuantMath.mean(negative),
            skewness: skewness(returns),
            excessKurtosis: excessKurtosis(returns),
            beta: beta,
            alpha: alpha,
            informationRatio: informationRatio
        )
    }

    // MARK: Building blocks

    public static func simpleReturns(_ prices: [Double]) -> [Double] {
        guard prices.count > 1 else { return [] }
        return zip(prices.dropFirst(), prices.dropLast()).map { current, previous in
            previous > 0 ? current / previous - 1 : 0
        }
    }

    public static func logReturns(_ prices: [Double]) -> [Double] {
        guard prices.count > 1 else { return [] }
        return zip(prices.dropFirst(), prices.dropLast()).compactMap { current, previous in
            guard current > 0, previous > 0 else { return nil }
            return log(current / previous)
        }
    }

    public static func cumulativeReturns(_ returns: [Double]) -> [Double] {
        var equity = 1.0
        var result = [Double]()
        result.reserveCapacity(returns.count)
        for value in returns {
            equity *= (1 + value)
            result.append(equity)
        }
        return result
    }

    /// Drawdown at each point, as a positive fraction from the running peak.
    public static func drawdownSeries(_ equity: [Double]) -> [Double] {
        guard !equity.isEmpty else { return [] }
        var peak = equity[0]
        var result = [Double]()
        result.reserveCapacity(equity.count)
        for value in equity {
            if value > peak { peak = value }
            result.append(peak > 0 ? max(0, (peak - value) / peak) : 0)
        }
        return result
    }

    public static func maxDrawdown(_ equity: [Double]) -> Double {
        drawdownSeries(equity).max() ?? 0
    }

    public static func skewness(_ values: [Double]) -> Double {
        let count = values.count
        guard count > 2 else { return 0 }
        let mean = QuantMath.mean(values)
        let deviation = QuantMath.standardDeviation(values)
        guard deviation > 0 else { return 0 }
        let sum = values.reduce(0) { $0 + pow(($1 - mean) / deviation, 3) }
        return Double(count) / (Double(count - 1) * Double(count - 2)) * sum
    }

    public static func excessKurtosis(_ values: [Double]) -> Double {
        let count = values.count
        guard count > 3 else { return 0 }
        let mean = QuantMath.mean(values)
        let deviation = QuantMath.standardDeviation(values)
        guard deviation > 0 else { return 0 }
        let fourth = values.reduce(0) { $0 + pow(($1 - mean) / deviation, 4) } / Double(count)
        let correction = (Double(count - 1) / Double((count - 2) * (count - 3)))
            * (Double(count + 1) * fourth - 3 * Double(count - 1))
        return correction
    }
}
