import Foundation

// MARK: - Optimization Types

public enum OptimizationObjective: String, Codable, Sendable, CaseIterable {
    case equalWeight = "equal_weight"
    case inverseVolatility = "inverse_volatility"
    case minimumVariance = "minimum_variance"
    case maximumSharpe = "maximum_sharpe"
    case riskParity = "risk_parity"
}

public struct OptimizationConstraints: Sendable, Equatable {
    public var minWeight: Double
    public var maxWeight: Double
    public var fullyInvested: Bool

    public init(
        minWeight: Double = 0,
        maxWeight: Double = 1,
        fullyInvested: Bool = true
    ) {
        self.minWeight = max(0, minWeight)
        self.maxWeight = max(0, maxWeight)
        self.fullyInvested = fullyInvested
    }
}

public struct OptimizationResult: Sendable, Equatable {
    public let objective: OptimizationObjective
    public let weights: [String: Double]
    public let expectedReturn: Double
    public let expectedVolatility: Double
    public let sharpeRatio: Double
    public let iterations: Int
    public let converged: Bool

    public init(
        objective: OptimizationObjective,
        weights: [String: Double],
        expectedReturn: Double,
        expectedVolatility: Double,
        sharpeRatio: Double,
        iterations: Int,
        converged: Bool
    ) {
        self.objective = objective
        self.weights = weights
        self.expectedReturn = expectedReturn
        self.expectedVolatility = expectedVolatility
        self.sharpeRatio = sharpeRatio
        self.iterations = iterations
        self.converged = converged
    }

    /// Weights sorted from largest to smallest.
    public var sortedWeights: [(symbol: String, weight: Double)] {
        weights.map { (symbol: $0.key, weight: $0.value) }
            .sorted { $0.weight > $1.weight }
    }
}

// MARK: - Portfolio Optimizer

public enum PortfolioOptimizer {

    /// Optimize a long-only, fully invested portfolio from expected returns and
    /// a covariance matrix.
    public static func optimize(
        symbols: [String],
        expectedReturns: [Double],
        covariance: [[Double]],
        riskFreeRate: Double = 0,
        objective: OptimizationObjective = .maximumSharpe,
        constraints: OptimizationConstraints = OptimizationConstraints()
    ) -> OptimizationResult {
        let count = symbols.count
        guard count > 0 else {
            return OptimizationResult(
                objective: objective,
                weights: [:],
                expectedReturn: 0,
                expectedVolatility: 0,
                sharpeRatio: 0,
                iterations: 0,
                converged: false
            )
        }

        let dimensionValid = expectedReturns.count == count
            && covariance.count == count
            && covariance.allSatisfy { $0.count == count }
        guard dimensionValid else {
            return finalize(
                weights: Array(repeating: 1.0 / Double(count), count: count),
                symbols: symbols,
                expectedReturns: count == expectedReturns.count ? expectedReturns : Array(repeating: 0, count: count),
                covariance: covariance,
                objective: objective,
                riskFreeRate: riskFreeRate,
                iterations: 0,
                converged: false
            )
        }

        let cap = max(constraints.maxWeight, 1.0 / Double(count))
        let equal = Array(repeating: 1.0 / Double(count), count: count)
        let diagonal = (0..<count).map { sqrt(max(0, covariance[$0][$0])) }

        switch objective {
        case .equalWeight:
            return finalize(
                weights: equal,
                symbols: symbols,
                expectedReturns: expectedReturns,
                covariance: covariance,
                objective: objective,
                riskFreeRate: riskFreeRate,
                iterations: 0,
                converged: true
            )

        case .inverseVolatility:
            let inverse = diagonal.map { $0 > 0 ? 1.0 / $0 : 0 }
            let total = inverse.reduce(0, +)
            let raw = total > 0 ? inverse.map { $0 / total } : equal
            return finalize(
                weights: QuantMath.projectToSimplex(raw, maxWeight: cap),
                symbols: symbols,
                expectedReturns: expectedReturns,
                covariance: covariance,
                objective: objective,
                riskFreeRate: riskFreeRate,
                iterations: 0,
                converged: true
            )

        case .minimumVariance:
            let weights = minimumVariance(
                covariance: covariance,
                count: count,
                cap: cap
            )
            return finalize(
                weights: weights.weights,
                symbols: symbols,
                expectedReturns: expectedReturns,
                covariance: covariance,
                objective: objective,
                riskFreeRate: riskFreeRate,
                iterations: weights.iterations,
                converged: weights.converged
            )

        case .maximumSharpe:
            let weights = maximumSharpe(
                expectedReturns: expectedReturns,
                covariance: covariance,
                riskFreeRate: riskFreeRate,
                count: count,
                cap: cap
            )
            return finalize(
                weights: weights.weights,
                symbols: symbols,
                expectedReturns: expectedReturns,
                covariance: covariance,
                objective: objective,
                riskFreeRate: riskFreeRate,
                iterations: weights.iterations,
                converged: weights.converged
            )

        case .riskParity:
            let weights = riskParity(covariance: covariance, count: count, cap: cap)
            return finalize(
                weights: weights.weights,
                symbols: symbols,
                expectedReturns: expectedReturns,
                covariance: covariance,
                objective: objective,
                riskFreeRate: riskFreeRate,
                iterations: weights.iterations,
                converged: weights.converged
            )
        }
    }

    /// Convenience wrapper that derives moments from historical return series.
    public static func optimize(
        symbols: [String],
        historicalReturns: [[Double]],
        riskFreeRate: Double = 0,
        objective: OptimizationObjective = .maximumSharpe,
        constraints: OptimizationConstraints = OptimizationConstraints()
    ) -> OptimizationResult? {
        guard symbols.count == historicalReturns.count, !symbols.isEmpty else { return nil }
        let means = historicalReturns.map(QuantMath.mean)
        let covariance = RiskAnalytics.covarianceMatrix(historicalReturns)
        return optimize(
            symbols: symbols,
            expectedReturns: means,
            covariance: covariance,
            riskFreeRate: riskFreeRate,
            objective: objective,
            constraints: constraints
        )
    }

    // MARK: Algorithms

    private static func minimumVariance(
        covariance: [[Double]],
        count: Int,
        cap: Double
    ) -> (weights: [Double], iterations: Int, converged: Bool) {
        var weights = Array(repeating: 1.0 / Double(count), count: count)
        let trace = (0..<count).reduce(0.0) { $0 + max(0, covariance[$1][$1]) }
        let step = 1.0 / (2.0 * max(trace, 1e-9))
        var converged = false
        var iterations = 0

        for iteration in 1...5_000 {
            iterations = iteration
            let gradient = QuantMath.matrixVector(covariance, weights).map { 2 * $0 }
            let candidate = zip(weights, gradient).map { $0 - step * $1 }
            let projected = QuantMath.projectToSimplex(candidate, maxWeight: cap)
            let change = maxAbs(zip(projected, weights).map { $0 - $1 })
            weights = projected
            if change < 1e-11 {
                converged = true
                break
            }
        }
        return (weights, iterations, converged)
    }

    private static func maximumSharpe(
        expectedReturns: [Double],
        covariance: [[Double]],
        riskFreeRate: Double,
        count: Int,
        cap: Double
    ) -> (weights: [Double], iterations: Int, converged: Bool) {
        var weights = Array(repeating: 1.0 / Double(count), count: count)
        let excess = expectedReturns.map { $0 - riskFreeRate }
        var converged = false
        var iterations = 0

        func sharpe(_ candidate: [Double]) -> Double {
            let variance = RiskAnalytics.portfolioVariance(weights: candidate, covariance: covariance)
            guard variance > 0 else { return -Double.infinity }
            return QuantMath.dot(candidate, excess) / sqrt(variance)
        }

        for iteration in 1...2_000 {
            iterations = iteration
            let variance = RiskAnalytics.portfolioVariance(weights: weights, covariance: covariance)
            guard variance > 1e-16 else { break }
            let volatility = sqrt(variance)
            let strategyReturn = QuantMath.dot(weights, excess)
            let currentSharpe = strategyReturn / volatility
            let sigmaW = QuantMath.matrixVector(covariance, weights)

            // d(return / vol) / dw
            let gradient = (0..<count).map { index in
                excess[index] / volatility
                    - strategyReturn * sigmaW[index] / (volatility * volatility * volatility)
            }
            let largest = maxAbs(gradient)
            guard largest > 0 else {
                converged = true
                break
            }

            var step = 1.0 / largest
            var improved = false
            for _ in 0..<30 {
                let candidate = QuantMath.projectToSimplex(
                    zip(weights, gradient).map { $0 + step * $1 },
                    maxWeight: cap
                )
                if sharpe(candidate) > currentSharpe + 1e-14 {
                    let change = maxAbs(zip(candidate, weights).map { $0 - $1 })
                    weights = candidate
                    improved = true
                    if change < 1e-11 { converged = true }
                    break
                }
                step *= 0.5
            }
            if !improved || converged { break }
        }
        return (weights, iterations, converged)
    }

    private static func riskParity(
        covariance: [[Double]],
        count: Int,
        cap: Double
    ) -> (weights: [Double], iterations: Int, converged: Bool) {
        var weights = Array(repeating: 1.0 / Double(count), count: count)
        var converged = false
        var iterations = 0

        for iteration in 1...5_000 {
            iterations = iteration
            let variance = RiskAnalytics.portfolioVariance(weights: weights, covariance: covariance)
            guard variance > 1e-16 else { break }
            let sigmaW = QuantMath.matrixVector(covariance, weights)
            let target = variance / Double(count)
            let updated = zip(weights, sigmaW).map { weight, marginal -> Double in
                let contribution = weight * marginal
                guard contribution > 1e-16 else { return weight }
                return weight * sqrt(target / contribution)
            }
            let projected = QuantMath.projectToSimplex(updated, maxWeight: cap)
            let change = maxAbs(zip(projected, weights).map { $0 - $1 })
            weights = projected
            if change < 1e-11 {
                converged = true
                break
            }
        }
        return (weights, iterations, converged)
    }

    // MARK: Helpers

    private static func finalize(
        weights: [Double],
        symbols: [String],
        expectedReturns: [Double],
        covariance: [[Double]],
        objective: OptimizationObjective,
        riskFreeRate: Double,
        iterations: Int,
        converged: Bool
    ) -> OptimizationResult {
        let expectedReturn = QuantMath.dot(weights, expectedReturns)
        let volatility = RiskAnalytics.portfolioVolatility(weights: weights, covariance: covariance)
        let sharpe = volatility > 0 ? (expectedReturn - riskFreeRate) / volatility : 0
        var dictionary: [String: Double] = [:]
        for index in symbols.indices where index < weights.count {
            dictionary[symbols[index]] = weights[index]
        }
        return OptimizationResult(
            objective: objective,
            weights: dictionary,
            expectedReturn: expectedReturn,
            expectedVolatility: volatility,
            sharpeRatio: sharpe,
            iterations: iterations,
            converged: converged
        )
    }

    private static func maxAbs(_ values: [Double]) -> Double {
        values.reduce(0) { max($0, abs($1)) }
    }
}
