// MARK: - Alpha Factors
import Foundation

public struct AlphaFactor: Equatable {
    public let id: String
    public let name: String
    public let description: String
    public var score: Double
    public let calculationDate: Date
    public let lookbackPeriod: Int
    
    public init(name: String, description: String = "", score: Double = 0, lookbackPeriod: Int = 20) {
        self.id = UUID().uuidString
        self.name = name
        self.description = description
        self.score = score
        self.calculationDate = Date()
        self.lookbackPeriod = lookbackPeriod
    }
    
    public static func == (lhs: AlphaFactor, rhs: AlphaFactor) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}

// MARK: - Specific Alpha Factors
public struct MomentumAlpha: AlphaFactor {
    public let momentumPeriod: Int
    
    public init(momentumPeriod: Int = 12) {
        self.momentumPeriod = momentumPeriod
        super.init(name: "Momentum", description: "Price momentum over \(momentumPeriod) periods", score: 0, lookbackPeriod: momentumPeriod)
    }
    
    public mutating func calculate(from prices: [Double]) {
        guard prices.count >= momentumPeriod else { return }
        let change = (prices.last! - prices[prices.count - momentumPeriod]) / abs(prices[prices.count - momentumPeriod])
        score = change * 100
    }
}

public struct MeanReversionAlpha: AlphaFactor {
    public let lookbackPeriod: Int
    public let entryThreshold: Double
    public let exitThreshold: Double
    
    public init(lookbackPeriod: Int = 20, entryThreshold: Double = 75, exitThreshold: Double = 30) {
        self.lookbackPeriod = lookbackPeriod
        self.entryThreshold = entryThreshold
        self.exitThreshold = exitThreshold
        super.init(name: "MeanReversion", description: "Reversion to mean after \(lookbackPeriod)-period deviation", score: 0, lookbackPeriod: lookbackPeriod)
    }
    
    public mutating func calculate(from prices: [Double], rsi: Double) {
        guard prices.count >= lookbackPeriod else { return }
        // Mean reversion: buy when oversold, sell when overbought
        if rsi > entryThreshold {
            score = -1 // Bearish
        } else if rsi < exitThreshold {
            score = 1 // Bullish
        } else {
            score = 0 // Neutral
        }
    }
}

public struct VolatilityAlpha: AlphaFactor {
    public let lookbackPeriod: Int
    public let targetVol: Double
    
    public init(lookbackPeriod: Int = 20, targetVol: Double = 15.0) {
        self.lookbackPeriod = lookbackPeriod
        self.targetVol = targetVol
        super.init(name: "Volatility", description: "Volatility deviation from target", score: 0, lookbackPeriod: lookbackPeriod)
    }
    
    public mutating func calculate(from returns: [Double]) {
        guard returns.count >= lookbackPeriod else { return }
        let avgVol = sqrt(Double(252) * returns.suffix(lookbackPeriod).map { pow($0, 2) }.reduce(0, +) / Double(lookbackPeriod)) * 100
        score = (avgVol - targetVol) / targetVol * 100 // Positive if above target
    }
}

public struct ValueAlpha: AlphaFactor {
    public let peRatio: Double?
    public let pbRatio: Double?
    public let dividendYield: Double?
    
    public init(peRatio: Double? = nil, pbRatio: Double? = nil, dividendYield: Double? = nil) {
        self.peRatio = peRatio
        self.pbRatio = pbRatio
        self.dividendYield = dividendYield
        super.init(name: "Value", description: "Fundamental value factors", score: 0, lookbackPeriod: 0)
    }
    
    public mutating func calculate(from fundamentals: [String: Double]?) {
        guard let fundamentals = fundamentals else { return }
        
        if let pe = peRatio {
            // Lower PE = better value (score inversely related)
            score = pe > 0 ? (100 / pe) * 10 : 0
        }
        
        if let pb = pbRatio {
            score = score + (pb > 0 ? (100 / pb) * 2 : 0)
        }
        
        if let dy = dividendYield {
            score = score + dy * 500 // Higher dividend = better value
        }
    }
}

public struct MomentumAccelerationAlpha: AlphaFactor {
    public let fastPeriod: Int
    public let slowPeriod: Int
    
    public init(fastPeriod: Int = 5, slowPeriod: Int = 20) {
        self.fastPeriod = fastPeriod
        self.slowPeriod = slowPeriod
        super.init(name: "MomentumAcceleration", description: "Acceleration of momentum over fast/slow periods", score: 0, lookbackPeriod: slowPeriod)
    }
    
    public mutating func calculate(from prices: [Double]) {
        guard prices.count >= slowPeriod else { return }
        let fastChange = (prices.last! - prices[prices.count - fastPeriod]) / abs(prices[prices.count - fastPeriod])
        let slowChange = (prices.last! - prices[prices.count - slowPeriod]) / abs(prices[prices.count - slowPeriod])
        // Acceleration = difference in momentum
        score = (fastChange - slowChange) * 100
    }
}

public struct ReversalAlpha: AlphaFactor {
    public let lookbackPeriod: Int
    
    public init(lookbackPeriod: Int = 10) {
        self.lookbackPeriod = lookbackPeriod
        super.init(name: "Reversal", description: "Price reversal detection", score: 0, lookbackPeriod: lookbackPeriod)
    }
    
    public mutating func calculate(from prices: [Double]) {
        guard prices.count >= lookbackPeriod + 2 else { return }
        // Look for reversal: price change direction opposite to recent trend
        let midPoint = prices.count / 2
        let earlyChange = (prices[midPoint] - prices[0]) / abs(prices[0])
        let lateChange = (prices.last! - prices[midPoint]) / abs(prices[midPoint])
        
        // If early was up and late is down (or vice versa), it's a reversal
        if (earlyChange > 0 && lateChange < 0) || (earlyChange < 0 && lateChange > 0) {
            score = lateChange * 100 // Score based on reversal magnitude
        } else {
            score = 0 // No reversal
        }
    }
}

// MARK: - Alpha Factor Composite
public struct AlphaComposite {
    private var factors: [AlphaFactor] = []
    private var weights: [String: Double] = [:] // factorName -> weight
    
    public mutating func add(_ factor: AlphaFactor, weight: Double? = nil) {
        factors.append(factor)
        if let weight = weight {
            weights[factor.name] = weight
        } else {
            // Equal weight
            weights[factor.name] = 1.0 / Double(factors.count)
        }
    }
    
    public var compositeScore: Double {
        guard !factors.isEmpty else { return 0 }
        var weightedSum = 0.0
        var totalWeight = 0.0
        
        for factor in factors {
            let weight = weights[factor.name] ?? 1.0 / Double(factors.count)
            weightedSum += factor.score * weight
            totalWeight += weight
        }
        
        return totalWeight > 0 ? weightedSum / totalWeight : 0
    }
    
    public var recommendation: String {
        compositeScore > 0.5 ? "buy" : compositeScore < -0.5 ? "sell" : "hold"
    }
}

// MARK: - Alpha Factor Registry
public final class AlphaFactorRegistry: ObservableObject {
    @Published public var factors: [AlphaFactor] = []
    @Published public var composite: AlphaComposite?
    
    public init() {
        // Default factors
        factors = [
            MomentumAlpha(),
            MeanReversionAlpha(),
            VolatilityAlpha(),
            ValueAlpha()
        ]
    }
    
    public func recalculateComposite() {
        var composite = AlphaComposite()
        for factor in factors {
            composite.add(factor)
        }
        self.composite = composite
    }
}
