// MARK: - Position Sizing Models
import Foundation

public enum PositionSizingMethod: String, CaseIterable, Sendable, Equatable {
    case fixedFraction = "fixed_fraction"
    case fixedDollar = "fixed_dollar"
    case kelly = "kelly"
    case volatilityWeighted = "volatility_weighted"
    case riskBased = "risk_based"
    case volatilityBreakout = "volatility_breakout"
}

public struct PositionSizingResult: Sendable, Equatable {
    public let suggestedQuantity: Double
    public let suggestedPositionSize: Double
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

public protocol PositionSizing {
    func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        symbol: String
    ) -> PositionSizingResult
}

private func percentages(_ value: Double) -> String {
    String(format: "%.2f%%", value)
}

private func invalidStop(
    method: PositionSizingMethod
) -> PositionSizingResult {
    PositionSizingResult(
        suggestedQuantity: 0,
        suggestedPositionSize: 0,
        riskAmount: 0,
        positionPctPortfolio: 0,
        method: method,
        justification: "Invalid stop price - same as entry price"
    )
}

// MARK: - Fixed Fraction
public struct FixedFractionSizing: PositionSizing, Sendable {
    public let riskPctPortfolio: Double
    public let stopLossPct: Double

    public init(riskPctPortfolio: Double = 1.0, stopLossPct: Double = 2.0) {
        self.riskPctPortfolio = riskPctPortfolio
        self.stopLossPct = stopLossPct
    }

    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        symbol: String
    ) -> PositionSizingResult {
        _ = symbol
        let riskAmount = accountSize * (riskPctPortfolio / 100.0)
        let priceRisk = abs(entryPrice - stopPrice)
        guard priceRisk > 0, entryPrice > 0 else { return invalidStop(method: .fixedFraction) }

        let quantity = riskAmount / priceRisk
        let positionSize = quantity * entryPrice
        let positionPct = accountSize > 0 ? positionSize / accountSize * 100.0 : 0

        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: riskAmount,
            positionPctPortfolio: positionPct,
            method: .fixedFraction,
            justification: "Risk \(currency(riskAmount)) at \(currency(priceRisk)) per share = \(String(format: "%.2f", quantity)) shares"
        )
    }
}

// MARK: - Fixed Dollar
public struct FixedDollarSizing: PositionSizing, Sendable {
    public let dollarAmount: Double

    public init(dollarAmount: Double = 1000.0) {
        self.dollarAmount = dollarAmount
    }

    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        symbol: String
    ) -> PositionSizingResult {
        _ = (stopPrice, symbol)
        guard entryPrice > 0 else { return invalidStop(method: .fixedDollar) }
        let quantity = dollarAmount / entryPrice
        let positionPct = accountSize > 0 ? dollarAmount / accountSize * 100.0 : 0

        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: dollarAmount,
            riskAmount: dollarAmount,
            positionPctPortfolio: positionPct,
            method: .fixedDollar,
            justification: "Fixed dollar investment of \(currency(dollarAmount)) at \(currency(entryPrice)) = \(String(format: "%.4f", quantity)) shares"
        )
    }
}

// MARK: - Kelly Criterion
public struct KellySizing: PositionSizing, Sendable {
    public let winRate: Double
    public let winLossRatio: Double

    public init(winRate: Double, winLossRatio: Double) {
        self.winRate = max(0, min(1, winRate))
        self.winLossRatio = max(0, winLossRatio)
    }

    public var kellyFraction: Double {
        guard winLossRatio > 0 else { return 0 }
        let p = winRate
        let q = 1 - p
        let fraction = (p * winLossRatio - q) / winLossRatio
        return max(0, min(fraction, 1.0))
    }

    public var fractionalKellyFraction: Double {
        kellyFraction / 2.0
    }

    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        symbol: String
    ) -> PositionSizingResult {
        _ = symbol
        let riskFraction = fractionalKellyFraction
        guard riskFraction > 0 else {
            return PositionSizingResult(
                suggestedQuantity: 0,
                suggestedPositionSize: 0,
                riskAmount: 0,
                positionPctPortfolio: 0,
                method: .kelly,
                justification: "Kelly criterion is non-positive; no position"
            )
        }

        let riskAmount = accountSize * riskFraction
        let priceRisk = abs(entryPrice - stopPrice)
        guard priceRisk > 0, entryPrice > 0 else { return invalidStop(method: .kelly) }

        let quantity = riskAmount / priceRisk
        let positionSize = quantity * entryPrice
        let positionPct = accountSize > 0 ? positionSize / accountSize * 100.0 : 0

        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: riskAmount,
            positionPctPortfolio: positionPct,
            method: .kelly,
            justification: "Kelly: full \(percentages(kellyFraction * 100)), half \(percentages(riskFraction * 100)), risking \(currency(riskAmount))"
        )
    }
}

// MARK: - Volatility Weighted
public struct VolatilityWeightedSizing: PositionSizing, Sendable {
    public let volatilityPct: Double
    public let targetVolatilityPct: Double
    public let riskPctPortfolio: Double

    public init(
        volatilityPct: Double,
        targetVolatilityPct: Double = 15.0,
        riskPctPortfolio: Double = 1.0
    ) {
        self.volatilityPct = volatilityPct
        self.targetVolatilityPct = targetVolatilityPct
        self.riskPctPortfolio = riskPctPortfolio
    }

    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        symbol: String
    ) -> PositionSizingResult {
        _ = symbol
        let riskAmount = accountSize * (riskPctPortfolio / 100.0)
        let priceRisk = abs(entryPrice - stopPrice)
        guard priceRisk > 0, entryPrice > 0 else { return invalidStop(method: .volatilityWeighted) }

        let volatilityAdjustment = targetVolatilityPct / max(volatilityPct, 1.0)
        let adjustedRisk = riskAmount * volatilityAdjustment
        let quantity = adjustedRisk / priceRisk
        let positionSize = quantity * entryPrice
        let positionPct = accountSize > 0 ? positionSize / accountSize * 100.0 : 0

        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: adjustedRisk,
            positionPctPortfolio: positionPct,
            method: .volatilityWeighted,
            justification: "Volatility-adjusted: vol \(percentages(volatilityPct)), target \(percentages(targetVolatilityPct)), risking \(currency(adjustedRisk))"
        )
    }
}

// MARK: - Risk Based
public struct RiskBasedSizing: PositionSizing, Sendable {
    public let maxRiskPct: Double
    public let maxConcurrentTrades: Int
    public let correlatedRiskPct: Double

    public init(
        maxRiskPct: Double = 2.0,
        maxConcurrentTrades: Int = 5,
        correlatedRiskPct: Double = 0.5
    ) {
        self.maxRiskPct = maxRiskPct
        self.maxConcurrentTrades = max(1, maxConcurrentTrades)
        self.correlatedRiskPct = correlatedRiskPct
    }

    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        symbol: String
    ) -> PositionSizingResult {
        calculate(
            entryPrice: entryPrice,
            stopPrice: stopPrice,
            accountSize: accountSize,
            symbol: symbol,
            concurrentTrades: 0
        )
    }

    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        symbol: String,
        concurrentTrades: Int
    ) -> PositionSizingResult {
        _ = symbol
        let maxRisk = accountSize * (maxRiskPct / 100.0)
        let openTrades = max(0, min(concurrentTrades, maxConcurrentTrades))
        let tradeFactor = Double(max(1, maxConcurrentTrades - openTrades)) / Double(maxConcurrentTrades + 1)
        let adjustedMaxRisk = maxRisk * tradeFactor
        let priceRisk = abs(entryPrice - stopPrice)
        guard priceRisk > 0, entryPrice > 0 else { return invalidStop(method: .riskBased) }

        let quantity = adjustedMaxRisk / priceRisk
        let positionSize = quantity * entryPrice
        let positionPct = accountSize > 0 ? positionSize / accountSize * 100.0 : 0

        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: adjustedMaxRisk,
            positionPctPortfolio: positionPct,
            method: .riskBased,
            justification: "Risk-based: max \(percentages(maxRiskPct)) risk, \(openTrades) open trades, risking \(currency(adjustedMaxRisk))"
        )
    }
}

// MARK: - Volatility Breakout
public struct VolatilityBreakoutSizing: PositionSizing, Sendable {
    public let atrPct: Double
    public let breakoutThreshold: Double
    public let riskPctPortfolio: Double

    public init(
        atrPct: Double,
        breakoutThreshold: Double = 1.5,
        riskPctPortfolio: Double = 1.0
    ) {
        self.atrPct = atrPct
        self.breakoutThreshold = max(breakoutThreshold, 0.01)
        self.riskPctPortfolio = riskPctPortfolio
    }

    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        symbol: String
    ) -> PositionSizingResult {
        calculate(
            entryPrice: entryPrice,
            stopPrice: stopPrice,
            accountSize: accountSize,
            symbol: symbol,
            atrValue: nil
        )
    }

    public func calculate(
        entryPrice: Double,
        stopPrice: Double,
        accountSize: Double,
        symbol: String,
        atrValue: Double?
    ) -> PositionSizingResult {
        _ = symbol
        let riskAmount = accountSize * (riskPctPortfolio / 100.0)
        let atr = atrValue ?? (abs(stopPrice - entryPrice) * 2.0)
        guard entryPrice > 0 else { return invalidStop(method: .volatilityBreakout) }
        let atrPctOfPrice = atr / entryPrice * 100.0
        let scale = atrPctOfPrice / breakoutThreshold
        let useScale = min(max(scale, 0.5), 2.0)
        let adjustedRisk = riskAmount * useScale
        let priceRisk = abs(entryPrice - stopPrice)
        guard priceRisk > 0 else { return invalidStop(method: .volatilityBreakout) }

        let quantity = adjustedRisk / priceRisk
        let positionSize = quantity * entryPrice
        let positionPct = accountSize > 0 ? positionSize / accountSize * 100.0 : 0

        return PositionSizingResult(
            suggestedQuantity: quantity,
            suggestedPositionSize: positionSize,
            riskAmount: adjustedRisk,
            positionPctPortfolio: positionPct,
            method: .volatilityBreakout,
            justification: "Volatility breakout: ATR \(percentages(atrPctOfPrice)), scale \(String(format: "%.2f", useScale)), risking \(currency(adjustedRisk))"
        )
    }
}

// MARK: - Factory
public enum PositionSizingFactory {
    public static func createSizer(
        _ method: PositionSizingMethod,
        parameters: [String: Any] = [:]
    ) -> any PositionSizing {
        switch method {
        case .fixedFraction:
            return FixedFractionSizing(
                riskPctPortfolio: parameters["riskPct"] as? Double ?? 1.0,
                stopLossPct: parameters["stopLossPct"] as? Double ?? 2.0
            )
        case .fixedDollar:
            return FixedDollarSizing(dollarAmount: parameters["dollarAmount"] as? Double ?? 1000.0)
        case .kelly:
            return KellySizing(
                winRate: parameters["winRate"] as? Double ?? 0.5,
                winLossRatio: parameters["winLossRatio"] as? Double ?? 2.0
            )
        case .volatilityWeighted:
            return VolatilityWeightedSizing(
                volatilityPct: parameters["volatilityPct"] as? Double ?? 15.0,
                targetVolatilityPct: parameters["targetVolatility"] as? Double ?? 15.0,
                riskPctPortfolio: parameters["riskPct"] as? Double ?? 1.0
            )
        case .riskBased:
            return RiskBasedSizing(
                maxRiskPct: parameters["maxRiskPct"] as? Double ?? 2.0,
                maxConcurrentTrades: parameters["maxConcurrentTrades"] as? Int ?? 5,
                correlatedRiskPct: parameters["correlatedRisk"] as? Double ?? 0.5
            )
        case .volatilityBreakout:
            return VolatilityBreakoutSizing(
                atrPct: parameters["atrPct"] as? Double ?? 2.0,
                breakoutThreshold: parameters["breakoutThreshold"] as? Double ?? 1.5,
                riskPctPortfolio: parameters["riskPct"] as? Double ?? 1.0
            )
        }
    }
}
