// MARK: - Screener
import Foundation

public struct Screener {
    /// Scan all snapshots and rank by composite score. The best scan per symbol
    /// wins, so duplicate symbols never crash dictionary construction.
    public static func scanAll(_ snapshots: [MarketSnapshot], horizonSetting: Int) -> [SymbolScan] {
        guard !snapshots.isEmpty else { return [] }
        let horizon = max(1, horizonSetting)
        let scans = snapshots.map { scan($0, horizon: horizon) }

        var bestBySymbol: [String: SymbolScan] = [:]
        for scan in scans {
            if let existing = bestBySymbol[scan.symbol] {
                if scan.composite > existing.composite {
                    bestBySymbol[scan.symbol] = scan
                }
            } else {
                bestBySymbol[scan.symbol] = scan
            }
        }
        return bestBySymbol.values.sorted { $0.composite > $1.composite }
    }

    /// Screen one snapshot based on technical criteria.
    public static func scan(_ snapshot: MarketSnapshot, horizon: Int) -> SymbolScan {
        guard let last = snapshot.closes.last, last != 0 else {
            return SymbolScan(
                symbol: snapshot.symbol,
                forecast: Forecast(predictedReturn: 0, predictedPrice: 0, horizonBars: max(1, horizon)),
                composite: 0,
                recommendation: .hold,
                reasons: ["No price history"],
                detectedAt: Date()
            )
        }

        let indicators = TechnicalIndicators.calculate(
            from: snapshot.closes,
            high: snapshot.highs,
            low: snapshot.lows,
            volume: snapshot.volumes
        )
        guard snapshot.closes.count >= 2 else {
            return SymbolScan(
                symbol: snapshot.symbol,
                forecast: Forecast(predictedReturn: 0, predictedPrice: last, horizonBars: 1),
                composite: 0,
                recommendation: .hold,
                reasons: ["Insufficient history"],
                detectedAt: Date()
            )
        }
        let safeHorizon = max(1, min(horizon, snapshot.closes.count - 1))

        let previous = snapshot.closes[snapshot.closes.count - 1 - safeHorizon]
        let priceChange = previous != 0 ? (last - previous) / abs(previous) : 0
        let momentumScore = priceChange * 100

        let rsi = indicators.rsi
        let rsiFilter = rsi > 30 && rsi < 70
        let trendPeriod = min(20, snapshot.closes.count - 1)
        let trendPrevious = snapshot.closes[snapshot.closes.count - 1 - trendPeriod]
        let trendUp = last > trendPrevious

        if rsiFilter && trendUp {
            let composite = momentumScore * 0.6 + rsi / 200.0 * 40.0
            return SymbolScan(
                symbol: snapshot.symbol,
                forecast: Forecast(
                    predictedReturn: momentumScore,
                    predictedPrice: last * (1 + priceChange),
                    horizonBars: safeHorizon
                ),
                composite: composite,
                recommendation: momentumScore > 5 ? .buy : .hold,
                reasons: [
                    "Momentum: \(String(format: "%.2f", momentumScore))%",
                    "RSI: \(String(format: "%.1f", rsi))"
                ],
                detectedAt: Date()
            )
        }

        return SymbolScan(
            symbol: snapshot.symbol,
            forecast: Forecast(predictedReturn: 0, predictedPrice: last, horizonBars: safeHorizon),
            composite: 0,
            recommendation: .hold,
            reasons: [
                "RSI: \(String(format: "%.1f", rsi))",
                "Trend: \(trendUp ? "up" : "down")"
            ],
            detectedAt: Date()
        )
    }
}

// MARK: - Extension for MarketSnapshot compatibility
extension MarketSnapshot {
    var symbolKey: String { symbol }
}
