// MARK: - Trading Setups
import Foundation

public enum SetupType: String, CaseIterable, Identifiable {
    case breakout = "breakout"
    case meanReversion = "mean_reversion"
    case momentum = "momentum"
    case trendFollowing = "trend_following"
    case reversal = "reversal"
    
    public var id: String { rawValue }
}

// MARK: - Setup Performance
public struct SetupPerformance {
    public let totalTrades: Int
    public let winningTrades: Int
    public let losingTrades: Int
    public let winRate: Double
    public let averageReturn: Double
    public let totalReturn: Double
    
    public init(
        totalTrades: Int = 0,
        winningTrades: Int = 0,
        losingTrades: Int = 0,
        winRate: Double = 0,
        averageReturn: Double = 0,
        totalReturn: Double = 0
    ) {
        self.totalTrades = totalTrades
        self.winningTrades = winningTrades
        self.losingTrades = losingTrades
        self.winRate = winRate
        self.averageReturn = averageReturn
        self.totalReturn = totalReturn
    }
}

// MARK: - Specific Setup Implementations
public struct BreakoutSetup: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let requiredIndicators: [String]
    public var isActive: Bool
    public var createdAt: Date
    public var performance: SetupPerformance?
    public let breakoutType: BreakoutType
    public let lookbackPeriod: Int
    public let volumeRequirement: Double
    
    public enum BreakoutType: String, CaseIterable {
        case resistance = "resistance"
        case support = "support"
        case channel = "channel"
        case triangle = "triangle"
    }
    
    public init(
        id: String = UUID().uuidString,
        name: String = "Breakout",
        breakoutType: BreakoutType = .resistance,
        lookbackPeriod: Int = 20,
        volumeRequirement: Double = 1.5
    ) {
        self.id = id
        self.name = name
        self.breakoutType = breakoutType
        self.lookbackPeriod = lookbackPeriod
        self.volumeRequirement = volumeRequirement
        self.description = "\(breakoutType.rawValue) breakout after \(lookbackPeriod)-period consolidation with \(volumeRequirement)x volume"
        self.requiredIndicators = ["sma", "volume", "rsi"]
        self.isActive = true
        self.createdAt = Date()
        self.performance = nil
    }
}

public func == (lhs: BreakoutSetup, rhs: BreakoutSetup) -> Bool {
    lhs.id == rhs.id
}

public struct MeanReversionSetup: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let requiredIndicators: [String]
    public var isActive: Bool
    public var createdAt: Date
    public var performance: SetupPerformance?
    public let entryZone: EntryZone
    public let lookbackPeriod: Int
    
    public enum EntryZone: String, CaseIterable {
        case overbought = "overbought"
        case oversold = "oversold"
        case valueArea = "value_area"
    }
    
    public init(
        id: String = UUID().uuidString,
        name: String = "Mean Reversion",
        entryZone: EntryZone = .oversold,
        lookbackPeriod: Int = 14
    ) {
        self.id = id
        self.name = name
        self.entryZone = entryZone
        self.lookbackPeriod = lookbackPeriod
        self.description = "\(entryZone.rawValue) mean reentry after \(lookbackPeriod)-period deviation"
        self.requiredIndicators = ["rsi", "bollinger"]
        self.isActive = true
        self.createdAt = Date()
        self.performance = nil
    }
}

public func == (lhs: MeanReversionSetup, rhs: MeanReversionSetup) -> Bool {
    lhs.id == rhs.id
}

public struct MomentumSetup: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let requiredIndicators: [String]
    public var isActive: Bool
    public var createdAt: Date
    public var performance: SetupPerformance?
    public let momentumPeriod: Int
    public let threshold: Double
    public let confirmationPeriod: Int
    
    public init(
        id: String = UUID().uuidString,
        name: String = "Momentum",
        momentumPeriod: Int = 10,
        threshold: Double = 2.0,
        confirmationPeriod: Int = 3
    ) {
        self.id = id
        self.name = name
        self.momentumPeriod = momentumPeriod
        self.threshold = threshold
        self.confirmationPeriod = confirmationPeriod
        self.description = "Momentum > \(threshold) over \(momentumPeriod) periods with \(confirmationPeriod)-period confirmation"
        self.requiredIndicators = ["rsi", "macd", "momentum"]
        self.isActive = true
        self.createdAt = Date()
        self.performance = nil
    }
}

public func == (lhs: MomentumSetup, rhs: MomentumSetup) -> Bool {
    lhs.id == rhs.id
}

public struct TrendFollowingSetup: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let requiredIndicators: [String]
    public var isActive: Bool
    public var createdAt: Date
    public var performance: SetupPerformance?
    public let fastPeriod: Int
    public let slowPeriod: Int
    public let trailStop: Bool
    
    public init(
        id: String = UUID().uuidString,
        name: String = "Trend Following",
        fastPeriod: Int = 12,
        slowPeriod: Int = 26,
        trailStop: Bool = true
    ) {
        self.id = id
        self.name = name
        self.fastPeriod = fastPeriod
        self.slowPeriod = slowPeriod
        self.trailStop = trailStop
        self.description = "EMA \(fastPeriod)/\(slowPeriod) trend following with \(trailStop ? "trailing stop" : "fixed stop")"
        self.requiredIndicators = ["ema", "macd"]
        self.isActive = true
        self.createdAt = Date()
        self.performance = nil
    }
}

public func == (lhs: TrendFollowingSetup, rhs: TrendFollowingSetup) -> Bool {
    lhs.id == rhs.id
}

// MARK: - Setup Registry
public final class SetupRegistry: ObservableObject {
    @Published public var setups: [Identifiable & Equatable] = []
    
    public init() {
        // Default setups
        setups = [
            BreakoutSetup(),
            MeanReversionSetup(),
            MomentumSetup(),
            TrendFollowingSetup()
        ]
    }
    
    public func setup(_ type: SetupType) -> Identifiable? {
        setups.first { _ in true }
    }
    
    public func activate(_ setup: Identifiable) {
        // Find and activate - simplified
        for setupItem in setups {
            if setupItem.id as? String == setup.id as? String {
                if var active = setupItem as? BreakoutSetup {
                    active.isActive = true
                } else if var meanRev = setupItem as? MeanReversionSetup {
                    meanRev.isActive = true
                } else if var momentum = setupItem as? MomentumSetup {
                    momentum.isActive = true
                } else if var trend = setupItem as? TrendFollowingSetup {
                    trend.isActive = true
                }
            }
        }
    }
}
