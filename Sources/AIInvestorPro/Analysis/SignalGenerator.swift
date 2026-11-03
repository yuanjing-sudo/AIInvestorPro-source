// MARK: - Signal Generator
import Foundation

public enum SignalStrength: Double, CaseIterable {
    case veryWeak = 0.1
    case weak = 0.3
    case moderate = 0.5
    case strong = 0.7
    case veryStrong = 0.9
    
    var description: String {
        switch self {
        case .veryWeak: return "Very Weak"
        case .weak: return "Weak"
        case .moderate: return "Moderate"
        case .strong: return "Strong"
        case .veryStrong: return "Very Strong"
        }
    }
}


public struct MarketData {
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
    
    public var description: String {
        "\(symbol): RSI \(String(format: "%.1f", rsi)), MACD \(String(format: "%.4f", macd)), Regime \(regime.rawValue)"
    }
}

public class SignalGenerator {
    private let config: SignalConfiguration
    
    public init(configuration: SignalConfiguration = SignalConfiguration()) {
        self.config = configuration
    }
    
    // Generate a trading signal based on technical indicators
    public func generateSignal(_ data: MarketData) -> (signal: TradeSignal, strength: SignalStrength, confidence: Double, reasons: [String]) {
        var scores: [Double] = []
        var reasons: [String] = []
        
        // RSI-based scoring
        let rsiScore = calculateRSIScore(data.rsi)
        scores.append(rsiScore)
        if rsiScore > 0 {
            reasons.append("RSI oversold/overbought: \(String(format: "%.1f", data.rsi))")
        }
        
        // MACD-based scoring
        let macdScore = calculateMACDScore(data.macd, data.macdSignal, data.macdHistogram)
        scores.append(macdScore)
        if macdScore > 0 {
            reasons.append("MACD bullish crossover")
        }
        
        // Moving average crossover scoring
        let maScore = calculateMAScore(data.sma20, data.sma50, data.ema12, data.ema26)
        scores.append(maScore)
        if maScore > 0 {
            reasons.append("MA bullish crossover")
        }
        
        // Bollinger Band squeeze/breakout
        let bbScore = calculateBBScore(data.price, data.bollingerUpper, data.bollingerLower)
        scores.append(bbScore)
        if bbScore > 0 {
            reasons.append("Price near upper Bollinger Band")
        }
        
        // Stochastic scoring
        let stochScore = calculateStochasticScore(data.stochasticK, data.williamsR)
        scores.append(stochScore)
        if stochScore > 0 {
            reasons.append("Stochastic oversold")
        }
        
        // Williams %R scoring
        let willrScore = calculateWillRScore(data.williamsR)
        scores.append(willrScore)
        if willrScore > 0 {
            reasons.append("Williams %R oversold")
        }
        
        // Regime adjustment
        let regimeAdjustment = calculateRegimeAdjustment(data.regime)
        scores.append(regimeAdjustment)
        
        // Calculate composite score
        let compositeScore = scores.reduce(0, +) / Double(scores.count)
        let strength = SignalStrength(rawValue: max(0, min(1, compositeScore))) ?? .moderate
        
        // Determine signal
        let signal: TradeSignal
        let confidence: Double
        
        switch strength {
        case .veryStrong:
            signal = compositeScore > 0 ? .strongBuy : .strongSell
            confidence = abs(compositeScore)
        case .strong:
            signal = compositeScore > 0 ? .buy : .sell
            confidence = abs(compositeScore)
        case .moderate:
            signal = compositeScore > 0.1 ? .buy : compositeScore < -0.1 ? .sell : .hold
            confidence = abs(compositeScore) * 0.8 + 0.2
        case .weak:
            signal = .hold
            confidence = 0.3
        case .veryWeak:
            signal = .hold
            confidence = 0.1
        }
        
        return (signal, strength, confidence, reasons)
    }
    
    // RSI scoring: returns positive if oversold (buy) or overbought (sell)
    func calculateRSIScore(_ rsi: Double) -> Double {
        if rsi < 30 { return 0.8 // Oversold }
        if rsi > 70 { return -0.8 // Overbought }
        if rsi < 40 { return 0.2 }
        if rsi > 60 { return -0.2 }
        return 0.0
    }
    
    // MACD scoring
    func calculateMACDScore(_ macd: Double, _ signal: Double, _ histogram: Double) -> Double {
        if macd > signal && histogram > 0 { return 0.6 } // Bullish
        if macd < signal && histogram < 0 { return -0.6 } // Bearish }
        if macd > 0 && histogram > 0 { return 0.3 }
        if macd < 0 && histogram < 0 { return -0.3 }
        return 0.0
    }
    
    // Moving average scoring
    func calculateMAScore(_ sma20: Double, _ sma50: Double, _ ema12: Double, _ ema26: Double) -> Double {
        if ema12 > ema26 && sma20 > sma50 { return 0.5 }
        if ema12 < ema26 && sma20 < sma50 { return -0.5 }
        if ema12 > ema26 { return 0.3 }
        if ema12 < ema26 { return -0.3 }
        return 0.0
    }
    
    // Bollinger Band scoring
    func calculateBBScore(_ price: Double, _ upper: Double, _ lower: Double) -> Double {
        let bandWidth = (upper - lower) / price
        if price > upper { return -0.5 } // Above upper band
        if price < lower { return 0.5 } // Below lower band }
        if price > upper * 0.98 { return 0.3 } // Near upper band
        if price < lower * 1.02 { return -0.3 } // Near lower band
        return 0.0
    }
    
    // Stochastic scoring
    func calculateStochasticScore(_ k: Double, _ williamsR: Double) -> Double {
        if k < 20 { return 0.7 } // Oversold
        if k > 80 { return -0.7 } // Overbought }
        if williamsR < -80 { return 0.7 }
        if williamsR > -20 { return -0.7 }
        return 0.0
    }
    
    // Williams %R scoring
    func calculateWillRScore(_ williamsR: Double) -> Double {
        if williamsR < -80 { return 0.8 } // Oversold
        if williamsR > -20 { return -0.8 } // Overbought }
        return 0.0
    }
    
    // Regime adjustment
    func calculateRegimeAdjustment(_ regime: MarketRegime) -> Double {
        switch regime {
        case .bullish: return 0.3
        case .bearish: return -0.3
        case .sideways: return 0.0
        case .volatile: return 0.1 // Small bias
        case .unknown: return 0.0
        }
    }
}

// MARK: - Signal Configuration
public struct SignalConfiguration {
    /// RSI oversold threshold
    let rsiOversold: Double = 30
    /// RSI overbought threshold
    let rsiOverbought: Double = 70
    /// MACD fast/slow period configuration
    let macdFastPeriod: Int = 12
    let macdSlowPeriod: Int = 26
    let macdSignalPeriod: Int = 9
    /// Bollinger Band std dev
    let bollingerStdDev: Double = 2.0
    /// Minimum signal strength for trade
    let minSignalStrength: SignalStrength = .moderate
    /// Regime weight in signal calculation
    let regimeWeight: Double = 0.2
}
```

