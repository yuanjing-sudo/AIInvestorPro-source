// MARK: - Metric Result
import Foundation

public struct MetricResult: Equatable {
    public let metricName: String
    public let value: Double
    public let unit: MetricUnit
    public let timestamp: Date
    public var benchmark: Double?
    public var category: MetricCategory
    
    public init(metricName: String, value: Double, unit: MetricUnit, category: MetricCategory = .performance, benchmark: Double? = nil) {
        self.metricName = metricName
        self.value = value
        self.unit = unit
        self.timestamp = Date()
        self.benchmark = benchmark
        self.category = category
    }
    
    public static func == (lhs: MetricResult, rhs: MetricResult) -> Bool {
        lhs.metricName == rhs.metricName && lhs.value == rhs.value
    }
}

public enum MetricUnit: String, CaseIterable {
    case percent = "percent_unit"
    case currency = "currency_unit"
    case ratio = "ratio_unit"
    case price = "price_unit"
    case volatility = "volatility_unit"
    case sharpe = "sharpe_unit"
    case drawdown = "drawdown_unit"
    case returnPerTrade = "return_unit"
    case winRate = "winrate_unit"
    case sampleSize = "sample_unit"
    
    var symbol: String {
        rawValue
    }
}

public enum MetricCategory: String, CaseIterable {
    case performance = "performance"
    case risk = "risk"
    case valuation = "valuation"
    case liquidity = "liquidity"
    case technical = "technical"
    case fundamental = "fundamental"
}
