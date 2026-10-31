// MARK: - Yahoo Finance Service
import Foundation

public enum ChartRange: String, CaseIterable {
    case oneDay = "1d"
    case fiveDays = "5d"
    case oneMonth = "1mo"
    case threeMonths = "3mo"
    case sixMonths = "6mo"
    case oneYear = "1y"
    case twoYears = "2y"
    case fiveYears = "5y"
    case max = "max"
}

public struct NewsItem: Identifiable {
    public let id = UUID()
    public let title: String
    public let publisher: String
    public let publishedAt: Date?
    public let link: URL
    public let category: String
}

public struct FinancialData {
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double
    public let adjustedClose: Double
    public let date: Date
}

public class YahooService {
    private let baseURL = URL(string: "https://query1.finance.yahoo.com/v8/finance")!
    private let session: URLSession
    
    public init(session: URLSession = .shared) {
        self.session = session
    }
    
    // Fetch chart data for a symbol
    public func fetchCandles(symbol: String, range: ChartRange) async throws -> [FinancialData] {
        // Implementation would parse Yahoo Finance API
        return []
    }
    
    // Fetch news for a symbol
    public func fetchNews(symbol: String) async throws -> [NewsItem] {
        // Implementation would parse Yahoo Finance news
        return []
    }
    
    // Get quote (current price data)
    public func fetchQuote(symbol: String) async throws -> FinancialData {
        // Implementation would parse Yahoo Finance quote
        return FinancialData(open: 0, high: 0, low: 0, close: 0, volume: 0, adjustedClose: 0, date: Date())
    }
}
