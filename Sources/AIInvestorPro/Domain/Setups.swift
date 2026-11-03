// MARK: - Trading Setups
import Foundation

public struct TradeSetup: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let requiredIndicators: [String]
    public var isActive: Bool
    public var createdAt: Date
    public var performance: SetupPerformance?
    
    public init(name: String, description: String, requiredIndicators: [String] = []) {
        self.id = UUID().uuidString
        self.name = name
        self.description = description
        self.requiredIndicators = requiredIndicators
        self.isActive = true
        self.createdAt = Date()
        self.performance = nil
    }
}

public struct SetupPerformance {
    let totalTrades: Int
    let winningTrades: Int
    let losingTrades: Int
    let winRate: Double
    let averageReturn: Double
    let totalReturn: Double
    
    public var description: String {
        "\(name): \(totalTrades) trades, \(String(format: "%.1f%", winRate))% win rate, $\(String(format: "%.2f", totalReturn)) return"
    }
}

public enum SetupType: String, CaseIterable, Identifiable {
    case breakout = "breakout"
    case meanReversion = "mean_reversion"
    case momentum = "momentum"
    case trendFollowing = "trend_following"
    case reversal = "reversal"
    
    public var id: String { rawValue }
}

// MARK: - Specific Setup Implementations
public struct BreakoutSetup: TradeSetup {
    public let breakoutType: BreakoutType
    public let lookbackPeriod: Int
    public let volumeRequirement: Double
    
    public enum BreakoutType: String, CaseIterable {
        case resistance = "resistance"
        case support = "support"
        case channel = "channel"
        case triangle = "triangle"
    }
    
    public init(name: String = "Breakout", breakoutType: BreakoutType = .resistance, lookbackPeriod: Int = 20, volumeRequirement: Double = 1.5) {
        self.name = name
        self.description = "\(breakoutType.rawValue) breakout after \(lookbackPeriod)-period consolidation with \(volumeRequirement)x volume"
        self.requiredIndicators = ["sma", "volume", "rsi"]
        self.breakoutType = breakoutType
        self.lookbackPeriod = lookbackPeriod
        self.volumeRequirement = volumeRequirement
        super.init(name: name, description: description, requiredIndicators: requiredIndicators)
    }
}

public struct MeanReversionSetup: TradeSetup {
    public let entryZone: EntryZone
    public let lookbackPeriod: Int
    
    public enum EntryZone: String, CaseIterable {
        case overbought = "overbought"
        case oversold = "oversold"
        case valueArea = "value_area"
    }
    
    public init(name: String = "Mean Reversion", entryZone: EntryZone = .oversold, lookbackPeriod: Int = 14) {
        self.name = name
        self.description = "\(entryZone.rawValue) mean reentry after \(lookbackPeriod)-period deviation"
        self.requiredIndicators = ["rsi", "bollinger"]
        self.entryZone = entryZone
        self.lookbackPeriod = lookbackPeriod
        super.init(name: name, description: description, requiredIndicators: requiredIndicators)
    }
}

public struct MomentumSetup: TradeSetup {
    public let momentumPeriod: Int
    public let threshold: Double
    public let confirmationPeriod: Int
    
    public init(name: String = "Momentum", momentumPeriod: Int = 10, threshold: Double = 2.0, confirmationPeriod: Int = 3) {
        self.name = name
        self.description = "Momentum > \(threshold) over \(momentumPeriod) periods with \(confirmationPeriod)-period confirmation"
        self.requiredIndicators = ["rsi", "macd", "momentum"]
        self.momentumPeriod = momentumPeriod
        self.threshold = threshold
        self.confirmationPeriod = confirmationPeriod
        super.init(name: name, description: description, requiredIndicators: requiredIndicators)
    }
}

public struct TrendFollowingSetup: TradeSetup {
    public let fastPeriod: Int
    public let slowPeriod: Int
    public let trailStop: Bool
    
    public init(name: String = "Trend Following", fastPeriod: Int = 12, slowPeriod: Int = 26, trailStop: Bool = true) {
        self.name = name
        self.description = "EMA \(fastPeriod)/\(slowPeriod) trend following with \(trailStop ? "trailing stop" : "fixed stop")"
        self.requiredIndicators = ["ema", "macd"]
        self.fastPeriod = fastPeriod
        self.slowPeriod = slowPeriod
        self.trailStop = trailStop
        super.init(name: name, description: description, requiredIndicators: requiredIndicators)
    }
}

// MARK: - Setup Registry
public final class SetupRegistry: ObservableObject {
    @Published public var setups: [TradeSetup] = []
    
    public init() {
        // Default setups
        setups = [
            BreakoutSetup(),
            MeanReversionSetup(),
            MomentumSetup(),
            TrendFollowingSetup()
        ]
    }
    
    public func setup(_ type: SetupType) -> TradeSetup? {
        setups.first { /* match by indicators or name */ }
    }
    
    public func activate(_ setup: TradeSetup) {
        if let index = setups.firstIndex(where: { $0.id == setup.id }) {
            setups[index].isActive = true
        }
    }
}
