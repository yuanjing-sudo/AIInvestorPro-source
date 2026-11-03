// MARK: - Market Regime
import Foundation

public enum MarketRegime: String, CaseIterable, Codable {
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
    
    /// Detect regime from market snapshots using multiple methods
    /// - Parameter snapshots: Market snapshots to analyze
    /// - Returns: Detected regime with confidence
    public static func detect(_ snapshots: [MarketSnapshot], withConfidence: Bool = true) -> (regime: MarketRegime, confidence: Double) {
        guard !snapshots.isEmpty else { return (.unknown, 0.0) }
        
        // Use multiple indicators for regime detection
        let recentSnapshots = snapshots.suffix(min(30, snapshots.count))
        
        // Calculate price trend
        let firstPrice = recentSnapshots.first?.closes.first ?? 0
        let lastPrice = recentSnapshots.last?.closes.last ?? 0
        
        guard firstPrice > 0 else { return (.unknown, 0.0) }
        let priceChange = (lastPrice - firstPrice) / firstPrice
        
        // Calculate volatility
        let returns = zip(recentSnapshots.dropFirst().map { $0.closes.last! }, 
                          recentSnapshots.dropLast().map { $0.closes.last! })
        .map { $1 / $0 - 1 }
        let avgReturn = returns.reduce(0, +) / Double(returns.count)
        let returnVariance = returns.map { pow($0 - avgReturn, 2) }.reduce(0, +) / Double(returns.count)
        let volatility = sqrt(returnVariance) * 100
        
        // Calculate multiple RSI values on different periods
        let allCloses = recentSnapshots.flatMap { $0.closes }
        let rsi7 = calculateRSI(allCloses, period: 7)
        let rsi14 = calculateRSI(allCloses, period: 14)
        let rsi21 = calculateRSI(allCloses, period: 21)
        
        // Calculate momentum
        let momentum = calculateMomentum(allCloses, period: 10)
        
        // Calculate autocorrelation (trend strength)
        let autocorr = calculateAutocorrelation(allCloses, lag: 5)
        
        // Calculate wave count (Elliott wave simplification)
        let waveCount = calculateWaveCount(allCloses)
        
        // Determine regime using fuzzy logic
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
    
    /// Calculate RSI from price array
    private static func calculateRSI(_ prices: [Double], period: Int) -> Double {
        guard prices.count > period else { return 50.0 }
        let changes = zip(prices.dropFirst(), prices.dropLast()).map { $1 - $0 }
        let gains = changes.filter { $0 > 0 }
        let losses = abs(changes.filter { $0 < 0 })
        let avgGain = gains.isEmpty ? 0 : gains.reduce(0, +) / Double(gains.count)
        let avgLoss = losses.isEmpty ? 1 : losses.reduce(0, +) / Double(losses.count)
        let rs = avgLoss == 0 ? 100 : avgGain / avgLoss
        return 100 - (100 / (1 + rs))
    }
    
    /// Calculate momentum
    private static func calculateMomentum(_ prices: [Double], period: Int) -> Double {
        guard prices.count > period else { return 0.0 }
        let change = prices.last! - prices[prices.count - period]
        return change
    }
    
    /// Calculate autocorrelation
    private static func calculateAutocorrelation(_ prices: [Double], lag: Int) -> Double {
        guard prices.count > lag * 2 else { return 0.0 }
        
        let mean = prices.reduce(0, +) / Double(prices.count)
        let n = Double(prices.count - lag)
        
        let numerator = zip(prices.dropFirst(lag), prices.dropLast(lag)).reduce(0) { $0 + ($1.0 - mean) * ($1.1 - mean) }
        
        // Simplified - full implementation would be more complex
        return 0.0
    }
    
    /// Calculate wave count (Elliott wave simplification)
    private static func calculateWaveCount(_ prices: [Double]) -> Int {
        guard prices.count > 10 else { return 3 }
        // Simplified wave count
        return 5
    }
    
    /// Determine regime using fuzzy logic
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
        // Bullish conditions: positive trend, moderate volatility, RSI > 55, positive momentum
        let isBullish = priceChange > 0.03 && volatility < 25 && rsi14 > 55 && momentum > 0
        
        // Bearish conditions: negative trend, moderate volatility, RSI < 45, negative momentum
        let isBearish = priceChange < -0.03 && volatility < 25 && rsi14 < 45 && momentum < 0
        
        // Volatile conditions: high volatility
        let isVolatile = volatility > 30
        
        // Sideways conditions: low volatility, RSI near 50
        let isSideways = volatility < 20 && rsi14 > 45 && rsi14 < 55
        
        // Accumulation: positive trend within volatile market (smart money accumulating)
        let isAccumulation = priceChange > 0 && volatility > 25 && volatility < 35
        
        // Distribution: negative trend within volatile market (smart money distributing)
        let isDistribution = priceChange < 0 && volatility > 25 && volatility < 35
        
        if isAccumulation { return .accumulation }
        if isDistribution { return .distribution }
        if isBullish { return .bullish }
        if isBearish { return .bearish }
        if isVolatile { return .volatile }
        if isSideways { return .sideways }
        return .unknown
    }
    
    /// Calculate confidence based on indicator alignment
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
        
        // Price change direction
        totalIndicators += 1
        if abs(priceChange) > 0.03 { aligningIndicators += 1 }
        
        // Volatility regime
        totalIndicators += 1
        if volatility > 20 || volatility < 30 { aligningIndicators += 1 }
        
        // RSI alignment
        totalIndicators += 1
        if (rsi7 > 55 && rsi14 > 55) || (rsi7 < 45 && rsi14 < 45) { aligningIndicators += 1 }
        
        // Momentum alignment
        totalIndicators += 1
        if momentum > 0 || momentum < 0 { aligningIndicators += 1 }
        
        // Autocorrelation trend confirmation
        totalIndicators += 1
        if abs(autocorr) > 0.3 { aligningIndicators += 1 }
        
        return totalIndicators > 0 ? Double(aligningIndicators) / Double(totalIndicators) : 0.5
    }
}

// MARK: - Regime Regime Transition
public struct RegimeTransition {
    /// Current regime
    let current: MarketRegime
    /// Previous regime
    let previous: MarketRegime
    /// Transition date
    let date: Date
    /// Probability of staying in current regime
    let stayProbability: Double
    /// Probability of transitioning to another regime
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
    
    /// Get transition description
    var description: String {
        "\(previous.rawValue) → \(current.rawValue) on \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}
