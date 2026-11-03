// MARK: - Screener
import Foundation

public struct Screener {
    /// Scan all snapshots and rank by composite score
    public static func scanAll(_ snapshots: [MarketSnapshot], horizonSetting: Int) -> [SymbolScan] {
        // Use existing scanner for universe
        let scanned = Scanner.scanAll(snapshots, horizonSetting: horizonSetting)
        
        // Also scan with our enhanced logic
        var enhanced: [SymbolScan] = []
        for snapshot in snapshots.prefix(20) { // Limit for performance
            let scan = Scanner.scan(snapshot, regime: MarketRegime.bullish)
            enhanced.append(scan)
        }
        
        // Combine and rank by composite score
        var allScans: [SymbolScan] = scanned + enhanced
        // Remove duplicates by symbol
        let unique = Dictionary(uniqueKeysWithValues: allScans.map { ($0.symbol, $0) }).values.map { $0 }
        // Sort by composite score descending
        return unique.sorted { $0.composite > $1.composite }
    }
    
    /// Screen snapshots based on technical criteria
    public static func scan(_ snapshots: [MarketSnapshot], horizon: Int) -> [SymbolScan] {
        var results: [SymbolScan] = []
        
        for snapshot in snapshots where snapshot.closes.count >= 20 {
            let indicators = TechnicalIndicators.calculate(from: snapshot.closes)
            let regime = MarketRegime.detect(snapshots)
            
            // Momentum score
            let priceChange = (snapshot.closes.last! - snapshot.closes[snapshot.closes.count - horizon]) / abs(snapshot.closes[snapshot.closes.count - horizon])
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
                results.append(scan)
            }
        }
        return results
    }
}
