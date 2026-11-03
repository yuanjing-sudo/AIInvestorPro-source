// MARK: - Screener
import Foundation

public struct Screener {
    /// Scan all snapshots and rank by composite score
    public static func scanAll(_ snapshots: [MarketSnapshot], horizonSetting: Int) -> [SymbolScan] {
        // Scan with our enhanced logic
        var scanned: [SymbolScan] = []
        
        for snapshot in snapshots.prefix(horizonSetting) { // Limit for performance
            let scan = scan(snapshot, regime: MarketRegime.bullish)
            scanned.append(scan)
        }
        
        // Combine and rank by composite score
        // Remove duplicates by symbol
        let unique = Dictionary(uniqueKeysWithValues: scanned.map { ($0.symbol, $0) }).values.map { $0 }
        // Sort by composite score descending
        return unique.sorted { $0.composite > $1.composite }
    }
    
    /// Screen snapshots based on technical criteria
    public static func scan(_ snapshot: MarketSnapshot, horizon: Int) -> SymbolScan {
        let indicators = TechnicalIndicators.calculate(from: snapshot.closes, high: snapshot.highs, low: snapshot.lows, volume: snapshot.volumes)
        let regime = MarketRegime.detect([snapshot])
        
        // Momentum score
        let priceChange = (snapshot.closes.last! - snapshot.closes[snapshot.closes.count - min(horizon, snapshot.closes.count)]) / abs(snapshot.closes[snapshot.closes.count - min(horizon, snapshot.closes.count)])
        let momentumScore = priceChange * 100
        
        // RSI filter
        let rsi = indicators.rsi
        let rsiFilter = rsi > 30 && rsi < 70 // Not overbought/oversold
        
        // Trend filter
        let trendUp = snapshot.closes.last! > snapshot.closes[snapshot.closes.count - min(horizon, 20)]
        
        if rsiFilter && trendUp {
            // Calculate composite score
            let composite = (momentumScore * 0.6) + (rsi / 200.0 * 40.0)
            let scan = SymbolScan(
                symbol: snapshot.symbol,
                forecast: Forecast(predictedReturn: momentumScore, predictedPrice: snapshot.closes.last!, horizonBars: horizon),
                composite: composite,
                recommendation: momentumScore > 0.05 ? .buy : .sell,
                reasons: ["Momentum: \(String(format: "%.2f", momentumScore))%", "RSI: \(String(format: "%.1f", rsi))"],
                detectedAt: Date()
            )
            return scan
        }
        
        // Return neutral scan even if filters don't pass
        return SymbolScan(
            symbol: snapshot.symbol,
            forecast: Forecast(predictedReturn: 0, predictedPrice: snapshot.closes.last!, horizonBars: horizon),
            composite: 0,
            recommendation: .hold,
            reasons: ["RSI: \(String(format: "%.1f", rsi))", "Trend: \(trendUp ? "up" : "down")"],
            detectedAt: Date()
        )
    }
}

// MARK: - Extension for MarketSnapshot compatibility
extension MarketSnapshot {
    var symbolKey: String { symbol }
}
