// MARK: - Stock Analyzer
import Foundation

public struct StockAnalyzer {
    /// Analyze a snapshot and return comprehensive results
    public func analyze(_ snapshot: MarketSnapshot, regime: Market.Regime? = nil) -> AnalysisResult {
        let regime = regime ?? MarketRegime.detect([snapshot])
        let indicators = TechnicalIndicators.calculate(from: snapshot.closes)
        
        // Calculate various metrics
        let totalReturn = (snapshot.closes.last! / snapshot.closes.first!) - 1
        let recentReturn = (snapshot.closes.last! / snapshot.closes[snapshot.closes.count - min(20, snapshot.closes.count)]) - 1
        
        // Volatility (annualized approximate)
        let returns = zip(snapshot.closes.dropFirst(), snapshot.closes.dropLast()).map { $0 / $1 - 1 }
        let meanReturn = returns.reduce(0, +) / Double(returns.count)
        let variance = returns.map { pow($0 - meanReturn, 2) }.reduce(0, +) / Double(returns.count - 1)
        let annualizedVol = sqrt(Double(252) * variance) * 100
        
        // Moving averages
        let sma20 = snapshot.closes.suffix(20).reduce(0, +) / 20
        let sma50 = snapshot.closes.count >= 50 ? snapshot.closes.suffix(50).reduce(0, +) / 50 : snapshot.cloves.last!
        let ema12 = calculateEMA(snapshot.closes, period: 12)
        let ema26 = calculateEMA(snapshot.closes, period: 26)
        
        // MACD
        let macd = ema12 - ema26
        let macdSignal = (snapshot.closes.last! - ema26) / ema26 * 100
        
        // RSI
        let rsi = RSI.calculate(from: snapshot.closes)
        
        // Support/Resistance levels
        let high52 = snapshot.closes.suffix(252).max() ?? snapshot.closes.last!
        let low52 = snapshot.closes.suffix(252).min() ?? snapshot.closes.last!
        
        return AnalysisResult(
            symbol: snapshot.symbol,
            currentPrice: snapshot.currentPrice,
            totalReturn: totalReturn,
            recentReturn: recentReturn,
            annualizedVolatility: annualizedVol,
            sma20: sma20,
            sma50: sma50,
            ema12: ema12,
            ema26: ema26,
            macd: macd,
            macdSignal: macdSignal,
            rsi: rsi,
            supportLevel: snapshot.low52 * 0.98, // Approximate
            resistanceLevel: snapshot.high52 * 1.02, // Approximate
            regime: regime,
            technical: TechnicalSignal(
                rsi: rsi,
                macd: macd,
                macdSignal: macdSignal,
                aboveSMA20: snapshot.closes.last! > sma20,
                aboveSMA50: snapshot.closes.last! > sma50
            )
        )
    }
    
    // Calculate exponential moving average
    private func calculateEMA(_ prices: [Double], period: Int) -> Double {
        guard prices.count >= period else { return prices.last ?? 0 }
        let multiplier = 2.0 / (Double(period) + 1)
        var ema = prices[0]
        for i in 1..<prices.count {
            ema = (prices[i] - ema) * multiplier + ema
        }
        return ema
    }
    
    // Calculate RSI
    private func RSI(_ prices: [Double], period: Int = 14) -> Double {
        guard prices.count > period else { return 50.0 }
        let changes = zip(prices.dropFirst(), prices.dropLast()).map { $1 - $0 }
        let gains = gains.filter { $0 > 0 }.count
        let losses = losses.filter { $0 < 0 }.count
        let averageGain = gains.reduce(0, +) / Double(gains.count)
        let averageLoss = abs(losses.filter { $0 < 0 }.reduce(0, +)) / Double(losses.count)
        let rs = averageGain / averageLoss
        return 100 - (100 / (1 + rs))
    }
}
