// MARK: - Feature Engineering
import Foundation

public enum FeatureType: String, CaseIterable, Sendable, Hashable {
    case priceReturn = "price_return"
    case logReturn = "log_return"
    case movingAverage = "moving_average"
    case exponentialMovingAverage = "exponential_moving_average"
    case relativeStrength = "relative_strength"
    case volatility = "volatility"
    case volumeRatio = "volume_ratio"
    case priceToMA = "price_to_ma"
    case momentumOscillator = "momentum_oscillator"
    case rsi = "rsi"
    case macdHistogram = "macd_histogram"
    case stochK = "stoch_k"
    case stochD = "stoch_d"
    case williamsR = "williams_r"
    case bollingerPosition = "bollinger_position"
    case volumeWeightedPrice = "volume_weighted_price"

    public var description: String {
        rawValue.replacingUnderscoresWithSpaces
    }
}

public struct ExtractedFeature: Equatable, Sendable {
    public let featureType: FeatureType
    public let value: Double
    public let timestamp: Date
    public let symbol: String?

    public init(featureType: FeatureType, value: Double, timestamp: Date = Date(), symbol: String? = nil) {
        self.featureType = featureType
        self.value = value
        self.timestamp = timestamp
        self.symbol = symbol
    }

    public static func == (lhs: ExtractedFeature, rhs: ExtractedFeature) -> Bool {
        lhs.featureType == rhs.featureType && lhs.value == rhs.value
    }

    var formatted: String {
        "\(featureType.rawValue): \(String(format: "%.4f", value)) at \(timestamp.formatted(date: .abbreviated, time: .omitted))"
    }
}

public final class FeatureEngineer {
    private let prices: [Double]
    private let highs: [Double]
    private let lows: [Double]
    private let volumes: [Double]
    private let timestamps: [Date]
    private let lookback: Int

    public init(
        prices: [Double],
        highs: [Double]? = nil,
        lows: [Double]? = nil,
        volumes: [Double]? = nil,
        lookback: Int = 20
    ) {
        self.prices = prices
        self.highs = highs ?? prices.map { $0 * 1.02 }
        self.lows = lows ?? prices.map { $0 * 0.98 }
        self.volumes = volumes ?? Array(repeating: 1_000_000, count: prices.count)
        self.timestamps = (0..<prices.count).map { Date().addingTimeInterval(-86_400 * Double(prices.count - 1 - $0)) }
        self.lookback = max(1, lookback)
    }

    public func extractAllFeatures() -> [FeatureType: Double] {
        var features: [FeatureType: Double] = [:]
        features[.priceReturn] = priceReturn()
        features[.logReturn] = logReturn()
        features[.movingAverage] = movingAverage()
        features[.exponentialMovingAverage] = ema()
        features[.relativeStrength] = relativeStrength()
        features[.volatility] = volatility()
        features[.volumeRatio] = volumeRatio()
        features[.priceToMA] = priceToMA()
        features[.momentumOscillator] = momentumOscillator()
        features[.rsi] = rsi()
        features[.macdHistogram] = macdHistogram()
        features[.stochK] = stochK()
        features[.stochD] = stochD()
        features[.williamsR] = williamsR()
        features[.bollingerPosition] = bollingerPosition()
        features[.volumeWeightedPrice] = volumeWeightedPrice()
        return features
    }

    private func priceReturn() -> Double {
        guard prices.count > lookback else { return 0 }
        let start = prices[prices.count - 1 - lookback]
        guard start != 0, let end = prices.last else { return 0 }
        return (end - start) / abs(start)
    }

    private func logReturn() -> Double {
        guard prices.count > 1,
              let last = prices.last,
              last > 0 else { return 0 }
        let previous = prices[prices.count - 2]
        guard previous > 0 else { return 0 }
        return log(last / previous)
    }

    private func movingAverage() -> Double {
        guard !prices.isEmpty else { return 0 }
        let window = prices.suffix(min(lookback, prices.count))
        return window.reduce(0, +) / Double(window.count)
    }

    private func ema(period: Int? = nil) -> Double {
        let period = max(1, period ?? lookback)
        guard prices.count >= period, let first = prices.first else {
            return prices.last ?? 0
        }
        let multiplier = 2.0 / (Double(period) + 1)
        var value = first
        for price in prices.dropFirst() {
            value = (price - value) * multiplier + value
        }
        return value
    }

    private func relativeStrength() -> Double {
        let average = movingAverage()
        guard average > 0, let last = prices.last else { return 0.5 }
        return last / average
    }

    private func volatility() -> Double {
        guard prices.count > 1 else { return 0 }
        let returns = zip(prices.dropFirst(), prices.dropLast()).map { $0.0 / $0.1 - 1 }
        guard !returns.isEmpty else { return 0 }
        let window = Array(returns.suffix(min(lookback, returns.count)))
        let average = window.mean
        let variance = window.reduce(0) { $0 + pow($1 - average, 2) } / Double(window.count)
        return sqrt(max(0, variance)) * sqrt(252) * 100
    }

    private func volumeRatio() -> Double {
        guard let currentVolume = volumes.last, volumes.count > 1 else { return 1.0 }
        let average = volumes.dropLast().reduce(0, +) / Double(volumes.count - 1)
        return average > 0 ? currentVolume / average : 1.0
    }

    private func priceToMA() -> Double {
        let average = movingAverage()
        guard average > 0, let last = prices.last else { return 1.0 }
        return last / average
    }

    private func momentumOscillator() -> Double {
        let period = min(10, prices.count - 1)
        guard period > 0 else { return 0 }
        let previous = prices[prices.count - 1 - period]
        guard previous != 0, let current = prices.last else { return 0 }
        return (current - previous) / abs(previous) * 100
    }

    private func rsi(period: Int = 14) -> Double {
        guard prices.count > period else { return 50.0 }
        var averageGain = 0.0
        var averageLoss = 0.0
        for index in 1...period {
            let change = prices[index] - prices[index - 1]
            averageGain += max(change, 0)
            averageLoss += max(-change, 0)
        }
        averageGain /= Double(period)
        averageLoss /= Double(period)

        if prices.count > period + 1 {
            for index in (period + 1)..<prices.count {
                let change = prices[index] - prices[index - 1]
                averageGain = (averageGain * Double(period - 1) + max(change, 0)) / Double(period)
                averageLoss = (averageLoss * Double(period - 1) + max(-change, 0)) / Double(period)
            }
        }

        guard averageLoss > 0 else { return averageGain > 0 ? 100 : 50 }
        return 100 - 100 / (1 + averageGain / averageLoss)
    }

    private func macdHistogram() -> Double {
        guard prices.count >= 26 else { return 0 }
        let fast = ema(period: 12)
        let slow = ema(period: 26)
        return fast - slow
    }

    private func stochasticValues(period: Int = 14) -> (k: Double, d: Double) {
        guard prices.count >= period else { return (50, 50) }
        var closes = prices
        let high = highs.suffix(min(period, highs.count)).max() ?? closes.last ?? 0
        let low = lows.suffix(min(period, lows.count)).min() ?? closes.last ?? 0
        guard high > low, let current = closes.last else { return (50, 50) }
        let k = (current - low) / (high - low) * 100
        return (clamp(k, 0, 100), clamp(k, 0, 100))
    }

    private func stochK() -> Double {
        stochasticValues().k
    }

    private func stochD() -> Double {
        stochasticValues().d
    }

    private func williamsR() -> Double {
        guard prices.count >= 14 else { return -50.0 }
        let high = highs.suffix(14).max() ?? 0
        let low = lows.suffix(14).min() ?? 0
        guard high > low, let current = prices.last else { return -50.0 }
        return -(high - current) / (high - low) * 100
    }

    private func bollingerPosition() -> Double {
        guard prices.count >= 20 else { return 0.5 }
        let window = prices.suffix(20)
        let average = window.reduce(0, +) / 20
        let variance = window.reduce(0) { $0 + pow($1 - average, 2) } / 20
        let deviation = sqrt(max(0, variance))
        let upper = average + 2 * deviation
        let lower = average - 2 * deviation
        guard upper > lower, let price = prices.last else { return 0.5 }
        return clamp((price - lower) / (upper - lower), 0, 1)
    }

    private func volumeWeightedPrice() -> Double {
        guard prices.count > 1, volumes.count == prices.count else { return prices.last ?? 0 }
        let totalVolume = volumes.reduce(0, +)
        guard totalVolume > 0 else { return prices.last ?? 0 }
        let product = zip(prices, volumes).map { $0.0 * $0.1 }.reduce(0, +)
        return product / totalVolume
    }

    public func extractFeature(_ type: FeatureType) -> Double {
        switch type {
        case .priceReturn: return priceReturn()
        case .logReturn: return logReturn()
        case .movingAverage: return movingAverage()
        case .exponentialMovingAverage: return ema()
        case .relativeStrength: return relativeStrength()
        case .volatility: return volatility()
        case .volumeRatio: return volumeRatio()
        case .priceToMA: return priceToMA()
        case .momentumOscillator: return momentumOscillator()
        case .rsi: return rsi()
        case .macdHistogram: return macdHistogram()
        case .stochK: return stochK()
        case .stochD: return stochD()
        case .williamsR: return williamsR()
        case .bollingerPosition: return bollingerPosition()
        case .volumeWeightedPrice: return volumeWeightedPrice()
        }
    }

    public func featureNames() -> [String] {
        FeatureType.allCases.map(\.rawValue)
    }

    public func featureArray() -> [Double] {
        FeatureType.allCases.map { extractFeature($0) }
    }
}

// MARK: - Feature Normalizer
public struct FeatureNormalizer: Sendable {
    private var means: [Double] = []
    private var stdDevs: [Double] = []
    private var minVals: [Double] = []
    private var maxVals: [Double] = []
    private var isFitted = false

    public init() {}

    public mutating func fit(_ features: [[Double]]) {
        guard let first = features.first, !first.isEmpty else { return }
        let nFeatures = first.count
        guard features.allSatisfy({ $0.count == nFeatures }) else { return }

        means = Array(repeating: 0.0, count: nFeatures)
        stdDevs = Array(repeating: 0.0, count: nFeatures)
        minVals = Array(repeating: .infinity, count: nFeatures)
        maxVals = Array(repeating: -Double.infinity, count: nFeatures)

        for featureSet in features {
            for index in 0..<nFeatures {
                let value = featureSet[index]
                means[index] += value
                minVals[index] = min(minVals[index], value)
                maxVals[index] = max(maxVals[index], value)
            }
        }

        for index in 0..<nFeatures {
            means[index] /= Double(features.count)
            let variance = features.reduce(0) { $0 + pow($1[index] - means[index], 2) } / Double(features.count)
            stdDevs[index] = sqrt(max(0, variance))
            if stdDevs[index] == 0 { stdDevs[index] = 1 }
        }
        isFitted = true
    }

    public func normalize(_ features: [Double]) -> [Double] {
        guard isFitted, features.count == means.count else { return features }
        return features.indices.map { index in
            (features[index] - means[index]) / stdDevs[index]
        }
    }

    public func minMaxScale(_ features: [Double]) -> [Double] {
        guard isFitted, features.count == minVals.count else { return features }
        return features.indices.map { index in
            maxVals[index] > minVals[index]
                ? (features[index] - minVals[index]) / (maxVals[index] - minVals[index])
                : 0.5
        }
    }
}
