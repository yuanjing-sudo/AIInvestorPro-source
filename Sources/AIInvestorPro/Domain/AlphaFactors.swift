// MARK: - Alpha Factors
import Foundation
import Combine

/// Base alpha factor. The concrete factors below are reference types so they
/// can share the common mutable `score` while adding their own inputs.
public class AlphaFactor: Equatable {
    public let id: String
    public let name: String
    public let description: String
    public var score: Double
    public let calculationDate: Date
    public let lookbackPeriod: Int

    public init(
        name: String,
        description: String = "",
        score: Double = 0,
        lookbackPeriod: Int = 20
    ) {
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
public final class MomentumAlpha: AlphaFactor {
    public let momentumPeriod: Int

    public init(momentumPeriod: Int = 12) {
        self.momentumPeriod = momentumPeriod
        super.init(
            name: "Momentum",
            description: "Price momentum over \(momentumPeriod) periods",
            score: 0,
            lookbackPeriod: momentumPeriod
        )
    }

    public func calculate(from prices: [Double]) {
        guard momentumPeriod > 0,
              prices.count > momentumPeriod,
              let last = prices.last else { return }
        let previous = prices[prices.count - 1 - momentumPeriod]
        guard previous != 0 else { return }
        score = (last - previous) / abs(previous) * 100
    }
}

public final class MeanReversionAlpha: AlphaFactor {
    public let entryThreshold: Double
    public let exitThreshold: Double

    public init(lookbackPeriod: Int = 20, entryThreshold: Double = 75, exitThreshold: Double = 30) {
        self.entryThreshold = entryThreshold
        self.exitThreshold = exitThreshold
        super.init(
            name: "MeanReversion",
            description: "Reversion to mean after \(lookbackPeriod)-period deviation",
            score: 0,
            lookbackPeriod: lookbackPeriod
        )
    }

    public func calculate(from prices: [Double], rsi: Double) {
        guard !prices.isEmpty, prices.count >= lookbackPeriod else { return }
        if rsi > entryThreshold {
            score = -1
        } else if rsi < exitThreshold {
            score = 1
        } else {
            score = 0
        }
    }
}

public final class VolatilityAlpha: AlphaFactor {
    public let targetVol: Double

    public init(lookbackPeriod: Int = 20, targetVol: Double = 15.0) {
        self.targetVol = targetVol
        super.init(
            name: "Volatility",
            description: "Volatility deviation from target",
            score: 0,
            lookbackPeriod: lookbackPeriod
        )
    }

    public func calculate(from returns: [Double]) {
        guard lookbackPeriod > 0, returns.count >= lookbackPeriod else { return }
        let window = returns.suffix(lookbackPeriod)
        let variance = window.map { $0 * $0 }.reduce(0, +) / Double(lookbackPeriod)
        let annualizedVolatility = sqrt(Double(252) * variance) * 100
        guard targetVol > 0 else { return }
        score = (annualizedVolatility - targetVol) / targetVol * 100
    }
}

public final class ValueAlpha: AlphaFactor {
    public let peRatio: Double?
    public let pbRatio: Double?
    public let dividendYield: Double?

    public init(peRatio: Double? = nil, pbRatio: Double? = nil, dividendYield: Double? = nil) {
        self.peRatio = peRatio
        self.pbRatio = pbRatio
        self.dividendYield = dividendYield
        super.init(
            name: "Value",
            description: "Fundamental value factors",
            score: 0,
            lookbackPeriod: 0
        )
    }

    public func calculate(from fundamentals: [String: Double]? = nil) {
        if let pe = fundamentals?["pe"] ?? peRatio, pe > 0 {
            score = (100 / pe) * 10
        }
        if let pb = fundamentals?["pb"] ?? pbRatio, pb > 0 {
            score += (100 / pb) * 2
        }
        if let dividend = fundamentals?["dividendYield"] ?? dividendYield {
            score += dividend * 500
        }
    }
}

public final class MomentumAccelerationAlpha: AlphaFactor {
    public let fastPeriod: Int
    public let slowPeriod: Int

    public init(fastPeriod: Int = 5, slowPeriod: Int = 20) {
        self.fastPeriod = fastPeriod
        self.slowPeriod = slowPeriod
        super.init(
            name: "MomentumAcceleration",
            description: "Acceleration of momentum over fast/slow periods",
            score: 0,
            lookbackPeriod: slowPeriod
        )
    }

    public func calculate(from prices: [Double]) {
        guard slowPeriod > 0, fastPeriod > 0,
              prices.count > slowPeriod,
              let last = prices.last else { return }

        let fastBase = prices[prices.count - 1 - fastPeriod]
        let slowBase = prices[prices.count - 1 - slowPeriod]
        guard fastBase != 0, slowBase != 0 else { return }

        let fastChange = (last - fastBase) / abs(fastBase)
        let slowChange = (last - slowBase) / abs(slowBase)
        score = (fastChange - slowChange) * 100
    }
}

public final class ReversalAlpha: AlphaFactor {
    public init(lookbackPeriod: Int = 10) {
        super.init(
            name: "Reversal",
            description: "Price reversal detection",
            score: 0,
            lookbackPeriod: lookbackPeriod
        )
    }

    public func calculate(from prices: [Double]) {
        guard lookbackPeriod > 0, prices.count >= lookbackPeriod + 2,
              let first = prices.first, first != 0 else { return }

        let midPoint = prices.count / 2
        guard prices[midPoint] != 0 else { return }
        let earlyChange = (prices[midPoint] - first) / abs(first)
        let lateChange = (prices[prices.count - 1] - prices[midPoint]) / abs(prices[midPoint])

        if (earlyChange > 0 && lateChange < 0) || (earlyChange < 0 && lateChange > 0) {
            score = lateChange * 100
        } else {
            score = 0
        }
    }
}

// MARK: - Alpha Factor Composite
public struct AlphaComposite {
    private var factors: [AlphaFactor] = []
    private var weights: [String: Double] = [:]

    public init() {}

    public mutating func add(_ factor: AlphaFactor, weight: Double? = nil) {
        factors.append(factor)
        if let weight {
            weights[factor.name] = weight
        } else {
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
