// MARK: - Market Data Pipeline
import Foundation
import Combine

public enum DataSource {
    case yahoo
    case stooq
    case local
}

public enum DataQuality {
    case clean
    case partial
    case stale
}

public struct MarketPipeline {
    private let cancellable: Cancellable?
    @Published public private(set) var state: DataQuality = .clean
    
    public init() {
        self.cancellable = nil
    }
    
    public func fetch(_ symbol: String, dataSource: DataSource = .yahoo) async throws -> MarketData {
        // Implementation for fetching market data
        return MarketData(symbol: symbol, price: 0, quality: .stale)
    }
    
    public func fetchHistory(_ symbols: [String], range: DataSource.ChartRange) async throws -> [MarketData] {
        // Implementation for fetching history
        return []
    }
}

public struct MarketData: Equatable {
    public let symbol: String
    public let price: Double
    public let change: Double
    public let quality: DataQuality
    public let timestamp: Date
}
