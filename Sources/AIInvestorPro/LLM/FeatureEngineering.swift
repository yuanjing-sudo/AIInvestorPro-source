// MARK: - Feature Engineering
import Foundation

public enum FeatureType: String, CaseIterable {
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
        rawValue.replacingUnderscoresWithSpaces()
    }
}

public struct ExtractedFeature: Equatable {
    public let featureType: FeatureType
    public let value: Double
    public let timestamp: Date
    public let symbol: String?
    
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
    
    public init(prices: [Double], highs: [Double]? = nil, lows: [Double]? = nil, volumes: [Double]? = nil, lookback: Int = 20) {
        self.prices = prices
        self.highs = highs ?? prices.map { $0 * 1.02 }
        self.lows = lows ?? prices.map { $0 * 0.98 }
        self.volumes = volumes ?? Array(repeating: 1_000_000, count: prices.count)
        self.timestamps = (0..<prices.count).map { Date().addingTimeInterval(-86400 * Double($0)) }
        self.lookback = max(1, lookback)
    }
    
    // Extract all features as a dictionary
    public func extractAllFeatures() -> [FeatureType: Double] {
        var features: [FeatureType: Double] = [:]
        
        // Basic price features
        features[.priceReturn] = priceReturn()
        features[.logReturn] = logReturn()
        
        // Trend features
        features[.movingAverage] = movingAverage()
        features[.exponentialMovingAverage] = ema()
        
        // Momentum features
        features[.relativeStrength] = relativeStrength()
        features[.volatility] = volatility()
        
        // Volume features
        features[.volumeRatio] = volumeRatio()
        
        // Technical indicators
        features[.rsi] = rsi()
        features[.macdHistogram] = macdHistogram()
        features[.stochK] = stochK()
        features[.stochD] = stochD()
        features[.williamsR] = williamsR()
        features[.bollingerPosition] = bollingerPosition()
        features[.volumeWeightedPrice] = volumeWeightedPrice()
        
        return features
    }
    
    // Price return over lookback period
    private func priceReturn() -> Double {
        guard prices.count > lookback else { return 0 }
        let start = prices[prices.count - lookback - 1]
        let end = prices.last!
        return (end - start) / max(1, start)
    }
    
    // Log return
    private func logReturn() -> Double {
        guard prices.count > 1 else { return 0 }
        let last = prices.last!
        let prev = prices[prices.count - 2]
        return log(last / max(1, prev))
    }
    
    // Simple moving average of last lookback prices
    private func movingAverage() -> Double {
        guard prices.count >= lookback else { return prices.last ?? 0 }
        let window = Array(prices[prices.count - lookback...])
        return window.reduce(0, +) / Double(window.count)
    }
    
    // Exponential moving average
    private func ema() -> Double {
        guard prices.count >= lookback else { return prices.last ?? 0 }
        let multiplier = 2.0 / (Double(lookback) + 1)
        var ema = prices[0]
        for i in 1..<prices.count {
            ema = (prices[i] - ema) * multiplier + ema
        }
        return ema
    }
    
    // Relative strength vs lookback period average
    private func relativeStrength() -> Double {
        guard prices.count > lookback else { return 0.5 }
        let currentPrice = prices.last!
        let avgLookback = movingAverage()
        return avgLookback > 0 ? currentPrice / avgLookback : 0.5
    }
    
    // Volatility (standard deviation of returns)
    private func volatility() -> Double {
        guard prices.count > lookback + 1 else { return 0 }
        let returns = zip(prices.dropFirst(), prices.dropLast()).map { $1 / $0 - 1 }
        let subset = Array(returns.suffix(lookback))
        let mean = returns.reduce(0, +) / Double(returns.count)
        let variance = subset.map { pow($0 - mean, 2) }.reduce(0, +) / Double(subset.count)
        return sqrt(variance) * sqrt(252) * 100 // Annualized percentage
    }
    
    // Volume ratio: current volume vs average volume
    private func volumeRatio() -> Double {
        guard prices.count > 1 else { return 1.0 }
        let currentVolume = volumes.last!
        let avgVolume = volumes.dropLast().reduce(0, +) / Double(volumes.count - 1)
        return currentVolume / max(1, avgVolume)
    }
    
    // Price relative to moving average
    private func priceToMA() -> Double {
        let ma = movingAverage()
        return ma > 0 ? prices.last! / ma : 1.0
    }
    
    // Momentum oscillator: rate of change
    private func momentumOscillator() -> Double {
        guard prices.count >= 10 else { return 0 }
        let current = prices.last!
        let tenDaysAgo = prices[prices.count - 10]
        return tenDaysAgo > 0 ? (current - tenDaysAgo) / tenDaysAgo * 100 : 0
    }
    
    // RSI (Relative Strength Index) - simplified 14-period
    private func rsi() -> Double {
        guard prices.count >= 15 else { return 50.0 }
        let changes = zip(prices.dropFirst(), prices.dropLast()).map { $1 - $0 }
        let gains = changes.filter { $0 > 0 }
        let losses = abs(changes.filter { $0 < 0 })
        let avgGain = gains.isEmpty ? 0 : gains.reduce(0, +) / Double(gains.count)
        let avgLoss = losses.isEmpty ? 1 : losses.reduce(0, +) / Double(losses.count)
        let rs = avgLoss == 0 ? 100 : avgGain / avgLoss
        return 100 - (100 / (1 + rs))
    }
    
    // MACD histogram simplified
    private func macdHistogram() -> Double {
        guard prices.count >= 26 else { return 0 }
        let ema12 = ema(fast: 12)
        let ema26 = ema(fast: 26)
        return ema12 - ema26 // Simplified histogram
    }
    
    // Stochastic K (14-period)
    private func stochK() -> Double {
        guard prices.count >= 15 else { return 50.0 }
        let lookback = 14
        let lowLow = prices[prices.count - lookback - 1...].min() ?? prices.last!
        let highHigh = prices[prices.count - lookback - 1...].max() ?? prices.last!
        let current = prices.last!
        return (current - lowLow) / (highHigh - lowLow) * 100
    }
    
    // Stochastic D (3-period SMA of K)
    private func stochD() -> Double {
        // Simplified: return K value
        stochK()
    }
    
    // Williams %R (14-period)
    private func williamsR() -> Double {
        guard prices.count >= 15 else { return -50.0 }
        let lookback = 14
        let lowLow = prices[prices.count - lookback - 1...].min() ?? prices.last!
        let highHigh = prices[prices.count - lookback - 1...].max() ?? prices.last!
        let current = prices.last!
        return -(highHigh - current) / (highHigh - lowLow) * 100
    }
    
    // Bollinger Band position (0 = lower band, 1 = upper band)
    private func bollingerPosition() -> Double {
        guard prices.count >= 20 else { return 0.5 }
        let sma = movingAverage()
        let stdDev: Double = sqrt(zip(zip(prices, highs), lows).map { ($0.1 - $0.2) ** 2 + ($0.1 - $0.3) ** 2 }.reduce(0, +) / Double(prices.count))
        let upperBand = sma + 2 * stdDev
        let lowerBand = sma - 2 * stdDev
        let price = prices.last!
        return price > lowerBand && price < upperBand ? (price - lowerBand) / (upperBand - lowerBand) : 0.5
    }
    
    // Volume Weighted Price (VWAP approximation)
    private func volumeWeightedPrice() -> Double {
        guard prices.count > 1, volumes.count > 1 else { return prices.last ?? 0 }
        let priceVolumeProduct = zip(prices, volumes).map { $0 * $1 }.reduce(0, +)
        let totalVolume = volumes.reduce(0, +)
        return totalVolume > 0 ? priceVolumeProduct / totalVolume : prices.last!
    }
    
    // Extract single feature by type
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
    
    // Get feature names for ML input
    public func featureNames() -> [String] {
        FeatureType.allCases.map { $0.rawValue }
    }
    
    // Get all features as array for ML model input
    public func featureArray() -> [Double] {
        extractAllFeatures().map { $0.value }
    }
}

// MARK: - Feature Normalizer
public struct FeatureNormalizer {
    private var means: [Double] = []
    private var stdDevs: [Double] = []
    private var minVals: [Double] = []
    private var maxVals: [Double] = []
    private var isFitted = false
    
    public mutating func fit(_ features: [[Double]]) {
        guard !features.isEmpty else { return }
        
        let nFeatures = features[0].count
        means = Array(repeating: 0.0, count: nFeatures)
        stdDevs = Array(repeating: 0.0, count: nFeatures)
        minVals = Array(repeating: Double.infinity, count: nFeatures)
        maxVals = Array(repeating: -Double.infinity, count: nFeatures)
        
        for featureSet in features {
            for j in 0..<nFeatures {
                let val = featureSet[j]
                means[j] += val
                minVals[j] = min(minVals[j], val)
                maxVals[j] = max(maxVals[j], val)
            }
        }
        
        for j in 0..<nFeatures {
            means[j] /= Double(features.count)
            if maxVals[j] > minVals[j] {
                stdDevs[j] = sqrt(pow(maxVals[j] - means[j], 2) + pow(minVals[j] - means[j], 2)) / 2 // Simplified
            } else {
                stdDevs[j] = 1.0
            }
        }
        
        isFitted = true
    }
    
    // Z-score normalize a single feature set
    public func normalize(_ features: [Double]) -> [Double] {
        guard isFitted && features.count == means.count else { return features }
        
        return zip(features, means, stdDevs).map { (val, mean, std) in
            (val - mean) / std
        }
    }
    
    // Min-max scale a feature set to [0, 1]
    public func minMaxScale(_ features: [Double]) -> [Double] {
        guard isFitted && features.count == minVals.count else { return features }
        
        return zip(features, minVals, maxVals).map { (val, minV, maxV) in
            maxV > minV ? (val - minV) / (maxV - minV) : 0.5
        }
    }
}
