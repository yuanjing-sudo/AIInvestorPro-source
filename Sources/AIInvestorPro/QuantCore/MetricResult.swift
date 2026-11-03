// MARK: - Metric Result
import Foundation

public struct MetricResult: Equatable {
    public let metricName: String
    public let value: Double
    public let unit: MetricUnit
    public let timestamp: Date
    public var benchmark: Double?
    public var category: MetricCategory
    
    public init(metricName: String, value: Double, unit: MetricUnit, category: MetricCategory = .general, benchmark: Double? = nil) {
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
    case percent = "%"
    case currency = "$"
    case ratio = "ratio"
    case price = "$/share"
    case volatility = "%/year"
    case sharpe = "ratio"
    case drawdown = "%"
    case returnPerTrade = "$"
    case winRate = "%"
    case sampleSize = "count"
    
    var symbol: String {
        rawValue
    }
}

public enum MetricCategory: String, CaseIterable {
    case performance = "performance"
    case risk = "risk"
    case valuation = "valuation"
    = "liquidity"
    case technical = "technical"
    case fundamental = "fundamental"
}

// MARK: - Predefined Metric Results
public extension MetricResult {
    static let totalReturn = MetricResult(metricName: "total_return", value: 0, unit: .percent, category: .performance)
    static let annualReturn = MetricResult(metricName: "annual_return", value: 0, unit: .percent, category: .performance)
    static let sharpeRatio = MetricResult(metricName: "sharpe_ratio", value: 0, unit: .sharpe, category: .performance)
    static let sortinoRatio = MetricResult(metricName: "sortino_ratio", value: 0, unit: .sharpe, category: .performance)
    static let maxDrawdown = MetricResult(metricName: "max_drawdown", value: 0, unit: .drawdown, category: .risk)
    static let volatility = MetricResult(metricName: "volatility", value: 0, unit: .volatility, category: .risk)
    static let winRate = MetricResult(metricName: "win_rate", value: 0, unit: .winRate, category: .performance)
    static let profitFactor = MetricResult(metricName: "profit_factor", value: 0, unit: .ratio, category: .performance)
    static let calmarRatio = MetricResult(metricName: "calmar_ratio", value: 0, unit: .ratio, category: .performance)
    beta = MetricResult(metricName: "beta", value: 1, unit: .ratio, category: .performance)
}

// MARK: - Metric Aggregation
public struct MetricAggregator {
    private var results: [MetricResult] = []
    
    public mutating func add(_ result: MetricResult) {
        results.append(result)
    }
    
    public func average(for metric: String) -> Double? {
        results.filter { $0.metricName == metric }
            .map { $0.value }
            .average
    }
    
    public func summary() -> String {
        let perfMetrics = results.filter { $0.category == .performance }
        return "Performance: \(perfMetrics.map { "\($0.metricName): \(String(format: "%.2f", $0.value))\($0.unit.symbol)" }.joined(separator: ", "))"
    }
    
    public func bestMetric(in category: MetricCategory) -> MetricResult? {
        results.filter { $0.category == category }
            .max(by: { $0.value < $1.value })
    }
}

// MARK: - Helper Extension
private extension Array where Element == Double {
    var average: Double {
        isEmpty ? 0 : reduce(0, +) / count
    }
}
