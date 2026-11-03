// MARK: - Technical Indicators
import Foundation

public struct TechnicalIndicators {
    /// Calculate all major technical indicators from closing prices
    public static func calculate(from prices: [Double], high: [Double]? = nil, low: [Double]? = nil, volume: [Double]? = nil) -> TechnicalIndicators {
        guard prices.count >= 26 else {
            return TechnicalIndicators()
        }
        
        // RSI (14-period)
        let rsi = RSI(prices, period: 14)
        
        // MACD (12,26,9)
        let macdLine = EMA(prices, period: 12) - EMA(prices, period: 26)
        let macdSignal = MACDSignal(prices: prices, fastPeriod: 12, slowPeriod: 26, signalPeriod: 9)
        let macdHistogram = macdLine - macdSignal
        
        // Moving Averages
        let sma20 = SMA(prices, period: 20)
        let sma50 = prices.count >= 50 ? SMA(prices, period: 50) : prices.last!
        let ema12 = EMA(prices, period: 12)
        let ema26 = EMA(prices, period: 26)
        
        // Bollinger Bands (20-period, 2 standard deviations)
        let bollinger = BollingerBands(prices: prices, period: 20, stdDev: 2.0)
        
        // Stochastic Oscillator (14-period)
        let stochastic = StochasticOscillator(prices: prices, period: 14)
        
        // Williams %R (14-period)
        let williamsR = WilliamsR(prices: prices, period: 14)
        
        // Average True Range (14-period)
        let atr = AverageTrueRange(high: high ?? prices, low: low ?? prices, close: prices, period: 14)
        
        // Momentum
        let momentum = Momentum(prices: prices, period: 10)
        
        return TechnicalIndicators(
            rsi: rsi,
            macd: macdLine,
            macdSignal: macdSignal,
            macdHistogram: macdHistogram,
            sma20: sma20,
            sma50: sma50,
            ema12: ema12,
            ema26: ema26,
            bollingerUpper: bollinger.upper,
            bollingerLower: bollinger.lower,
            bollingerMiddle: bollinger.middle,
            stochasticK: stochastic.k,
            stochasticD: stochastic.d,
            williamsR: williamsR.value,
            atr: atr.value,
            momentum: momentum.value
        )
    }
    
    // RSI (Relative Strength Index)
    private static func RSI(_ prices: [Double], period: Int) -> Double {
        guard prices.count > period else { return 50.0 }
        let changes = zip(prices.dropFirst(), prices.dropLast()).map { $1 - $0 }
        let gains = changes.filter { $0 > 0 }
        let losses = abs(changes.filter { $0 < 0 })
        let avgGain = gains.isEmpty ? 0 : gains.reduce(0, +) / Double(gains.count)
        let avgLoss = losses.isEmpty ? 1 : losses.reduce(0, +) / Double(losses.count)
        let rs = avgLoss == 0 ? 100 : avgGain / avgLoss
        return 100 - (100 / (1 + rs))
    }
    
    // EMA (Exponential Moving Average)
    private static func EMA(_ prices: [Double], period: Int) -> Double {
        guard prices.count >= period else { return prices.last ?? 0 }
        let multiplier = 2.0 / (Double(period) + 1)
        var ema = prices[0]
        for i in 1..<prices.count {
            ema = (prices[i] - ema) * multiplier + ema
        }
        return ema
    }
    
    // SMA (Simple Moving Average)
    private static func SMA(_ prices: [Double], period: Int) -> Double {
        guard prices.count >= period else { return prices.last ?? 0 }
        let start = prices.count - period
        let subset = Array(prices[start...])
        return subset.reduce(0, +) / Double(subset.count)
    }
}

// MARK: - Bollinger Bands
private struct BollingerBands {
    let upper: Double
    let lower: Double
    let middle: Double
    
    init(prices: [Double], period: Int, stdDev: Double) {
        guard prices.count >= period else {
            self.upper = prices.last ?? 0
            self.lower = prices.last ?? 0
            self.middle = prices.last ?? 0
            return
        }
        
        let subset = Array(prices[prices.count-period...])
        let middle = subset.reduce(0, +) / Double(subset.count)
        let squaredDev = subset.map { pow($0 - middle, 2) }.reduce(0, +) / Double(max(subset.count - 1, 1))
        let stdDevValue = sqrt(squaredDev)
        
        self.upper = middle + (stdDevValue * stdDev)
        self.lower = middle - (stdDevValue * stdDev)
        self.middle = middle
    }
}

// MARK: - Stochastic Oscillator
private struct StochasticOscillator {
    let k: Double // %K
    let d: Double // %D
    
    init(prices: [Double], period: Int) {
        guard prices.count >= period + 1 else {
            self.k = 50.0
            self.d = 50.0
            return
        }
        
        let subset = Array(prices[prices.count-period-1...])
        let lowLow = subset.min() ?? subset.first!
        let highHigh = subset.max() ?? subset.first!
        
        let currentClose = prices.last!
        self.k = (currentClose - lowLow) / (highHigh - lowLow) * 100
        // %D is a 3-period SMA of %K - simplified to just return k
        self.d = k
    }
}

// MARK: - Williams %R
private struct WilliamsR {
    let value: Double
    
    init(prices: [Double], period: Int) {
        guard prices.count >= period + 1 else {
            self.value = -50.0
            return
        }
        
        let subset = Array(prices[prices.count-period-1...])
        let highHigh = subset.max() ?? subset.first!
        let lowLow = subset.min() ?? subset.first!
        let currentClose = prices.last!
        
        self.value = -(highHigh - currentClose) / (highHigh - lowLow) * 100
    }
}

// MARK: - Average True Range
private struct AverageTrueRange {
    let value: Double
    
    init(high: [Double], low: [Double], close: [Double], period: Int) {
        guard close.count >= period + 1 else {
            self.value = 0.0
            return
        }
        
        // True Range = max(high - low, abs(high - previousClose), abs(low - previousClose)
        var trueRanges: [Double] = []
        for i in 1..<close.count {
            let tr = max(
                high[i] - low[i],
                abs(high[i] - close[i-1]),
                abs(low[i] - close[i-1])
            )
            trueRanges.append(tr)
        }
        
        // Average True Range = mean of true ranges over period
        let start = trueRanges.count - period + 1
        let endIndex = max(start, 0)
        let count = max(trueRanges.count - endIndex, 1)
        let subset = Array(trueRanges[endIndex...])
        self.value = subset.reduce(0, +) / Double(count)
    }
}

// MARK: - Momentum
private struct Momentum {
    let value: Double
    
    init(prices: [Double], period: Int) {
        guard prices.count > period else {
            self.value = 0.0
            return
        }
        let change = prices.last! - prices[prices.count - period]
        self.value = change
    }
}
