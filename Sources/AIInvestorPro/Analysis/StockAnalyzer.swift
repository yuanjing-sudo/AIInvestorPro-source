// MARK: - Stock Analyzer
import Foundation

public struct StockAnalyzer {
    /// Analyze a snapshot and return comprehensive results.
    public func analyze(_ snapshot: MarketSnapshot, regime explicitRegime: MarketRegime? = nil) -> AnalysisResult {
        let regime = explicitRegime ?? MarketRegime.detect([snapshot]).regime
        let indicators = TechnicalIndicators.calculate(
            from: snapshot.closes,
            high: snapshot.highs,
            low: snapshot.lows,
            volume: snapshot.volumes
        )

        guard let first = snapshot.closes.first,
              let last = snapshot.closes.last,
              first > 0, last > 0 else {
            return AnalysisResult(
                symbol: snapshot.symbol,
                currentPrice: snapshot.currentPrice,
                totalReturn: 0,
                recentReturn: 0,
                annualizedVolatility: 0,
                sma20: 0,
                sma50: 0,
                ema12: 0,
                ema26: 0,
                macd: 0,
                macdSignal: 0,
                rsi: 50,
                supportLevel: snapshot.currentPrice,
                resistanceLevel: snapshot.currentPrice,
                regime: regime,
                technical: TechnicalSignal(
                    rsi: 50,
                    macd: 0,
                    macdSignal: 0,
                    aboveSMA20: false,
                    aboveSMA50: false
                )
            )
        }

        let totalReturn = (last / first - 1) * 100
        let recentCount = min(20, snapshot.closes.count)
        let recentBase = snapshot.closes[snapshot.closes.count - recentCount]
        let recentReturn = recentBase > 0 ? (last / recentBase - 1) * 100 : 0

        let returns = zip(snapshot.closes.dropFirst(), snapshot.closes.dropLast()).map { $0.0 / $0.1 - 1 }
        let meanReturn = returns.mean
        let variance = returns.count > 1
            ? returns.reduce(0) { $0 + pow($1 - meanReturn, 2) } / Double(returns.count - 1)
            : 0
        let annualizedVolatility = sqrt(max(0, variance * 252)) * 100

        let sma20 = snapshot.closes.suffix(min(20, snapshot.closes.count)).reduce(0, +)
            / Double(min(20, snapshot.closes.count))
        let sma50 = snapshot.closes.suffix(min(50, snapshot.closes.count)).reduce(0, +)
            / Double(min(50, snapshot.closes.count))

        let high52 = snapshot.closes.suffix(252).max() ?? last
        let low52 = snapshot.closes.suffix(252).min() ?? last

        return AnalysisResult(
            symbol: snapshot.symbol,
            currentPrice: snapshot.currentPrice,
            totalReturn: totalReturn,
            recentReturn: recentReturn,
            annualizedVolatility: annualizedVolatility,
            sma20: sma20,
            sma50: sma50,
            ema12: indicators.ema12,
            ema26: indicators.ema26,
            macd: indicators.macd,
            macdSignal: indicators.macdSignal,
            rsi: indicators.rsi,
            supportLevel: low52 * 0.98,
            resistanceLevel: high52 * 1.02,
            regime: regime,
            technical: TechnicalSignal(
                rsi: indicators.rsi,
                macd: indicators.macd,
                macdSignal: indicators.macdSignal,
                aboveSMA20: last > sma20,
                aboveSMA50: last > sma50
            )
        )
    }
}
