// MARK: - Regime Policy
import Foundation

public enum RegimePolicy {
    public static func allows(_ strategy: String, in regime: MarketRegime) -> Bool {
        // Implementation for regime-based strategy filtering
        return true
    }
    
    public static func riskPercent(score: Double, regime: MarketRegime) -> Double {
        // Implementation for risk percentage based on regime
        return 0.05
    }
    
    public static func stance(for regime: MarketRegime) -> (note: String, isBullish: Bool) {
        switch regime {
        case .bullish: return ("Bullish market conditions", true)
        case .bearish: return ("Bearish market conditions", false)
        case .neutral: return ("Neutral market conditions", false)
        case .highVolatility: return ("High volatility regime", false)
        case .lowVolatility: return ("Low volatility regime", true)
        }
    }
}
