// MARK: - Regime Policy
import Foundation

public struct RegimePolicy {
    /// Position sizing rules
    public struct PositionSizing {
        let basePct: Double
        let bullishMultiplier: Double
        let bearishMultiplier: Double
        let volatileMultiplier: Double
        let sidewaysMultiplier: Double
        
        public init(
            basePct: Double = 2.0,
            bullishMultiplier: Double = 1.3,
            bearishMultiplier: Double = 0.7,
            volatileMultiplier: Double = 0.5,
            sidewaysMultiplier: Double = 0.9
        ) {
            self.basePct = basePct
            self.bullishMultiplier = bullishMultiplier
            self.bearishMultiplier = bearishMultiplier
            self.volatileMultiplier = volatileMultiplier
            self.sidewaysMultiplier = sidewaysMultiplier
        }
        
        func size(for regime: MarketRegime) -> Double {
            switch regime {
            case .bullish: return basePct * bullishMultiplier
            case .bearish: return basePct * bearishMultiplier
            case .volatile: return basePct * volatileMultiplier
            case .sideways: return basePct * sidewaysMultiplier
            case .unknown: return basePct
            case .accumulation: return basePct * 1.1 // Slightly larger positions
            case .distribution: return basePct * 0.9 // Slightly smaller positions
            }
        }
    }
    
    /// Stop loss rules
    public struct StopLoss {
        let basePct: Double
        let bullishAdjustment: Double
        let bearishAdjustment: Double
        let volatileAdjustment: Double
        
        public init(
            basePct: Double = 1.5,
            bullishAdjustment: Double = 0.3,
            bearishAdjustment: Double = 0.2,
            volatileAdjustment: Double = 0.4
        ) {
            self.basePct = basePct
            self.bullishAdjustment = bullishAdjustment
            self.bearishAdjustment = bearishAdjustment
            self.volatileAdjustment = volatileAdjustment
        }
        
        func stopLossPct(for regime: MarketRegime, basePct: Double = 2.0) -> Double {
            switch regime {
            case .bullish: return basePct * (1.0 - bullishAdjustment)
            case .bearish: return basePct * (1.0 + bearishAdjustment)
            case .volatile: return basePct * (1.0 + volatileAdjustment)
            case .sideways, .unknown: return basePct
            case .accumulation: return basePct * 0.95 // Tighter stops when accumulating
            case .distribution: return basePct * 0.95 // Tighter stops when distributing
            }
        }
    }
    
    /// Take profit rules
    public struct TakeProfit {
        let basePct: Double
        let bullishTarget: Double
        let bearishTarget: Double
        
        public init(
            basePct: Double = 6.0,
            bullishTarget: Double = 1.8,
            bearishTarget: Double = 0.4
        ) {
            self.basePct = basePct
            self.bullishTarget = bullishTarget
            self.bearishTarget = bearishTarget
        }
        
        func takeProfitPct(for regime: MarketRegime, basePct: Double = 4.0) -> Double {
            switch regime {
            case .bullish: return basePct * bullishTarget
            case .bearish: return basePct * bearishTarget
            case .sideways, .volatile, .unknown: return basePct
            case .accumulation: return basePct * 1.2 // Larger targets when accumulating
            case .distribution: return basePct * 0.8 // Smaller targets when distributing
            }
        }
    }
    
    /// Default conservative policy
    public static var conservative: RegimePolicy {
        RegimePolicy(
            positionSizing: PositionSizing(),
            stopLoss: StopLoss(),
            takeProfit: TakeProfit()
        )
    }
    
    /// Default aggressive policy
    public static var aggressive: RegimePolicy {
        RegimePolicy(
            positionSizing: PositionSizing(
                basePct: 3.0,
                bullishMultiplier: 1.5,
                bearishMultiplier: 0.4,
                volatileMultiplier: 0.2,
                sidewaysMultiplier: 1.0
            ),
            stopLoss: StopLoss(
                basePct: 1.0,
                bullishAdjustment: 0.2,
                bearishAdjustment: 0.1,
                volatileAdjustment: 0.3
            ),
            takeProfit: TakeProfit(
                basePct: 8.0,
                bullishTarget: 2.0,
                bearishTarget: 0.3
            )
        )
    }
    
    /// Default balanced policy
    public static var balanced: RegimePolicy {
        RegimePolicy(
            positionSizing: PositionSizing(
                basePct: 2.0,
                bullishMultiplier: 1.3,
                bearishMultiplier: 0.7,
                volatileMultiplier: 0.5,
                sidewaysMultiplier: 0.9
            ),
            stopLoss: StopLoss(
                basePct: 1.5,
                bullishAdjustment: 0.3,
                bearishAdjustment: 0.2,
                volatileAdjustment: 0.4
            ),
            takeProfit: TakeProfit(
                basePct: 6.0,
                bullishTarget: 1.8,
                bearishTarget: 0.4
            )
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
        positionSizing: PositionSizing = PositionSizing(),
        stopLoss: StopLoss = StopLoss(),
        takeProfit: TakeProfit = TakeProfit()
    ) {
        self.positionSizing = positionSizing
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
    }
    
    /// Calculate recommended position size for regime
    /// - Parameter regime: Current market regime
    /// - Returns: Position size percentage
    public func positionSize(for regime: MarketRegime) -> Double {
        positionSizing.size(for: regime)
    }
    
    /// Calculate recommended stop loss percentage for regime
    /// - Parameters:
    ///   - regime: Current market regime
    ///   - basePct: Base stop loss percentage
    /// - Returns: Stop loss percentage
    public func stopLossPct(for regime: MarketRegime, basePct: Double = 2.0) -> Double {
        stopLoss.stopLossPct(for: regime, basePct: basePct)
    }
    
    /// Calculate recommended take profit percentage for regime
    /// - Parameters:
    ///   - regime: Current market regime
    ///   - basePct: Base take profit percentage
    /// - Returns: Take profit percentage
    public func takeProfitPct(for regime: MarketRegime, basePct: Double = 4.0) -> Double {
        takeProfit.takeProfitPct(for: regime, basePct: basePct)
    }
}
