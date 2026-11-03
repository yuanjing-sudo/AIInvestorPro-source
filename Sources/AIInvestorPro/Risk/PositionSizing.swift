// MARK: - Position Sizing Models
import Foundation

public enum PositionSizingMethod: String, CaseIterable {
    case fixedFraction = "fixed_fraction"
    case fixedDollar = "fixed_dollar"
    case kelly = "kelly"
    case volatilityWeighted = "volatility_weighted"
    case riskBased = "risk_based"
    case volatilityBreakout = "volatility_breakout"
}

// MARK: - Position Sizing Result
public struct PositionSizingResult {
    public let suggestedQuantity: Double
    public let suggestedPositionSize: Double // In currency
    public let riskAmount: Double
    public let positionPctPortfolio: Double
    public let method: PositionSizingMethod
    public let justification: String
    
    public init(
        suggestedQuantity: Double,
        suggestedPositionSize: Double,
        riskAmount: Double,
        positionPctPortfolio: Double,
        method: PositionSizingMethod,
        justification: String
    ) {
        self.suggestedQuantity = suggestedQuantity
        self.suggestedPositionSize = suggestedPositionSize
        self.riskAmount = riskAmount
        self.positionPctPortfolio = positionPctPortfolio
        self.method = method
        self.justification = justification
    }
}

// MARK: - Fixed Fraction Position Sizing
public struct FixedFractionSizing {
    let riskPctPortfolio: Double // % of portfolio to risk
    let stopLossPct: Double // % stop loss from entry
    
    public init(riskPctPortfolio: Double = 1.0, stopLossPct: Double = 2.0) {
        self.riskPctPortfolio = riskPctPortfolio
        self.stopLossPct = stopLossPct
    }
    
    /// Calculate position size using fixed fraction method
    /// - Parameters:
    ///   - entryPrice: Entry price
    ///   - stopPrice: Stop loss price
    ///   - accountSize: Total account size
    ///   - symbol: Symbol being traded
    /// - Returns: Position sizing result
    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        symbol: String
    ) -> PositionSizingResult {
        let riskAmount = accountSize * (riskPctPortfolio / 100.0)
        let priceRisk = abs(entryPrice - stopPrice)
        
        guard priceRisk > 0 else {
            return PositionSizingResult(
                suggestedQuantity: 0,
                suggestedPositionSize: 0,
                riskAmount: 0,
                positionPctPortfolio: 0,
                method: .fixedFraction,
                justification: "Invalid stop price - same as entry price"
            )
        }
        
        let quantity = riskAmount / priceRisk
        let positionSize = quantity * entryPrice
        let positionPct = (positionSize / accountSize) * 100.0
        
        let justification = "Risk $\(String(format: "%.2f", riskAmount)) at risk of $\(String(format: "%.2f", priceRisk)) per share = \(String(format: "%.2f", quantity)) shares"
        
        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: riskAmount,
            positionPctPortfolio: positionPct,
            method: .fixedFraction,
            justification: justification
        )
    }
}

// MARK: - Fixed Dollar Position Sizing
public struct FixedDollarSizing {
    let dollarAmount: Double // Fixed dollar amount to invest
    
    public init(dollarAmount: Double = 1000.0) {
        self.dollarAmount = dollarAmount
    }
    
    /// Calculate position size using fixed dollar method
    /// - Parameters:
    ///   - entryPrice: Entry price
    ///   - accountSize: Total account size
    ///   - symbol: Symbol being traded
    /// - Returns: Position sizing result
    public func calculate(
        entryPrice: Double,
        accountSize: Double,
        symbol: String
    ) -> PositionSizingResult {
        let quantity = dollarAmount / entryPrice
        let positionSize = dollarAmount
        let positionPct = (dollarAmount / accountSize) * 100.0
        
        let justification = "Fixed dollar investment of $\(String(format: "%.2f", dollarAmount)) at $\(String(format: "%.2f", entryPrice)) = \(String(format: "%.4f", quantity)) shares"
        
        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: dollarAmount,
            positionPctPortfolio: positionPct,
            method: .fixedDollar,
            justification: justification
        )
    }
}

// MARK: - Kelly Criterion Position Sizing
public struct KellySizing {
    let winRate: Double // Historical win rate (0-1)
    let winLossRatio: Double // Average win / average loss
    
    public init(winRate: Double, winLossRatio: Double) {
        self.winRate = max(0, min(1, winRate)) // Clamp to 0-1
        self.winLossRatio = winLossRatio
    }
    
    /// Calculate Kelly fraction: f = (p * b - q) / b
    /// where p = win rate, q = loss rate = 1-p, b = odds received (win/loss ratio)
    public var kellyFraction: Double {
        guard winLossRatio > 0 else { return 0 }
        let p = winRate
        let q = 1 - p
        let fraction = (p * winLossRatio - q) / winLossRatio
        return max(0, min(fraction, 1.0)) // Clamp to 0-1
    }
    
    /// Fractional Kelly - use half Kelly for safety
    public var fractionalKellyFraction: Double {
        kellyFraction / 2.0
    }
    
    /// Calculate position size using Kelly criterion
    /// - Parameters:
    ///   - entryPrice: Entry price
    ///   - stopPrice: Stop loss price
    ///   - accountSize: Total account size
    /// - Returns: Position sizing result
    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double
    ) -> PositionSizingResult {
        let fullKelly = kellyFraction
        let fractionalKelly = fractionalKellyFraction
        let useFraction = fullKelly > 0 ? fractionalKelly : 0.1 // Minimum 10% if Kelly positive
        
        let riskAmount = accountSize * useFraction
        let priceRisk = abs(entryPrice - stopPrice)
        
        guard priceRisk > 0 else {
            return PositionSizingResult(
                suggestedQuantity: 0,
                suggestedPositionSize: 0,
                riskAmount: 0,
                positionPctPortfolio: 0,
                method: .kelly,
                justification: "Invalid stop price - using minimum position"
            )
        }
        
        let quantity = riskAmount / priceRisk
        let positionSize = quantity * entryPrice
        let positionPct = (positionSize / accountSize) * 100.0
        
        let justification = "Kelly criterion: full=\(String(format: "%.1f%", fullKelly * 100))%, fractional=\(String(format: "%.1f%", fractionalKelly * 100))%, risking $\(String(format: "%.2f", riskAmount))"
        
        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: riskAmount,
            positionPctPortfolio: positionPct,
            method: .kelly,
            justification: justification
        )
    }
}

// MARK: - Volatility-Weighted Position Sizing
public struct VolatilityWeightedSizing {
    let volatilityPct: Double // Annualized volatility as percentage
    let targetVolatilityPct: Double // Target portfolio volatility
    let riskPctPortfolio: Double // % of portfolio to risk
    
    public init(
        volatilityPct: Double,
        targetVolatilityPct: Double = 15.0,
        riskPctPortfolio: Double = 1.0
    ) {
        self.volatilityPct = volatilityPct
        self.targetVolatilityPct = targetVolatilityPct
        self.riskPctPortfolio = riskPctPortfolio
    }
    
    /// Calculate position size adjusted for volatility
    /// - Parameters:
    ///   - entryPrice: Entry price
    ///   - stopPrice: Stop loss price
    ///   - accountSize: Total account size
    /// - Returns: Position sizing result
    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double
    ) -> PositionSizingResult {
        let riskAmount = accountSize * (riskPctPortfolio / 100.0)
        let priceRisk = abs(entryPrice - stopPrice)
        
        // Adjust for volatility - higher volatility = smaller position
        let volAdjustment = targetVolatilityPct / max(volatilityPct, 1.0)
        let adjustedRisk = riskAmount * volAdjustment
        
        guard priceRisk > 0 else {
            return PositionSizingResult(
                suggestedQuantity: 0,
                suggestedPositionSize: 0,
                riskAmount: 0,
                positionPctPortfolio: 0,
                method: .volatilityWeighted,
                justification: "Invalid stop price - using minimum position"
            )
        }
        
        let quantity = adjustedRisk / priceRisk
        let positionSize = quantity * entryPrice
        let positionPct = (positionSize / accountSize) * 100.0
        
        let justification = "Volatility-adjusted: vol=\(String(format: "%.1f%", volatilityPct))%, target=\(String(format: "%.1f%", targetVolatilityPct))%, risking $\(String(format: "%.2f", adjustedRisk))"
        
        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: adjustedRisk,
            positionPctPortfolio: positionPct,
            method: .volatilityWeighted,
            justification: justification
        )
    }
}

// MARK: - Risk-Based Position Sizing
public struct RiskBasedSizing {
    let maxRiskPct: Double // Maximum % capital at risk per trade
    let maxConcurrentTrades: Int // Max simultaneous positions
    let correlatedRiskPct: Double // Additional risk allowance for diversification
    
    public init(
        maxRiskPct: Double = 2.0,
        maxConcurrentTrades: Int = 5,
        correlatedRiskPct: Double = 0.5
    ) {
        self.maxRiskPct = maxRiskPct
        self.maxConcurrentTrades = maxConcurrentTrades
        self.correlatedRiskPct = correlatedRiskPct
    }
    
    /// Calculate position size based on risk parameters
    /// - Parameters:
    ///   - entryPrice: Entry price
    ///   - stopPrice: Stop loss price
    ///   - accountSize: Total account size
    ///   - concurrentTrades: Number of currently open positions
    /// - Returns: Position sizing result
    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        concurrentTrades: Int = 0
    ) -> PositionSizingResult {
        let maxRisk = accountSize * (maxRiskPct / 100.0)
        
        // Reduce risk if many concurrent trades
        let tradeFactor = Double(max(1, maxConcurrentTrades - concurrentTrades)) / Double(maxConcurrentTrades + 1)
        let adjustedMaxRisk = maxRisk * tradeFactor
        
        let priceRisk = abs(entryPrice - stopPrice)
        guard priceRisk > 0 else {
            return PositionSizingResult(
                suggestedQuantity: 0,
                suggestedPositionSize: 0,
                riskAmount: 0,
                positionPctPortfolio: 0,
                method: .riskBased,
                justification: "Invalid stop price"
            )
        }
        
        let quantity = adjustedMaxRisk / priceRisk
        let positionSize = quantity * entryPrice
        let positionPct = (positionSize / accountSize) * 100.0
        
        let justification = "Risk-based: max \(maxRiskPct)% risk, \(concurrentTrades) open trades, risking $\(String(format: "%.2f", adjustedMaxRisk))"
        
        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: adjustedMaxRisk,
            positionPctPortfolio: positionPct,
            method: .riskBased,
            justification: justification
        )
    }
}

// MARK: - Volatility Breakout Position Sizing
public struct VolatilityBreakoutSizing {
    let atrPct: Double // ATR as percentage of price
    let breakoutThreshold: Double // Minimum ATR % for full position
    let riskPctPortfolio: Double // % of portfolio to risk
    
    public init(
        atrPct: Double,
        breakoutThreshold: Double = 1.5,
        riskPctPortfolio: Double = 1.0
    ) {
        self.atrPct = atrPct
        self.breakoutThreshold = breakoutThreshold
        self.riskPctPortfolio = riskPctPortfolio
    }
    
    /// Calculate position size based on volatility breakout
    /// - Parameters:
    ///   - entryPrice: Entry price
    ///   - stopPrice: Stop loss price
    ///   - accountSize: Total account size
    /// - Returns: Position sizing result
    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        atrValue: Double? = nil
    ) -> PositionSizingResult {
        let riskAmount = accountSize * (riskPctPortfolio / 100.0)
        
        // Use ATR if provided, otherwise calculate from price difference
        let atr = atrValue ?? (abs(stopPrice - entryPrice) * 2.0) // Simplified
        let atrPctOfPrice = (atr / entryPrice) * 100.0
        
        // Scale position based on breakout strength
        let scale = atrPctOfPrice / breakoutThreshold
        let useScale = min(max(scale, 0.5), 2.0) // Clamp between 0.5 and 2.0
        
        let adjustedRisk = riskAmount * useScale
        let priceRisk = abs(entryPrice - stopPrice)
        
        guard priceRisk > 0 else {
            return PositionSizingResult(
                suggestedQuantity: 0,
                suggestedPositionSize: 0,
                riskAmount: 0,
                positionPctPortfolio: 0,
                method: .volatilityBreakout,
                justification: "Invalid stop price"
            )
        }
        
        let quantity = adjustedRisk / priceRisk
        let positionSize = quantity * entryPrice
        let positionPct = (positionSize / accountSize) * 100.0
        
        let justification = "Volatility breakout: ATR \(String(format: "%.2f%", atrPctOfPrice))%, scale \(String(format: "%.2f", useScale)), risking $\(String(format: "%.2f", adjustedRisk))"
        
        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: adjustedRisk,
            positionPctPortfolio: positionPct,
            method: .volatilityBreakout,
            justification: justification
        )
    }
}

// MARK: - Position Sizing Factory
public enum PositionSizingFactory {
    /// Create position sizer based on method
    /// - Parameters:
    ///   - method: Sizing method
    ///   - parameters: Method-specific parameters
    /// - Returns: Position sizing object
    public static func createSizer(
        _ method: PositionSizingMethod,
        parameters: [String: Any] = [:]
    ) -> any PositionSizing {
        switch method {
        case .fixedFraction:
            let risk = parameters["riskPct"] as? Double ?? 1.0
            let stopLoss = parameters["stopLossPct"] as? Double ?? 2.0
            return FixedFractionSizing(riskPctPortfolio: risk, stopLossPct: stopLoss)
            
        case .fixedDollar:
            let amount = parameters["dollarAmount"] as? Double ?? 1000.0
            return FixedDollarSizing(dollarAmount: amount)
            
        case .kelly:
            let winRate = parameters["winRate"] as? Double ?? 0.5
            let winLossRatio = parameters["winLossRatio"] as? Double ?? 2.0
            return KellySizing(winRate: winRate, winLossRatio: winLossRatio)
            
        case .volatilityWeighted:
            let volatility = parameters["volatilityPct"] as? Double ?? 15.0
            let targetVol = parameters["targetVolatility"] as? Double ?? 15.0
            let risk = parameters["riskPct"] as? Double ?? 1.0
            return VolatilityWeightedSizing(volatilityPct: volatility, targetVolatilityPct: targetVol, riskPctPortfolio: risk)
            
        case .riskBased:
            let maxRisk = parameters["maxRiskPct"] as? Double ?? 2.0
            let maxTrades = parameters["maxConcurrentTrades"] as? Int ?? 5
            let correlated = parameters["correlatedRisk"] as? Double ?? 0.5
            return RiskBasedSizing(maxRiskPct: maxRisk, maxConcurrentTrades: maxTrades, correlatedRiskPct: correlated)
            
        case .volatilityBreakout:
            let atrPct = parameters["atrPct"] as? Double ?? 2.0
            let threshold = parameters["breakoutThreshold"] as? Double ?? 1.5
            let risk = parameters["riskPct"] as? Double ?? 1.0
            return VolatilityBreakoutSizing(atrPct: atrPct, breakoutThreshold: threshold, riskPctPortfolio: risk)
            
        default:
            return FixedFractionSizing()
        }
    }
}

// MARK: - Position Sizing Protocol
public protocol PositionSizing {
    func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        symbol: String
    ) -> PositionSizingResult
}
// MARK: - Position Sizing Protocol Conformances

extension FixedFractionSizing: PositionSizing {
    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        symbol: String
    ) -> PositionSizingResult {
        let riskAmount = accountSize * (riskPctPortfolio / 100.0)
        let priceRisk = abs(entryPrice - stopPrice)
        
        guard priceRisk > 0 else {
            return PositionSizingResult(
                suggestedQuantity: 0,
                suggestedPositionSize: 0,
                riskAmount: 0,
                positionPctPortfolio: 0,
                method: .fixedFraction,
                justification: "Invalid stop price - same as entry price"
            )
        }
        
        let quantity = riskAmount / priceRisk
        let positionSize = quantity * entryPrice
        let positionPct = (positionSize / accountSize) * 100.0
        
        let justification = "Risk $\(String(format: "%.2f", riskAmount)) at risk of $\(String(format: "%.2f", priceRisk)) per share = \(String(format: "%.2f", quantity)) shares"
        
        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: riskAmount,
            positionPctPortfolio: positionPct,
            method: .fixedFraction,
            justification: justification
        )
    }
}

extension FixedDollarSizing: PositionSizing {
    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        symbol: String
    ) -> PositionSizingResult {
        let quantity = dollarAmount / entryPrice
        let positionSize = dollarAmount
        let positionPct = (dollarAmount / accountSize) * 100.0
        
        let justification = "Fixed dollar investment of $\(String(format: "%.2f", dollarAmount)) at $\(String(format: "%.2f", entryPrice)) = \(String(format: "%.4f", quantity)) shares"
        
        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: dollarAmount,
            positionPctPortfolio: positionPct,
            method: .fixedDollar,
            justification: justification
        )
    }
}

extension KellySizing: PositionSizing {
    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double
    ) -> PositionSizingResult {
        let fullKelly = kellyFraction
        let fractionalKelly = fractionalKellyFraction
        let useFraction = fullKelly > 0 ? fractionalKelly : 0.1
        
        let riskAmount = accountSize * useFraction
        let priceRisk = abs(entryPrice - stopPrice)
        
        guard priceRisk > 0 else {
            return PositionSizingResult(
                suggestedQuantity: 0,
                suggestedPositionSize: 0,
                riskAmount: 0,
                positionPctPortfolio: 0,
                method: .kelly,
                justification: "Invalid stop price - using minimum position"
            )
        }
        
        let quantity = riskAmount / priceRisk
        let positionSize = quantity * entryPrice
        let positionPct = (positionSize / accountSize) * 100.0
        
        let justification = "Kelly criterion: full=\(String(format: "%.1f%", fullKelly * 100))%, fractional=\(String(format: "%.1f%", fractionalKelly * 100))%, risking $\(String(format: "%.2f", riskAmount))"
        
        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: riskAmount,
            positionPctPortfolio: positionPct,
            method: .kelly,
            justification: justification
        )
    }
}

extension VolatilityWeightedSizing: PositionSizing {
    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double
    ) -> PositionSizingResult {
        let riskAmount = accountSize * (riskPctPortfolio / 100.0)
        let priceRisk = abs(entryPrice - stopPrice)
        
        let volAdjustment = targetVolatilityPct / max(volatilityPct, 1.0)
        let adjustedRisk = riskAmount * volAdjustment
        
        guard priceRisk > 0 else {
            return PositionSizingResult(
                suggestedQuantity: 0,
                suggestedPositionSize: 0,
                riskAmount: 0,
                positionPctPortfolio: 0,
                method: .volatilityWeighted,
                justification: "Invalid stop price"
            )
        }
        
        let quantity = adjustedRisk / priceRisk
        let positionSize = quantity * entryPrice
        let positionPct = (positionSize / accountSize) * 100.0
        
        let justification = "Volatility-adjusted: vol=\(String(format: "%.1f%", volatilityPct))%, target=\(String(format: "%.1f%", targetVolatilityPct))%, risking $\(String(format: "%.2f", adjustedRisk))"
        
        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: adjustedRisk,
            positionPctPortfolio: positionPct,
            method: .volatilityWeighted,
            justification: justification
        )
    }
}

extension RiskBasedSizing: PositionSizing {
    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        concurrentTrades: Int = 0
    ) -> PositionSizingResult {
        let maxRisk = accountSize * (maxRiskPct / 100.0)
        
        let tradeFactor = Double(max(1, maxConcurrentTrades - concurrentTrades)) / Double(maxConcurrentTrades + 1)
        let adjustedMaxRisk = maxRisk * tradeFactor
        
        let priceRisk = abs(entryPrice - stopPrice)
        guard priceRisk > 0 else {
            return PositionSizingResult(
                suggestedQuantity: 0,
                suggestedPositionSize: 0,
                riskAmount: 0,
                positionPctPortfolio: 0,
                method: .riskBased,
                justification: "Invalid stop price"
            )
        }
        
        let quantity = adjustedMaxRisk / priceRisk
        let positionSize = quantity * entryPrice
        let positionPct = (positionSize / accountSize) * 100.0
        
        let justification = "Risk-based: max \(maxRiskPct)% risk, \(concurrentTrades) open trades, risking $\(String(format: "%.2f", adjustedMaxRisk))"
        
        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: adjustedMaxRisk,
            positionPctPortfolio: positionPct,
            method: .riskBased,
            justification: justification
        )
    }
}

extension VolatilityBreakoutSizing: PositionSizing {
    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        atrValue: Double? = nil
    ) -> PositionSizingResult {
        let riskAmount = accountSize * (riskPctPortfolio / 100.0)
        
        let atr = atrValue ?? (abs(stopPrice - entryPrice) * 2.0)
        let atrPctOfPrice = (atr / entryPrice) * 100.0
        
        let scale = atrPctOfPrice / breakoutThreshold
        let useScale = min(max(scale, 0.5), 2.0)
        
        let adjustedRisk = riskAmount * useScale
        let priceRisk = abs(entryPrice - stopPrice)
        
        guard priceRisk > 0 else {
            return PositionSizingResult(
                suggestedQuantity: 0,
                suggestedPositionSize: 0,
                riskAmount: 0,
                positionPctPortfolio: 0,
                method: .volatilityBreakout,
                justification: "Invalid stop price"
            )
        }
        
        let quantity = adjustedRisk / priceRisk
        let positionSize = quantity * entryPrice
        let positionPct = (positionSize / accountSize) * 100.0
        
        let justification = "Volatility breakout: ATR \(String(format: "%.2f%", atrPctOfPrice))%, scale \(String(format: "%.2f", useScale)), risking $\(String(format: "%.2f", adjustedRisk))"
        
        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: adjustedRisk,
            positionPctPortfolio: positionPct,
            method: .volatilityBreakout,
            justification: justification
        )
    }
}
