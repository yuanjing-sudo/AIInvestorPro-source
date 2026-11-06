// MARK: - Market Regime
import Foundation

public enum MarketRegime: String, CaseIterable, Codable, Sendable, Equatable, Hashable {
    case bullish = "bull"
    case bearish = "bear"
    case sideways = "sideways"
    case volatile = "volatile"
    case unknown = "unknown"
    case accumulation = "accumulation"
    case distribution = "distribution"

    public var description: String {
        rawValue.capitalized
    }

    /// UI color indicator
    var uiColor: String {
        switch self {
        case .bullish: return "🟢"
        case .bearish: return "🔴"
        case .sideways: return "🟡"
        case .volatile: return "🟣"
        case .unknown: return "⚪"
        case .accumulation: return "🟠"
        case .distribution: return "🟤"
        }
    }

    /// Detect regime from market snapshots using multiple methods.
    /// - Parameter snapshots: Market snapshots to analyze
    /// - Returns: Detected regime with confidence
    public static func detect(
        _ snapshots: [MarketSnapshot],
        withConfidence: Bool = true
    ) -> (regime: MarketRegime, confidence: Double) {
        _ = withConfidence
        guard !snapshots.isEmpty else { return (.unknown, 0.0) }

        let recentSnapshots = Array(snapshots.suffix(min(30, snapshots.count)))

        guard let firstPrice = recentSnapshots.first?.closes.first,
              let lastPrice = recentSnapshots.last?.closes.last,
              firstPrice > 0, lastPrice > 0 else {
            return (.unknown, 0.0)
        }
        let priceChange = (lastPrice - firstPrice) / firstPrice

        let closes = recentSnapshots.compactMap { $0.closes.last }
        guard closes.count > 1 else { return (.unknown, 0.0) }
        let returns = zip(closes.dropFirst(), closes.dropLast()).map { $0.0 / $0.1 - 1 }
        let averageReturn = returns.mean
        let variance = returns.reduce(0) { $0 + pow($1 - averageReturn, 2) } / Double(returns.count)
        let volatility = sqrt(max(0, variance)) * 100

        let allCloses = recentSnapshots.flatMap { $0.closes }
        guard !allCloses.isEmpty else { return (.unknown, 0.0) }
        let rsi7 = calculateRSI(allCloses, period: 7)
        let rsi14 = calculateRSI(allCloses, period: 14)
        let rsi21 = calculateRSI(allCloses, period: 21)
        let momentum = calculateMomentum(allCloses, period: 10)
        let autocorr = calculateAutocorrelation(allCloses, lag: 5)
        let waveCount = calculateWaveCount(allCloses)

        let regime = determineRegime(
            priceChange: priceChange,
            volatility: volatility,
            rsi7: rsi7,
            rsi14: rsi14,
            rsi21: rsi21,
            momentum: momentum,
            autocorr: autocorr,
            waveCount: waveCount
        )

        let confidence = calculateConfidence(
            priceChange: priceChange,
            volatility: volatility,
            rsi7: rsi7,
            rsi14: rsi14,
            momentum: momentum,
            autocorr: autocorr
        )

        return (regime, confidence)
    }

    /// Wilder RSI from a price array.
    private static func calculateRSI(_ prices: [Double], period: Int) -> Double {
        guard period > 0, prices.count > period else { return 50.0 }

        var gains: [Double] = []
        var losses: [Double] = []
        for index in 1..<prices.count {
            let change = prices[index] - prices[index - 1]
            gains.append(max(change, 0))
            losses.append(max(-change, 0))
        }

        var averageGain = gains.prefix(period).reduce(0, +) / Double(period)
        var averageLoss = losses.prefix(period).reduce(0, +) / Double(period)

        if gains.count > period {
            for index in period..<gains.count {
                averageGain = (averageGain * Double(period - 1) + gains[index]) / Double(period)
                averageLoss = (averageLoss * Double(period - 1) + losses[index]) / Double(period)
            }
        }

        guard averageLoss > 0 else { return averageGain > 0 ? 100 : 50 }
        let relativeStrength = averageGain / averageLoss
        return 100 - 100 / (1 + relativeStrength)
    }

    /// Price change over `period` observations.
    private static func calculateMomentum(_ prices: [Double], period: Int) -> Double {
        guard period > 0, prices.count > period else { return 0.0 }
        return prices[prices.count - 1] - prices[prices.count - 1 - period]
    }

    private static func calculateAutocorrelation(_ prices: [Double], lag: Int) -> Double {
        guard lag > 0, prices.count > lag * 2 else { return 0.0 }
        let current = Array(prices.dropFirst(lag))
        let lagged = Array(prices.dropLast(lag))
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
        return denominator > 0 ? clamp(numerator / denominator, -1, 1) : 0.0
    }

    private static func calculateWaveCount(_ prices: [Double]) -> Int {
        guard prices.count > 10 else { return 3 }
        return 5
    }

    private static func determineRegime(
        priceChange: Double,
        volatility: Double,
        rsi7: Double,
        rsi14: Double,
        rsi21: Double,
        momentum: Double,
        autocorr: Double,
        waveCount: Int
    ) -> MarketRegime {
        _ = (rsi7, rsi21, autocorr, waveCount)

        let isBullish = priceChange > 0.03 && volatility < 25 && rsi14 > 55 && momentum > 0
        let isBearish = priceChange < -0.03 && volatility < 25 && rsi14 < 45 && momentum < 0
        let isVolatile = volatility > 30
        let isSideways = volatility < 20 && rsi14 > 45 && rsi14 < 55
        let isAccumulation = priceChange > 0 && volatility > 25 && volatility < 35
        let isDistribution = priceChange < 0 && volatility > 25 && volatility < 35

        if isAccumulation { return .accumulation }
        if isDistribution { return .distribution }
        if isBullish { return .bullish }
        if isBearish { return .bearish }
        if isVolatile { return .volatile }
        if isSideways { return .sideways }
        return .unknown
    }

    private static func calculateConfidence(
        priceChange: Double,
        volatility: Double,
        rsi7: Double,
        rsi14: Double,
        momentum: Double,
        autocorr: Double
    ) -> Double {
        var aligningIndicators = 0
        var totalIndicators = 0

        totalIndicators += 1
        if abs(priceChange) > 0.03 { aligningIndicators += 1 }

        totalIndicators += 1
        if volatility > 20 && volatility < 30 { aligningIndicators += 1 }

        totalIndicators += 1
        if (rsi7 > 55 && rsi14 > 55) || (rsi7 < 45 && rsi14 < 45) { aligningIndicators += 1 }

        totalIndicators += 1
        if momentum != 0 { aligningIndicators += 1 }

        totalIndicators += 1
        if abs(autocorr) > 0.3 { aligningIndicators += 1 }

        return totalIndicators > 0 ? Double(aligningIndicators) / Double(totalIndicators) : 0.5
    }
}

extension MarketRegime: Identifiable {
    public var id: String { rawValue }
}

// MARK: - Regime Transition
public struct RegimeTransition {
    let current: MarketRegime
    let previous: MarketRegime
    let date: Date
    let stayProbability: Double
    let transitionProbability: Double

    public init(
        current: MarketRegime,
        previous: MarketRegime,
        date: Date = Date(),
        stayProbability: Double = 0.7,
        transitionProbability: Double = 0.3
    ) {
        self.current = current
        self.previous = previous
        self.date = date
        self.stayProbability = stayProbability
        self.transitionProbability = transitionProbability
    }

    var description: String {
        "\(previous.rawValue) → \(current.rawValue) on \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}
