// MARK: - Market Regime
import Foundation

public enum MarketRegime: String, CaseIterable, Codable {
    case bullish = "bull"
    case bearish = "bear"
    case sideways = "sideways"
    case volatile = "volatile"
    case unknown = "unknown"
    
    public var description: String {
        rawValue.capitalized
    }
    
    /// Detect regime from market snapshots
    /// - Parameter snapshots: Market snapshots to analyze
    /// - Returns: Detected regime
    public static func detect(_ snapshots: [MarketSnapshot]) -> MarketRegime {
        guard !snapshots.isEmpty else { return .unknown }
        
        // Use multiple indicators for regime detection
        let recentSnapshots = snapshots.suffix(min(20, snapshots.count))
        
        // Calculate price trend
        let firstPrice = recentSnapshots.first?.closes.first ?? 0
        let lastPrice = recentSnapshots.last?.closes.last ?? 0
        
        guard firstPrice > 0 else { return .unknown }
        let priceChange = (lastPrice - firstPrice) / firstPrice
        
        // Calculate volatility
        let returns = zip(recentSnapshots.dropFirst().map { $0.closes.last! }, 
                          recentSnapshots.dropLast().map { $0.closes.last! })
        .map { $1 / $0 - 1 }
        let avgReturn = returns.reduce(0, +) / Double(returns.count)
        let returnVariance = returns.map { pow($0 - avgReturn, 2) }.reduce(0, +) / Double(returns.count)
        let volatility = sqrt(returnVariance) * 100
        
        // Calculate RSI
        let allCloses = recentSnapshots.flatMap { $0.closes }
        let rsi = calculateRSI(allCloses, period: 14)
        
        // Determine regime
        if priceChange > 0.05 && volatility < 20 && rsi > 55 {
            return .bullish
        } else if priceChange < -0.05 && volatility < 20 && rsi < 45 {
            return .bearish
        } else if volatility > 30 {
            return .volatile
        } else {
            return .sideways
        }
    }
    
    /// Calculate RSI from price array
    private static func calculateRSI(_ prices: [Double], period: Int) -> Double {
        guard prices.count > period else { return 50.0 }
        let changes = zip(prices.dropFirst(), prices.dropLast()).map { $1 - $0 }
        let gains = changes.filter { $0 > 0 }
        let losses = abs(changes.filter { $0 < 0 })
        let avgGain = gains.isEmpty ? 0 : gains.reduce(0, +) / Double(gains.count)
        let avgLoss = losses.isEmpty ? 1 : losses.reduce(0, +) / Double(losses.count)
        let rs = avgLoss == 0 ? 100 : avgGain / avgLoss
        return 100 - (100 / (1 + rs))
    }
    
    /// Get regime color for UI
    var uiColor: String {
        switch self {
        case .bullish: return "🟢"
        case .bearish: return "🔴"
        case .sideways: return "🟡"
        case .volatile: return "🟣"
        case .unknown: return "⚪"
        }
    }
}
