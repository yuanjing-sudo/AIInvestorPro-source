import Foundation
import InvestorKit

@main
struct InvestorKitDemo {
    static func main() async throws {
        print("InvestorKit demo")
        print("=================\n")

        let provider = MockMarketDataProvider(seed: 7)
        let symbol = "AAPL"
        let candles = try await provider.candles(
            symbol: symbol,
            range: .twoYears,
            interval: .oneDay
        )
        print("Loaded \(candles.count) synthetic daily bars for \(symbol).")
        if let first = candles.first, let last = candles.last {
            print("Range: \(first.close.formattedCurrency()) → \(last.close.formattedCurrency())\n")
        }

        // MARK: Backtest every catalog strategy

        let engine = BacktestEngine()
        let config = BacktestConfig(
            initialCash: 100_000,
            commissionBps: 5,
            slippageBps: 2
        )
        var results: [BacktestResult] = []

        print(pad("Strategy", 36) + "Return     Sharpe   Max DD   Trades")
        print(String(repeating: "-", count: 76))
        for strategy in StrategyCatalog.defaults() {
            guard let result = engine.run(
                strategy: strategy,
                candles: candles,
                symbol: symbol,
                config: config
            ) else { continue }
            results.append(result)
            let totalReturn = result.report?.totalReturn ?? 0
            let sharpe = result.report?.sharpeRatio ?? 0
            let drawdown = result.report?.maxDrawdown ?? 0
            print(
                pad(strategy.name, 36)
                    + pad(totalReturn.formattedPercent(), 11)
                    + pad(String(format: "%.2f", sharpe), 9)
                    + pad(drawdown.formattedPercent(), 9)
                    + "\(result.numberOfTrades)"
            )
        }

        if let best = results.max(by: {
            ($0.report?.sharpeRatio ?? -Double.infinity)
                < ($1.report?.sharpeRatio ?? -Double.infinity)
        }) {
            print("\nBest risk-adjusted strategy: \(best.strategyName)")
            print(best.report?.summary ?? "")
            let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("demo-backtest.md")
            try ReportExporter.write(ReportExporter.markdown(best), to: output)
            print("\nMarkdown report written to \(output.path)")
        }

        // MARK: Portfolio optimization

        let universe = ["AAPL", "MSFT", "NVDA", "SPY"]
        var returnSeries: [[Double]] = []
        for ticker in universe {
            let series = try await provider.candles(
                symbol: ticker,
                range: .twoYears,
                interval: .oneDay
            )
            returnSeries.append(PerformanceAnalytics.simpleReturns(series.map(\.effectiveClose)))
        }
        let count = returnSeries.map(\.count).min() ?? 0
        let aligned = returnSeries.map { Array($0.suffix(count)) }
        let means = aligned.map(QuantMath.mean)
        let covariance = RiskAnalytics.covarianceMatrix(aligned)

        if let optimized = PortfolioOptimizer.optimize(
            symbols: universe,
            historicalReturns: aligned,
            objective: .maximumSharpe
        ) {
            print("\nMax-Sharpe portfolio")
            print("Expected return (daily): \(optimized.expectedReturn.formattedPercent(decimals: 4))")
            print("Volatility (daily): \(optimized.expectedVolatility.formattedPercent(decimals: 4))")
            for holding in optimized.sortedWeights {
                print("  \(pad(holding.symbol, 6)) \(holding.weight.formattedPercent())")
            }

            let weights = universe.map { optimized.weights[$0] ?? 0 }
            if let simulation = RiskAnalytics.monteCarlo(
                weights: weights,
                annualMeanReturns: means.map { $0 * 252 },
                annualCovariance: covariance.map { $0.map { $0 * 252 } },
                horizonDays: 252,
                simulations: 1_000,
                seed: 99
            ) {
                print("\nOne-year Monte Carlo (1,000 paths)")
                print("  Median return: \(simulation.medianTerminalReturn.formattedPercent())")
                print("  5th percentile: \(simulation.percentile5.formattedPercent())")
                print("  95th percentile: \(simulation.percentile95.formattedPercent())")
                print("  VaR 95%: \(simulation.valueAtRisk95.formattedPercent())")
                print("  Probability of loss: \(simulation.probabilityOfLoss.formattedPercent())")
            }
        }

        // MARK: Tax lots

        var ledger = TaxLotLedger()
        let now = Date()
        try ledger.buy(
            symbol: "AAPL",
            quantity: 100,
            price: 150,
            date: now.addingTimeInterval(-86_400 * 500)
        )
        try ledger.buy(
            symbol: "AAPL",
            quantity: 50,
            price: 180,
            date: now.addingTimeInterval(-86_400 * 100)
        )
        let sale = try ledger.sell(
            symbol: "AAPL",
            quantity: 120,
            price: 210,
            fees: 2,
            date: now,
            method: .fifo
        )
        print("\nTax-lot sale")
        print("  Sold 120 AAPL for \(sale.proceeds.formattedCurrency())")
        print("  Cost basis: \(sale.costBasis.formattedCurrency())")
        print("  Realized gain: \(sale.gain.formattedCurrency())")
        print("  Remaining position: \(ledger.position(symbol: "AAPL")?.quantity ?? 0) shares")

        // MARK: Alerts

        var alerts = AlertRuleEngine()
        alerts.add(AlertRule(
            symbol: "AAPL",
            condition: .crossesAbove,
            threshold: 200,
            cooldown: 0
        ))
        _ = alerts.evaluate([Quote(symbol: "AAPL", price: 195)])
        let events = alerts.evaluate([Quote(symbol: "AAPL", price: 201)])
        print("\nAlerts")
        for event in events {
            print("  \(event.message)")
        }

        // MARK: Screener

        let candidates = [
            ScreenCandidate(
                symbol: "AAPL",
                price: 201,
                volume: 12_000_000,
                sector: "Technology",
                metrics: ["rsi": 58, "momentum": 8, "volatility": 22, "priceToSMA": 1.04, "volumeRatio": 1.3]
            ),
            ScreenCandidate(
                symbol: "XYZ",
                price: 12,
                volume: 400_000,
                sector: "Energy",
                metrics: ["rsi": 82, "momentum": -4, "volatility": 65, "priceToSMA": 0.91, "volumeRatio": 0.6]
            ),
        ]
        let filter = ScreenFilter(
            minPrice: 20,
            minVolume: 1_000_000,
            maxRSI: 70,
            maxVolatility: 40,
            minPriceToSMA: 1.0
        )
        print("\nScreener")
        for result in ScreenerEngine.run(candidates: candidates, filter: filter) {
            print("  \(result.candidate.symbol): score \(String(format: "%.2f", result.score))")
        }
        let rejected = ScreenerEngine.evaluate(candidates[1], filter: filter)
        print("  Rejected XYZ: \(rejected.failures.joined(separator: "; "))")
    }

    private static func pad(_ value: String, _ width: Int) -> String {
        if value.count >= width { return String(value.prefix(width)) }
        return value + String(repeating: " ", count: width - value.count)
    }
}
