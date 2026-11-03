// MARK: - Regime Policy
import Foundation

public struct RegimePolicy {
    /// Rules for position sizing based on regime
    public struct PositionSizing {
        /// Base position size percentage
        let basePct: Double
        /// Bullish multiplier
        let bullishMultiplier: Double
        /// Bearish multiplier
        let bearishMultiplier: Double
        /// Volatile multiplier
        let volatileMultiplier: Double
        /// Sideways multiplier
        let sidewaysMultiplier: Double
        
        /// Calculate position size percentage for given regime
        /// - Parameter regime: Current market regime
        /// - Returns: Position size percentage
        func size(for regime: MarketRegime) -> Double {
            switch regime {
            case .bullish: return basePct * bullishMultiplier
            case .bearish: return basePct * bearishMultiplier
            case .volatile: return basePct * volatileMultiplier
            case .sideways: return basePct * sidewaysMultiplier
            case .unknown: return basePct
            }
        }
    }
    
    /// Rules for stop loss based on regime
    public struct StopLoss {
        let basePct: Double
        let bullishAdjustment: Double
        let bearishAdjustment: Double
        let volatileAdjustment: Double
        
        func stopLossPct(for regime: MarketRegime, basePct: Double) -> Double {
            switch regime {
            case .bullish: return basePct * (1.0 - bullishAdjustment)
            case .bearish: return basePct * (1.0 + bearishAdjustment)
            case .volatile: return basePct * (1.0 + volatileAdjustment)
            case .sideways: return basePct
            case .unknown: return basePct
            }
        }
    }
    
    /// Rules for take profit based on regime
    public struct TakeProfit {
        let basePct: Double
        let bullishTarget: Double
        let bearishTarget: Double
        
        func takeProfitPct(for regime: MarketRegime, basePct: Double) -> Double {
            switch regime {
            case .bullish: return basePct * bullishTarget
            case .bearish: return basePct * bearishTarget
            case .sideways, .volatile, .unknown: return basePct
            }
        }
    }
    
    /// Default conservative policy
    public static var conservative: RegimePolicy {
        RegimePolicy(
            positionSizing: PositionSizing(basePct: 1.0, bullishMultiplier: 1.2, bearishMultiplier: 0.6, volatileMultiplier: 0.4, sidewaysMultiplier: 0.8),
            stopLoss: StopLoss(basePct: 2.0, bullishAdjustment: 0.5, bearishAdjustment: 0.3, volatileAdjustment: 0.5),
            takeProfit: TakeProfit(basePct: 4.0, bullishTarget: 1.5, bearishTarget: 0.5)
        )
    }
    
    /// Default aggressive policy
    public static var aggressive: RegimePolicy {
        RegimePolicy(
            positionSizing: PositionSizing(basePct: 3.0, bullishMultiplier: 1.5, bearishMultiplier: 0.4, volatileMultiplier: 0.2, sidewaysMultiplier: 1.0),
            stopLoss: StopLoss(basePct: 1.0, bullishAdjustment: 0.2, bearishAdjustment: 0.1, volatileAdjustment: 0.3),
            takeProfit: TakeProfit(basePct: 8.0, bullishTarget: 2.0, bearishTarget: 0.3)
        )
    }
    
    /// Default balanced policy
    public static var balanced: RegimePolicy {
        RegimePolicy(
            positionSizing: PositionSizing(basePct: 2.0, bullishMultiplier: 1.3, bearishMultiplier: 0.7, volatileMultiplier: 0.5, sidewaysMultiplier: 0.9),
            stopLoss: StopLoss(basePct: 1.5, bullishAdjustment: 0.3, bearishAdjustment: 0.2, volatileAdjustment: 0.4),
            takeProfit: TakeProfit(basePct: 6.0, bullishTarget: 1.8, bearishTarget: 0.4)
        )
    }
    
    /// Position sizing configuration
    let positionSizing: PositionSizing
    /// Stop loss configuration
    let stopLoss: StopLoss
    /// Take profit configuration
    let takeProfit: TakeProfit
    
    /// Initialize with custom policy
    public init(
        positionSizing: PositionSizing = PositionSizing(basePct: 2.0, bullishMultiplier: 1.3, bearishMultiplier: 0.7, volatileMultiplier: 0.5, sidewaysMultiplier: 0.9),
        stopLoss: StopLoss = StopLoss(basePct: 1.5, bullishAdjustment: 0.3, bearishAdjustment: 0.2, volatileAdjustment: 0.4),
        takeProfit: TakeProfit = TakeProfit(basePct: 6.0, bullishTarget: 1.8, bearishTarget: 0.4)
    ) {
        self.positionSizing = positionSizing
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
    }
    
    /// Calculate recommended position size for regime
    /// - Parameter regime: Current market regime
    /// - Returns: Position size percentage
    func positionSize(for regime: MarketRegime) -> Double {
        positionSizing.size(for: regime)
    }
    
    /// Calculate recommended stop loss percentage for regime
    /// - Parameters:
    ///   - regime: Current market regime
    ///   - basePct: Base stop loss percentage
    /// - Returns: Stop loss percentage
    func stopLossPct(for regime: MarketRegime, basePct: Double = 2.0) -> Double {
        stopLoss.stopLossPct(for: regime, basePct: basePct)
    }
    
    /// Calculate recommended take profit percentage for regime
    /// - Parameters:
    ///   - regime: Current market regime
    ///   - basePct: Base take profit percentage
    /// - Returns: Take profit percentage
    func takeProfitPct(for regime: MarketRegime, basePct: Double = 4.0) -> Double {
        takeProfit.takeProfitPct(for: regime, basePct: basePct)
    }
}
