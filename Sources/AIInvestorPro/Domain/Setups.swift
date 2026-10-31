// MARK: - Trade Setups
import Foundation

public struct Setup {
    public let symbol: String
    public let direction: SetupDirection
    public let entry: Double
    public let target: Double
    public let stop: Double
    public let score: Double
    public let riskReward: Double
    public let reasons: [String]
    public let detectedAt: Date
}

public enum SetupDirection {
    case long
    case short
}
