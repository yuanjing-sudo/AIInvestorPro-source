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

    /// Spread from the historical mean ratio.
    public func spread(from meanRatio: Double) -> Double {
        ratio - meanRatio
    }

    /// Z-score of the current ratio against a historical mean and standard
    /// deviation. The historical values are accepted for call-site
    /// compatibility; the supplied mean and deviation are authoritative.
    public func zScore(from historicalRatios: [Double], _ mean: Double, _ std: Double) -> Double {
        _ = historicalRatios
        guard std > 0 else { return 0 }
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
}

public enum TradeSignal: String, CaseIterable, Sendable, Equatable {
    case buy = "buy"
    case sell = "sell"
    case strongBuy = "strong_buy"
    case strongSell = "strong_sell"
    case enterLong = "enter_long"
    case enterShort = "enter_short"
    case exit = "exit"
    case hold = "hold"

    public var description: String {
        switch self {
        case .buy: return "Buy"
        case .sell: return "Sell"
        case .strongBuy: return "Strong buy"
        case .strongSell: return "Strong sell"
        case .enterLong: return "Enter long"
        case .enterShort: return "Enter short"
        case .exit: return "Exit"
        case .hold: return "Hold"
        }
    }
}

public struct PairAnalysis {
    public let pair: Pair<String, String>
    public let historicalRatio: [Double]
    public let meanRatio: Double
    public let stdDev: Double
    public let currentSpread: Double
    public let currentZScore: Double
    public let halfLife: Double // mean-reversion half-life in observations
    public let correlation: Double
    public let tradeSignals: [PairTradeSignal]
    public let lastAnalyzed: Date

    public init(pair: Pair<String, String>, historicalRatios: [Double]) {
        self.pair = pair
        self.historicalRatio = historicalRatios
        let average = historicalRatios.mean
        let deviation = historicalRatios.standardDeviation
        self.meanRatio = average
        self.stdDev = deviation
        let spread = pair.ratio - average
        self.currentSpread = spread
        let zScore = deviation > 0 ? spread / deviation : 0
        self.currentZScore = zScore
        self.halfLife = PairAnalysis.calculateHalfLife(historicalRatios)
        self.correlation = PairAnalysis.calculateAutocorrelation(historicalRatios)
        self.tradeSignals = PairAnalysis.makeSignals(
            pair: pair,
            spread: spread,
            zScore: zScore,
            stdDev: deviation
        )
        self.lastAnalyzed = Date()
    }

    /// Estimate a mean-reversion half-life with an AR(1) regression of the
    /// change in ratio on the lagged ratio level. Returns a large sentinel
    /// value when the series is too short or shows no mean reversion.
    private static func calculateHalfLife(_ ratios: [Double]) -> Double {
        guard ratios.count > 10 else { return 50.0 }
        let levels = Array(ratios.dropLast())
        let changes = zip(ratios.dropFirst(), ratios.dropLast()).map { $0.0 - $0.1 }
        let meanLevel = levels.mean
        let meanChange = changes.mean

        var covariance = 0.0
        var variance = 0.0
        for index in levels.indices {
            let x = levels[index] - meanLevel
            covariance += x * (changes[index] - meanChange)
            variance += x * x
        }
        guard variance > 0 else { return 50.0 }
        let slope = covariance / variance
        // A non-negative slope means the series is not mean reverting.
        guard slope < 0, slope > -1 else { return 50.0 }
        return -log(2.0) / log(1.0 + slope)
    }

    /// Lag-one autocorrelation of the ratio series.
    private static func calculateAutocorrelation(_ ratios: [Double]) -> Double {
        guard ratios.count > 2 else { return 0 }
        let current = Array(ratios.dropFirst())
        let lagged = Array(ratios.dropLast())
        let currentMean = current.mean
        let laggedMean = lagged.mean

        var numerator = 0.0
        var currentVariance = 0.0
        var laggedVariance = 0.0
        for index in current.indices {
            let currentDelta = current[index] - currentMean
            let laggedDelta = lagged[index] - laggedMean
            numerator += currentDelta * laggedDelta
            currentVariance += currentDelta * currentDelta
            laggedVariance += laggedDelta * laggedDelta
        }
        let denominator = sqrt(currentVariance * laggedVariance)
        return denominator > 0 ? clamp(numerator / denominator, -1, 1) : 0
    }

    private static func makeSignals(
        pair: Pair<String, String>,
        spread: Double,
        zScore: Double,
        stdDev: Double
    ) -> [PairTradeSignal] {
        if zScore > 2.0 {
            return [PairTradeSignal(
                pair: pair,
                signal: .enterShort,
                entryPrice: pair.ratio,
                spread: spread,
                zScore: zScore,
                recommendedEntry: spread - zScore * stdDev,
                recommendedStop: spread + stdDev,
                recommendedTarget: spread - 2.0 * stdDev,
                confidence: min(abs(zScore) / 3.0, 1.0),
                rationale: "Z-score \(String(format: "%.1f", zScore)) above 2.0 - mean reversion opportunity"
            )]
        }

        if zScore < -2.0 {
            return [PairTradeSignal(
                pair: pair,
                signal: .enterLong,
                entryPrice: pair.ratio,
                spread: spread,
                zScore: zScore,
                recommendedEntry: spread + abs(zScore) * stdDev,
                recommendedStop: spread - stdDev,
                recommendedTarget: spread + 2.0 * stdDev,
                confidence: min(abs(zScore) / 3.0, 1.0),
                rationale: "Z-score \(String(format: "%.1f", zScore)) below -2.0 - mean reversion opportunity"
            )]
        }

        return [PairTradeSignal(
            pair: pair,
            signal: .hold,
            entryPrice: pair.ratio,
            spread: spread,
            zScore: zScore,
            recommendedEntry: pair.ratio,
            recommendedStop: 0,
            recommendedTarget: 0,
            confidence: 0.5,
            rationale: "Z-score \(String(format: "%.1f", zScore)) within normal range"
        )]
    }
}
