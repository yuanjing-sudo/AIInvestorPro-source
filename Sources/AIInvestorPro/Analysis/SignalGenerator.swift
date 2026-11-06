// MARK: - Signal Generator
import Foundation

public enum SignalStrength: Double, CaseIterable, Sendable {
    case veryWeak = 0.1
    case weak = 0.3
    case moderate = 0.5
    case strong = 0.7
    case veryStrong = 0.9

    public var description: String {
        switch self {
        case .veryWeak: return "Very Weak"
        case .weak: return "Weak"
        case .moderate: return "Moderate"
        case .strong: return "Strong"
        case .veryStrong: return "Very Strong"
        }
    }

    /// Map an unbounded score magnitude onto the discrete strength scale.
    public static func from(magnitude: Double) -> SignalStrength {
        let value = abs(magnitude)
        switch value {
        case 0.75...: return .veryStrong
        case 0.55..<0.75: return .strong
        case 0.30..<0.55: return .moderate
        case 0.10..<0.30: return .weak
        default: return .veryWeak
        }
    }
}

public struct MarketData: Sendable {
    public let symbol: String
    public let price: Double
    public let rsi: Double
    public let macd: Double
    public let macdSignal: Double
    public let macdHistogram: Double
    public let sma20: Double
    public let sma50: Double
    public let ema12: Double
    public let ema26: Double
    public let bollingerUpper: Double
    public let bollingerLower: Double
    public let stochasticK: Double
    public let williamsR: Double
    public let atr: Double
    public let volume: Double
    public let regime: MarketRegime

    public init(
        symbol: String,
        price: Double,
        rsi: Double,
        macd: Double,
        macdSignal: Double,
        macdHistogram: Double,
        sma20: Double,
        sma50: Double,
        ema12: Double,
        ema26: Double,
        bollingerUpper: Double,
        bollingerLower: Double,
        stochasticK: Double,
        williamsR: Double,
        atr: Double,
        volume: Double,
        regime: MarketRegime
    ) {
        self.symbol = symbol
        self.price = price
        self.rsi = rsi
        self.macd = macd
        self.macdSignal = macdSignal
        self.macdHistogram = macdHistogram
        self.sma20 = sma20
        self.sma50 = sma50
        self.ema12 = ema12
        self.ema26 = ema26
        self.bollingerUpper = bollingerUpper
        self.bollingerLower = bollingerLower
        self.stochasticK = stochasticK
        self.williamsR = williamsR
        self.atr = atr
        self.volume = volume
        self.regime = regime
    }

    public var description: String {
        "\(symbol): RSI \(String(format: "%.1f", rsi)), MACD \(String(format: "%.4f", macd)), Regime \(regime.rawValue)"
    }
}

public final class SignalGenerator {
    private let config: SignalConfiguration

    public init(configuration: SignalConfiguration = SignalConfiguration()) {
        self.config = configuration
    }

    public func generateSignal(_ data: MarketData) -> (signal: TradeSignal, strength: SignalStrength, confidence: Double, reasons: [String]) {
        var scores: [Double] = []
        var reasons: [String] = []

        let rsiScore = calculateRSIScore(data.rsi)
        scores.append(rsiScore)
        if rsiScore > 0 {
            reasons.append("RSI oversold: \(String(format: "%.1f", data.rsi))")
        } else if rsiScore < 0 {
            reasons.append("RSI overbought: \(String(format: "%.1f", data.rsi))")
        }

        let macdScore = calculateMACDScore(data.macd, data.macdSignal, data.macdHistogram)
        scores.append(macdScore)
        if macdScore > 0 {
            reasons.append("MACD bullish crossover")
        } else if macdScore < 0 {
            reasons.append("MACD bearish crossover")
        }

        let maScore = calculateMAScore(data.sma20, data.sma50, data.ema12, data.ema26)
        scores.append(maScore)
        if maScore > 0 {
            reasons.append("Moving averages aligned bullishly")
        } else if maScore < 0 {
            reasons.append("Moving averages aligned bearishly")
        }

        let bbScore = calculateBBScore(data.price, data.bollingerUpper, data.bollingerLower)
        scores.append(bbScore)

        let stochScore = calculateStochasticScore(data.stochasticK, data.williamsR)
        scores.append(stochScore)

        let willrScore = calculateWillRScore(data.williamsR)
        scores.append(willrScore)

        let regimeAdjustment = calculateRegimeAdjustment(data.regime) * config.regimeWeight
        scores.append(regimeAdjustment)

        let compositeScore = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
        let strength = SignalStrength.from(magnitude: compositeScore)
        let confidence = min(1, abs(compositeScore) * 1.5 + 0.1)

        let signal: TradeSignal
        if compositeScore >= 0.5 {
            signal = .strongBuy
        } else if compositeScore >= 0.15 {
            signal = .buy
        } else if compositeScore <= -0.5 {
            signal = .strongSell
        } else if compositeScore <= -0.15 {
            signal = .sell
        } else {
            signal = .hold
        }

        if reasons.isEmpty {
            reasons.append("No directional edge")
        }
        return (signal, strength, confidence, reasons)
    }

    func calculateRSIScore(_ rsi: Double) -> Double {
        if rsi < config.rsiOversold { return 0.8 }
        if rsi > config.rsiOverbought { return -0.8 }
        if rsi < 40 { return 0.2 }
        if rsi > 60 { return -0.2 }
        return 0.0
    }

    func calculateMACDScore(_ macd: Double, _ signal: Double, _ histogram: Double) -> Double {
        if macd > signal && histogram > 0 { return 0.6 }
        if macd < signal && histogram < 0 { return -0.6 }
        if macd > 0 && histogram > 0 { return 0.3 }
        if macd < 0 && histogram < 0 { return -0.3 }
        return 0.0
    }

    func calculateMAScore(_ sma20: Double, _ sma50: Double, _ ema12: Double, _ ema26: Double) -> Double {
        if ema12 > ema26 && sma20 > sma50 { return 0.5 }
        if ema12 < ema26 && sma20 < sma50 { return -0.5 }
        if ema12 > ema26 { return 0.3 }
        if ema12 < ema26 { return -0.3 }
        return 0.0
    }

    func calculateBBScore(_ price: Double, _ upper: Double, _ lower: Double) -> Double {
        guard price > 0, upper > lower else { return 0 }
        if price > upper { return -0.5 }
        if price < lower { return 0.5 }
        if price > upper * 0.98 { return -0.3 }
        if price < lower * 1.02 { return 0.3 }
        return 0.0
    }

    func calculateStochasticScore(_ k: Double, _ williamsR: Double) -> Double {
        if k < 20 { return 0.7 }
        if k > 80 { return -0.7 }
        if williamsR < -80 { return 0.7 }
        if williamsR > -20 { return -0.7 }
        return 0.0
    }

    func calculateWillRScore(_ williamsR: Double) -> Double {
        if williamsR < -80 { return 0.8 }
        if williamsR > -20 { return -0.8 }
        return 0.0
    }

    func calculateRegimeAdjustment(_ regime: MarketRegime) -> Double {
        switch regime {
        case .bullish: return 0.3
        case .bearish: return -0.3
        case .sideways: return 0.0
        case .volatile: return 0.1
        case .unknown: return 0.0
        case .accumulation: return 0.2
        case .distribution: return -0.2
        }
    }
}

// MARK: - Signal Configuration
public struct SignalConfiguration: Sendable {
    public let rsiOversold: Double
    public let rsiOverbought: Double
    public let macdFastPeriod: Int
    public let macdSlowPeriod: Int
    public let macdSignalPeriod: Int
    public let bollingerStdDev: Double
    public let minSignalStrength: SignalStrength
    public let regimeWeight: Double

    public init(
        rsiOversold: Double = 30,
        rsiOverbought: Double = 70,
        macdFastPeriod: Int = 12,
        macdSlowPeriod: Int = 26,
        macdSignalPeriod: Int = 9,
        bollingerStdDev: Double = 2.0,
        minSignalStrength: SignalStrength = .moderate,
        regimeWeight: Double = 0.2
    ) {
        self.rsiOversold = rsiOversold
        self.rsiOverbought = rsiOverbought
        self.macdFastPeriod = macdFastPeriod
        self.macdSlowPeriod = macdSlowPeriod
        self.macdSignalPeriod = macdSignalPeriod
        self.bollingerStdDev = bollingerStdDev
        self.minSignalStrength = minSignalStrength
        self.regimeWeight = regimeWeight
    }
}
