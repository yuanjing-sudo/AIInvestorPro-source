// MARK: - Analysis Result
import Foundation

public struct AnalysisResult {
    public let symbol: String
    public let currentPrice: Double
    public let totalReturn: Double
    public let recentReturn: Double
    public let annualizedVolatility: Double
    public let sma20: Double
    public let sma50: Double
    public let ema12: Double
    public let ema26: Double
    public let macd: Double
    public let macdSignal: Double
    public let rsi: Double
    public let supportLevel: Double
    public let resistanceLevel: Double
    public let regime: MarketRegime
    public let technical: TechnicalSignal
    
    public init(
        symbol: String,
        currentPrice: Double,
        totalReturn: Double,
        recentReturn: Double,
        annualizedVolatility: Double,
        sma20: Double,
        sma50: Double,
        ema12: Double,
        ema26: Double,
        macd: Double,
        macdSignal: Double,
        rsi: Double,
        supportLevel: Double,
        resistanceLevel: Double,
        regime: MarketRegime,
        technical: TechnicalSignal
    ) {
        self.symbol = symbol
        self.currentPrice = currentPrice
        self.totalReturn = totalReturn
        self.recentReturn = recentReturn
        self.annualizedVolatility = annualizedVolatility
        self.sma20 = sma20
        self.sma50 = sma50
        self.ema12 = ema12
        self.ema26 = ema26
        self.macd = macd
        self.macdSignal = macdSignal
        self.rsi = rsi
        self.supportLevel = supportLevel
        self.resistanceLevel = resistanceLevel
        self.regime = regime
        self.technical = technical
    }
}

// MARK: - Technical Signal
public struct TechnicalSignal {
    public let rsi: Double
    public let macd: Double
    public let macdSignal: Double
    public let aboveSMA20: Bool
    public let aboveSMA50: Bool
    
    public init(
        rsi: Double,
        macd: Double,
        macdSignal: Double,
        aboveSMA20: Bool,
        aboveSMA50: Bool
    ) {
        self.rsi = rsi
        self.macd = macd
        self.macdSignal = macdSignal
        self.aboveSMA20 = aboveSMA20
        self.aboveSMA50 = aboveSMA50
    }
}
