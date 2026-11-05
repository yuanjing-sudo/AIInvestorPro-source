import Foundation

// MARK: - Monte Carlo Result

public struct MonteCarloResult: Sendable, Equatable {
    public let simulations: Int
    public let horizonDays: Int
    public let meanTerminalReturn: Double
    public let medianTerminalReturn: Double
    public let percentile5: Double
    public let percentile25: Double
    public let percentile75: Double
    public let percentile95: Double
    public let valueAtRisk95: Double
    public let conditionalValueAtRisk95: Double
    public let probabilityOfLoss: Double

    public init(
        simulations: Int,
        horizonDays: Int,
        meanTerminalReturn: Double,
        medianTerminalReturn: Double,
        percentile5: Double,
        percentile25: Double,
        percentile75: Double,
        percentile95: Double,
        valueAtRisk95: Double,
        conditionalValueAtRisk95: Double,
        probabilityOfLoss: Double
    ) {
        self.simulations = simulations
        self.horizonDays = horizonDays
        self.meanTerminalReturn = meanTerminalReturn
        self.medianTerminalReturn = medianTerminalReturn
        self.percentile5 = percentile5
        self.percentile25 = percentile25
        self.percentile75 = percentile75
        self.percentile95 = percentile95
        self.valueAtRisk95 = valueAtRisk95
        self.conditionalValueAtRisk95 = conditionalValueAtRisk95
        self.probabilityOfLoss = probabilityOfLoss
    }
}

// MARK: - Stress Scenario

public struct StressScenario: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    /// Symbol -> fractional shock (for example `-0.30` for a 30% decline).
    public let shocks: [String: Double]

    public init(name: String, shocks: [String: Double]) {
        self.name = name
        self.shocks = shocks
    }
}

// MARK: - Risk Analytics

public enum RiskAnalytics {

    // MARK: Covariance and correlation

    /// Covariance matrix for equally sized return series.
    public static func covarianceMatrix(_ series: [[Double]]) -> [[Double]] {
        let count = series.count
        guard count > 0 else { return [] }
        let length = series.map(\.count).min() ?? 0
        guard length > 1 else {
            return Array(repeating: Array(repeating: 0.0, count: count), count: count)
        }
        let trimmed = series.map { Array($0.suffix(length)) }
        var matrix = Array(repeating: Array(repeating: 0.0, count: count), count: count)
        for row in 0..<count {
            for column in 0..<count {
                matrix[row][column] = QuantMath.covariance(trimmed[row], trimmed[column])
            }
        }
        return matrix
    }

    public static func correlationMatrix(_ series: [[Double]]) -> [[Double]] {
        let covariance = covarianceMatrix(series)
        let volumes = (0..<series.count).map { index in
            sqrt(max(0, covariance[index][index]))
        }
        return covariance.enumerated().map { row, values in
            values.enumerated().map { column, value in
                let denominator = volumes[row] * volumes[column]
                return denominator > 0 ? value / denominator : 0
            }
        }
    }

    // MARK: Portfolio risk

    public static func portfolioVariance(weights: [Double], covariance: [[Double]]) -> Double {
        guard weights.count == covariance.count,
              covariance.allSatisfy({ $0.count == covariance.count })
        else { return 0 }
        let sigmaW = QuantMath.matrixVector(covariance, weights)
        return max(0, QuantMath.dot(weights, sigmaW))
    }

    public static func portfolioVolatility(weights: [Double], covariance: [[Double]]) -> Double {
        sqrt(portfolioVariance(weights: weights, covariance: covariance))
    }

    /// Fraction of total portfolio variance contributed by each position.
    /// The values sum to 1 for a fully invested portfolio.
    public static func riskContributions(
        weights: [Double],
        covariance: [[Double]]
    ) -> [Double] {
        let variance = portfolioVariance(weights: weights, covariance: covariance)
        guard variance > 0 else {
            return Array(repeating: 0, count: weights.count)
        }
        let sigmaW = QuantMath.matrixVector(covariance, weights)
        return zip(weights, sigmaW).map { weight, marginal in
            (weight * marginal) / variance
        }
    }

    /// Weighted-average asset volatility divided by portfolio volatility.
    /// A value above 1 indicates a diversification benefit.
    public static func diversificationRatio(
        weights: [Double],
        covariance: [[Double]]
    ) -> Double {
        guard weights.count == covariance.count,
              covariance.allSatisfy({ $0.count == covariance.count })
        else { return 0 }
        let portfolioVol = portfolioVolatility(weights: weights, covariance: covariance)
        guard portfolioVol > 0 else { return 0 }
        let weightedVol = zip(weights, 0..<weights.count).reduce(0.0) { total, pair in
            let (weight, index) = pair
            return total + weight * sqrt(max(0, covariance[index][index]))
        }
        return weightedVol / portfolioVol
    }

    // MARK: Tail risk

    /// Historical VaR at `confidence` (for example 0.95), returned as a positive
    /// loss fraction.
    public static func historicalVaR(returns: [Double], confidence: Double = 0.95) -> Double {
        guard !returns.isEmpty else { return 0 }
        let quantile = QuantMath.percentile(returns, 1 - confidence)
        return max(0, -quantile)
    }

    public static func historicalCVaR(returns: [Double], confidence: Double = 0.95) -> Double {
        guard !returns.isEmpty else { return 0 }
        let cutoff = QuantMath.percentile(returns, 1 - confidence)
        let tail = returns.filter { $0 <= cutoff }
        return tail.isEmpty ? historicalVaR(returns: returns, confidence: confidence)
            : max(0, -QuantMath.mean(tail))
    }

    /// Parametric (normal) VaR, returned as a positive loss fraction.
    public static func parametricVaR(
        mean: Double,
        standardDeviation: Double,
        confidence: Double = 0.95
    ) -> Double {
        guard standardDeviation > 0 else { return 0 }
        let z = QuantMath.inverseNormal(1 - confidence)
        return max(0, -(mean + z * standardDeviation))
    }

    // MARK: Relative risk

    public static func beta(assetReturns: [Double], benchmarkReturns: [Double]) -> Double {
        let count = min(assetReturns.count, benchmarkReturns.count)
        guard count > 2 else { return 0 }
        let asset = Array(assetReturns.suffix(count))
        let benchmark = Array(benchmarkReturns.suffix(count))
        let variance = QuantMath.variance(benchmark)
        guard variance > 0 else { return 0 }
        return QuantMath.covariance(asset, benchmark) / variance
    }

    /// Annualized alpha relative to a benchmark.
    public static func alpha(
        assetReturns: [Double],
        benchmarkReturns: [Double],
        riskFreeRate: Double = 0,
        periodsPerYear: Double = 252
    ) -> Double {
        let betaValue = beta(assetReturns: assetReturns, benchmarkReturns: benchmarkReturns)
        let count = min(assetReturns.count, benchmarkReturns.count)
        guard count > 2 else { return 0 }
        let asset = Array(assetReturns.suffix(count))
        let benchmark = Array(benchmarkReturns.suffix(count))
        let periods = max(1, periodsPerYear)
        return (QuantMath.mean(asset) - riskFreeRate / periods
            - betaValue * (QuantMath.mean(benchmark) - riskFreeRate / periods)) * periods
    }

    // MARK: Concentration

    public static func herfindahlIndex(weights: [Double]) -> Double {
        weights.reduce(0) { $0 + $1 * $1 }
    }

    public static func effectiveNumberOfPositions(weights: [Double]) -> Double {
        let hhi = herfindahlIndex(weights: weights)
        return hhi > 0 ? 1 / hhi : 0
    }

    // MARK: Monte Carlo

    /// Simulates correlated asset returns and reports the distribution of
    /// terminal portfolio returns. Uses a seeded generator for reproducibility.
    public static func monteCarlo(
        weights: [Double],
        annualMeanReturns: [Double],
        annualCovariance: [[Double]],
        horizonDays: Int = 252,
        simulations: Int = 2_000,
        seed: UInt64 = 42
    ) -> MonteCarloResult? {
        let assetCount = weights.count
        guard assetCount > 0,
              annualMeanReturns.count == assetCount,
              annualCovariance.count == assetCount,
              annualCovariance.allSatisfy({ $0.count == assetCount }),
              horizonDays > 0,
              simulations > 0
        else { return nil }

        let periods = 252.0
        let dailyMean = annualMeanReturns.map { $0 / periods }
        var dailyCovariance = annualCovariance.map { $0.map { $0 / periods } }

        // Guard against numerical issues; fall back to independent volatilities.
        if QuantMath.cholesky(dailyCovariance) == nil {
            dailyCovariance = (0..<assetCount).map { row in
                (0..<assetCount).map { column in
                    row == column ? max(0, annualCovariance[row][column] / periods) : 0
                }
            }
        }
        let factor = QuantMath.cholesky(dailyCovariance)
            ?? (0..<assetCount).map { row in
                (0..<assetCount).map { column in
                    row == column ? sqrt(max(0, dailyCovariance[row][column])) : 0
                }
            }

        var generator = SeededGenerator(seed: seed)
        var terminalReturns = [Double]()
        terminalReturns.reserveCapacity(simulations)

        for _ in 0..<simulations {
            var portfolioValue = 1.0
            for _ in 0..<horizonDays {
                var independent = [Double](repeating: 0, count: assetCount)
                for index in 0..<assetCount {
                    independent[index] = generator.nextGaussian()
                }
                var correlated = [Double](repeating: 0, count: assetCount)
                for row in 0..<assetCount {
                    var value = 0.0
                    for column in 0...row {
                        value += factor[row][column] * independent[column]
                    }
                    correlated[row] = value
                }
                var portfolioReturn = 0.0
                for index in 0..<assetCount {
                    portfolioReturn += weights[index] * (dailyMean[index] + correlated[index])
                }
                portfolioValue *= max(0.0001, 1 + portfolioReturn)
            }
            terminalReturns.append(portfolioValue - 1)
        }

        let sorted = terminalReturns.sorted()
        let var95 = max(0, -QuantMath.percentileSorted(sorted, 0.05))
        let cutoff = QuantMath.percentileSorted(sorted, 0.05)
        let tail = sorted.filter { $0 <= cutoff }
        let cvar95 = tail.isEmpty ? var95 : max(0, -QuantMath.mean(tail))
        let losses = sorted.filter { $0 < 0 }.count

        return MonteCarloResult(
            simulations: simulations,
            horizonDays: horizonDays,
            meanTerminalReturn: QuantMath.mean(sorted),
            medianTerminalReturn: QuantMath.percentileSorted(sorted, 0.5),
            percentile5: QuantMath.percentileSorted(sorted, 0.05),
            percentile25: QuantMath.percentileSorted(sorted, 0.25),
            percentile75: QuantMath.percentileSorted(sorted, 0.75),
            percentile95: QuantMath.percentileSorted(sorted, 0.95),
            valueAtRisk95: var95,
            conditionalValueAtRisk95: cvar95,
            probabilityOfLoss: Double(losses) / Double(sorted.count)
        )
    }

    // MARK: Stress testing

    /// Signed P&L implied by a set of shocks for a weighted portfolio
    /// (negative values are losses).
    public static func stressLoss(weights: [String: Double], shocks: [String: Double]) -> Double {
        var loss = 0.0
        for (symbol, weight) in weights {
            loss += weight * (shocks[symbol] ?? 0)
        }
        return loss
    }

    public static func stressLoss(weights: [String: Double], scenario: StressScenario) -> Double {
        stressLoss(weights: weights, shocks: scenario.shocks)
    }
}
