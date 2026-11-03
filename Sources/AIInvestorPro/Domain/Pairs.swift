// MARK: - Pair Trading
import Foundation

public struct Pair<Base: Hashable, Quote: Hashable>: Hashable {
    public let base: Base
    public let quote: Quote
    public let ratio: Double // base/quote price ratio
    public let lastUpdated: Date
    
    public init(base: Base, quote: Quote, ratio: Double) {
        self.base = base
        self.quote = quote
        self.ratio = ratio
        self.lastUpdated = Date()
    }
    
    public var description: String {
        "\(base)/\(quote) [\(String(format: "%.4f", ratio))]"
    }
    
    // Calculate spread from mean
    public func spread(from meanRatio: Double) -> Double {
        ratio - meanRatio
    }
    
    // Z-score of spread
    public func zScore(from historicalRatios: [Double], _ mean: Double, _ std: Double) -> Double {
        guard std != 0 else { return 0 }
        return (ratio - mean) / std
    }
}

public struct PairTradeSignal: Equatable {
    public let pair: Pair<String, String>
    public let signal: TradeSignal
    public let entryPrice: Double
    public let spread: Double
    public let zScore: Double
    public let recommendedEntry: Double
    public let recommendedStop: Double
    public let recommendedTarget: Double
    public let confidence: Double
    public let rationale: String
    
    public static func == (lhs: PairTradeSignal, rhs: PairTradeSignal) -> Bool {
        lhs.pair.base == rhs.pair.base && lhs.pair.quote == rhs.pair.quote
    }
}

public enum TradeSignal: String, CaseIterable {
    case enterLong = "enter_long"
    case enterShort = "enter_short"
    case exit = "exit"
    case hold = "hold"
    
    public var description: String {
    }
}

public struct PairAnalysis {
    public let pair: Pair<String, String>
    public let historicalRatio: [Double]
    public let meanRatio: Double
    public let stdDev: Double
    public let currentSpread: Double
    public let currentZScore: Double
    public let halfLife: Double // Cointegration half-life
    public let correlation: Double
    public let tradeSignals: [PairTradeSignal]
    public let lastAnalyzed: Date
    
    public init(pair: Pair<String, String>, historicalRatios: [Double]) {
        self.pair = pair
        self.historicalRatio = historicalRatios
        self.meanRatio = historicalRatios.mean
        self.stdDev = historicalRatios.standardDeviation
        self.currentSpread = pair.spread(from: meanRatio)
        self.currentZScore = pair.zScore(from: historicalRatios, meanRatio, stdDev)
        self.halfLife = calculateHalfLife(historicalRatios)
        self.correlation = calculateCorrelation(historicalRatios)
        self.tradeSignals = generateSignals()
        self.lastAnalyzed = Date()
    }
    
    private func calculateHalfLife(_ ratios: [Double]) -> Double {
        // Simplified half-life calculation using OU process
        guard ratios.count > 10 else { return 50.0 }
        let returns = zip(ratios.dropFirst(), ratios.dropLast()).map { $1 - $0 }
        let alpha = -log(0.5) / returns.reduce(0, +).absoluteValue + 1 // Simplified
        return log(0.5) / (-alpha + 1e-10) // Avoid division by zero
    }
    
    private func calculateCorrelation(_ ratios: [Double]) -> Double {
        guard ratios.count > 2 else { return 0 }
        let mean = ratios.mean
        let numerator = zip(ratios, ratios.dropFirst()).map { $0 * $1 }.reduce(0, +) - pow(mean, 2) * Double(ratios.count)
        let denom = sqrt((zip(ratios, ratios.map { pow($0, 2) }).reduce(0, +) - pow(mean, 2) * Double(ratios.count)) *
                         (zip(ratios.dropFirst(), ratios.dropFirst()).map { $0 * $1 }.reduce(0, +) - pow(mean, 2) * Double(ratios.count - 1)))
        return denom > 0 ? numerator / denom : 0
    }
    
    private func generateSignals() -> [PairTradeSignal] {
        var signals: [PairTradeSignal] = []
        
        // Entry signals based on z-score
        if currentZScore > 2.0 {
            signals.append(PairTradeSignal(
                pair: pair,
                signal: .enterShort,
                entryPrice: pair.ratio,
                spread: currentSpread,
                zScore: currentZScore,
                recommendedEntry: currentSpread - (currentZScore * stdDev),
                recommendedStop: currentSpread + stdDev,
                recommendedTarget: currentSpread - (2.0 * stdDev),
                confidence: min(abs(currentZScore) / 3.0, 1.0),
                rationale: "Z-score \(String(format: "%.1f", currentZScore)) above 2.0 - mean reversion opportunity"
            ))
        } else if currentZScore < -2.0 {
            signals.append(PairTradeSignal(
                pair: pair,
                signal: .enterLong,
                entryPrice: pair.ratio,
                spread: currentSpread,
                zScore: currentZScore,
                recommendedEntry: currentSpread + (currentZScore * stdDev).absoluteValue,
                recommendedStop: currentSpread - stdDev,
                recommendedTarget: currentSpread + (2.0 * stdDev).absoluteValue,
                confidence: min(abs(currentZScore) / 3.0, 1.0),
                rationale: "Z-score \(String(format: "%.1f", currentZScore)) below -2.0 - mean reversion opportunity"
            ))
        } else {
            signals.append(PairTradeSignal(
                pair: pair,
                signal: .hold,
                entryPrice: pair.ratio,
                spread: currentSpread,
                zScore: currentZScore,
                recommendedEntry: pair.ratio,
                recommendedStop: 0,
                recommendedTarget: 0,
                confidence: 0.5,
                rationale: "Z-score \(String(format: "%.1f", currentZScore)) within normal range"
            ))
        }
        
        return signals
    }
}
