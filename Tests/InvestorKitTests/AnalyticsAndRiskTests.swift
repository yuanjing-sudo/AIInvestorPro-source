import XCTest
@testable import InvestorKit

final class PerformanceAnalyticsTests: XCTestCase {

    func testTotalReturnAndDrawdown() {
        let equity = [100.0, 110.0, 99.0, 108.9]
        let report = PerformanceAnalytics.analyze(equity: equity)
        XCTAssertNotNil(report)
        XCTAssertEqual(report!.totalReturn, 0.089, accuracy: 1e-9)
        XCTAssertEqual(report!.maxDrawdown, 0.1, accuracy: 1e-9)
        XCTAssertEqual(report!.periodCount, 3)
        XCTAssertEqual(report!.bestPeriod, 0.1, accuracy: 1e-9)
    }

    func testDrawdownSeries() {
        let drawdowns = PerformanceAnalytics.drawdownSeries([100, 120, 90, 95])
        XCTAssertEqual(drawdowns, [0, 0, 0.25, 0.20833333333333334])
    }

    func testBenchmarkBetaOfIdenticalSeriesIsOne() {
        let returns = [0.01, -0.02, 0.03, 0.01, -0.01]
        let equity = PerformanceAnalytics.cumulativeReturns(returns)
        let report = PerformanceAnalytics.analyze(equity: equity, benchmark: equity)
        XCTAssertNotNil(report?.beta)
        XCTAssertEqual(report!.beta!, 1.0, accuracy: 1e-9)
        XCTAssertNil(report!.informationRatio)
    }

    func testValuesAtRiskAreNonNegative() {
        let equity = [100, 99, 101, 98, 102, 97, 103]
        let report = PerformanceAnalytics.analyze(equity: equity)!
        XCTAssertGreaterThanOrEqual(report.valueAtRisk95, 0)
        XCTAssertGreaterThanOrEqual(report.conditionalValueAtRisk95, report.valueAtRisk95)
        XCTAssertGreaterThanOrEqual(report.ulcerIndex, 0)
    }

    func testSkewnessAndKurtosisAreFinite() {
        let values = [0.01, 0.02, -0.01, 0.03, -0.02, 0.01]
        let skew = PerformanceAnalytics.skewness(values)
        let kurtosis = PerformanceAnalytics.excessKurtosis(values)
        XCTAssertTrue(skew.isFinite)
        XCTAssertTrue(kurtosis.isFinite)
    }

    func testLogReturns() {
        let prices = [100.0, 110.0, 99.0]
        let returns = PerformanceAnalytics.logReturns(prices)
        XCTAssertEqual(returns.count, 2)
        XCTAssertEqual(returns[0], log(1.1), accuracy: 1e-12)
    }
}

final class RiskAndOptimizerTests: XCTestCase {

    func testCovarianceAndCorrelation() {
        let a = [1.0, 2.0, 3.0, 4.0, 5.0]
        let b = a.map { $0 * 2 }
        let covariance = RiskAnalytics.covarianceMatrix([a, b])
        let variance = QuantMath.variance(a)
        XCTAssertEqual(covariance[0][0], variance, accuracy: 1e-12)
        XCTAssertEqual(covariance[0][1], variance * 2, accuracy: 1e-12)
        let correlation = RiskAnalytics.correlationMatrix([a, b])
        XCTAssertEqual(correlation[0][1], 1.0, accuracy: 1e-12)
    }

    func testPortfolioRiskContributionsSumToOne() {
        let covariance = [
            [0.04, 0.01, 0.0],
            [0.01, 0.09, 0.02],
            [0.0, 0.02, 0.16],
        ]
        let weights = [0.4, 0.35, 0.25]
        let contributions = RiskAnalytics.riskContributions(weights: weights, covariance: covariance)
        XCTAssertEqual(contributions.reduce(0, +), 1.0, accuracy: 1e-9)
        XCTAssertGreaterThan(RiskAnalytics.diversificationRatio(weights: weights, covariance: covariance), 0)
        XCTAssertEqual(RiskAnalytics.effectiveNumberOfPositions(weights: weights), 1 / RiskAnalytics.herfindahlIndex(weights: weights), accuracy: 1e-12)
    }

    func testHistoricalVsParametricVaR() {
        let returns = [-0.05, -0.03, -0.01, 0.0, 0.01, 0.02, 0.03, 0.04]
        XCTAssertEqual(RiskAnalytics.historicalVaR(returns: returns, confidence: 0.95), 0.043, accuracy: 1e-12)
        XCTAssertGreaterThanOrEqual(RiskAnalytics.parametricVaR(mean: 0.001, standardDeviation: 0.02), 0)
    }

    func testOptimizerWeightsAreValid() {
        let covariance = [
            [0.04, 0.006, 0.002],
            [0.006, 0.09, 0.01],
            [0.002, 0.01, 0.16],
        ]
        let expectedReturns = [0.08, 0.12, 0.15]

        for objective in OptimizationObjective.allCases {
            let result = PortfolioOptimizer.optimize(
                symbols: ["A", "B", "C"],
                expectedReturns: expectedReturns,
                covariance: covariance,
                objective: objective,
                constraints: OptimizationConstraints(maxWeight: 0.7)
            )
            XCTAssertEqual(result.weights.values.reduce(0, +), 1.0, accuracy: 1e-6)
            for weight in result.weights.values {
                XCTAssertGreaterThanOrEqual(weight, 0)
                XCTAssertLessThanOrEqual(weight, 0.7 + 1e-9)
            }
        }
    }

    func testRiskParityWithIdenticalAssetsIsEqualWeight() {
        let covariance = [
            [0.04, 0.0],
            [0.0, 0.04],
        ]
        let result = PortfolioOptimizer.optimize(
            symbols: ["A", "B"],
            expectedReturns: [0.1, 0.1],
            covariance: covariance,
            objective: .riskParity
        )
        XCTAssertEqual(result.weights["A"]!, 0.5, accuracy: 1e-6)
        XCTAssertEqual(result.weights["B"]!, 0.5, accuracy: 1e-6)
    }

    func testMonteCarloIsDeterministic() {
        let weights = [0.5, 0.5]
        let means = [0.08, 0.12]
        let covariance = [
            [0.04, 0.006],
            [0.006, 0.09],
        ]
        let first = RiskAnalytics.monteCarlo(
            weights: weights,
            annualMeanReturns: means,
            annualCovariance: covariance,
            horizonDays: 30,
            simulations: 200,
            seed: 7
        )
        let second = RiskAnalytics.monteCarlo(
            weights: weights,
            annualMeanReturns: means,
            annualCovariance: covariance,
            horizonDays: 30,
            simulations: 200,
            seed: 7
        )
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
        XCTAssertGreaterThanOrEqual(first!.probabilityOfLoss, 0)
        XCTAssertLessThanOrEqual(first!.probabilityOfLoss, 1)
    }

    func testStressLoss() {
        let weights = ["A": 0.6, "B": 0.4]
        let scenario = StressScenario(name: "Crash", shocks: ["A": -0.3, "B": -0.1])
        XCTAssertEqual(RiskAnalytics.stressLoss(weights: weights, scenario: scenario), -0.22, accuracy: 1e-12)
    }
}
