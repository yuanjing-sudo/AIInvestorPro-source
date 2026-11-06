// MARK: - Yahoo Finance Service
import Foundation

public enum YahooServiceError: Error {
    case invalidSymbol(String)
    case network(Error)
    case rateLimit(Double) // seconds
    case dataUnavailable(String)
    case parsing(Error)
    
    var localizedDescription: String {
        switch self {
        case .invalidSymbol(let sym):
            return "Invalid symbol: \(sym)"
        case .network(let err):
            return "Network error: \(err.localizedDescription)"
        case .rateLimit(let secs):
            return "Rate limited. Retry in \(Int(secs)) seconds"
        case .dataUnavailable(let sym):
            return "Data unavailable for: \(sym)"
        case .parsing(let err):
            return "Parsing error: \(err.localizedDescription)"
        }
    }
}

public struct YahooQuote: Equatable {
    public let symbol: String
    public let timestamp: Date
    public let price: Double       // Current price
    public let change: Double      // Change from previous close
    public let changePercent: Double // Percentage change
    public let bid: Double         // Best bid price
    public let ask: Double         // Best ask price
    public let volume: Double      // Volume
    public let marketCap: Double?  // Market capitalization
    public let dayRange: String    // "low-high"
    
    public static func == (lhs: YahooQuote, rhs: YahooQuote) -> Bool {
        lhs.symbol == rhs.symbol
    }
    
    var formattedChange: String {
        "\(String(format: "%.2f", change)) (\(String(format: "%.2f", changePercent))%)"
    }
    
    var formattedMarketCap: String {
        guard let cap = marketCap else { return "N/A" }
        if cap >= 1_000_000_000 {
            return "$\(String(format: "%.1fB", cap / 1_000_000_000))"
        } else if cap >= 1_000_000 {
            return "$\(String(format: "%.1fM", cap / 1_000_000))"
        }
        return "$\(String(format: "%.0f", cap))"
    }
}

public struct YahooHistoricalPoint: Equatable {
    public let date: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double
    public let adjClose: Double?
    
    public var currentPrice: Double { close }
    public var formattedDate: String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

public struct YahooHistoricalData: Equatable {
    public let symbol: String
    public let timestamp: Date
    public var points: [YahooHistoricalPoint]
    public let interval: String // "1d", "1wk", "1mo"
    
    public var firstPrice: Double { points.first?.close ?? 0 }
    public var lastPrice: Double { points.last?.close ?? 0 }
    public var change: Double { lastPrice - firstPrice }
    public var changePercent: Double {
        guard firstPrice > 0 else { return 0 }
        return (lastPrice - firstPrice) / firstPrice * 100
    }
    
    public var description: String {
        "\(symbol): \(points.count) points, \(firstPrice.formattedCurrency) → \(lastPrice.formattedCurrency) (\(String(format: "%.2f", changePercent))%)"
    }
}

public class YahooService {
    private let apiKey: String?
    private let urlSession: URLSession
    private var lastRequest: Date = Date.distantPast
    private let minRequestInterval: TimeInterval = 2.0 // Minimum 2 seconds between requests
    
    public init(apiKey: String? = nil, urlSession: URLSession = URLSession.shared) {
        self.apiKey = apiKey
        self.urlSession = urlSession
    }
    
    // MARK: - Quote Fetching
    /// Fetch current quote for a symbol
    /// - Parameter symbol: Stock symbol
    /// - Returns: Yahoo quote
    /// - Throws: YahooServiceError
    public func quote(symbol: String) async throws -> YahooQuote {
        // Validate symbol
        guard !symbol.isEmpty else { throw YahooServiceError.invalidSymbol("") }
        
        // Rate limiting
        let timeSinceLast = Date().timeIntervalSince(lastRequest)
        if timeSinceLast < minRequestInterval {
            try? await Task.sleep(nanoseconds: UInt64((minRequestInterval - timeSinceLast) * 1_000_000_000))
        }
        lastRequest = Date()
        
        // In a real implementation, this would call Yahoo Finance API
        // For now, return synthetic data
        var generator = SeededGenerator(seed: stableSeed(for: symbol))
        let price = generator.next(in: 100...200)
        let change = generator.next(in: -5...5)
        let changePercent = change / price * 100
        let bid = price - generator.next(in: 0...2)
        let ask = price + generator.next(in: 0...2)
        let volume = generator.next(in: 1_000_000...100_000_000)
        let marketCap = generator.next(in: 1_000_000_000...500_000_000_000)
        let dayRange = "\(String(format: "%.2f", price * 0.98))-\(String(format: "%.2f", price * 1.02))"
        
        return YahooQuote(
            symbol: symbol,
            timestamp: Date(),
            price: price,
            change: change,
            changePercent: changePercent,
            bid: bid,
            ask: ask,
            volume: volume,
            marketCap: marketCap,
            dayRange: dayRange
        )
    }
    
    // MARK: - Historical Data Fetching
    /// Fetch historical price data
    /// - Parameters:
    ///   - symbol: Stock symbol
    ///   - interval: Data interval ("1d", "1wk", "1mo")
    ///   - period: Lookback period ("1mo", "3mo", "6mo", "1y", "5y", "max")
    /// - Returns: Historical data
    /// - Throws: YahooServiceError
    public func historical(symbol: String, interval: String = "1d", period: String = "6mo") async throws -> YahooHistoricalData {
        // Rate limiting
        let timeSinceLast = Date().timeIntervalSince(lastRequest)
        if timeSinceLast < minRequestInterval {
            try? await Task.sleep(nanoseconds: UInt64((minRequestInterval - timeSinceLast) * 1_000_000_000))
        }
        lastRequest = Date()
        
        // Generate realistic synthetic historical data
        let pointCount: Int
        let startPrice: Double
        
        switch period {
        case "1mo": pointCount = 30; startPrice = 150
        case "3mo": pointCount = 60; startPrice = 150
        case "6mo": pointCount = 120; startPrice = 150
        case "1y": pointCount = 252; startPrice = 150
        case "5y": pointCount = 1260; startPrice = 100
        case "max": pointCount = 5040; startPrice = 50
        default: pointCount = 30; startPrice = 150
        }
        
        var generator = SeededGenerator(seed: stableSeed(for: symbol) &+ UInt64(pointCount))
        let returns = generateRealisticReturns(count: pointCount, startPrice: startPrice, generator: &generator)
        let timestamps = generateTimestamps(count: pointCount, interval: interval)
        
        let points = zip(timestamps, returns).map { pair in
            let close = pair.1
            return YahooHistoricalPoint(
                date: pair.0,
                open: close * generator.next(in: 0.99...1.01),
                high: close * generator.next(in: 1...1.03),
                low: close * generator.next(in: 0.97...1),
                close: close,
                volume: generator.next(in: 1_000_000...10_000_000),
                adjClose: close
            )
        }
        
        return YahooHistoricalData(
            symbol: symbol,
            timestamp: Date(),
            points: points,
            interval: interval
        )
    }
    
    // MARK: - Private Helpers
    private func stableSeed(for symbol: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in symbol.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }

    private func generateRealisticReturns(count: Int, startPrice: Double, generator: inout SeededGenerator) -> [Double] {
        guard count > 0 else { return [] }
        var prices: [Double] = [startPrice]
        let dailyVolatility: Double = 0.02

        for _ in 1..<count {
            let change = generator.next(in: -dailyVolatility...dailyVolatility)
            let newPrice = max(0.01, (prices.last ?? startPrice) * (1 + change))
            prices.append(newPrice)
        }

        return prices
    }
    
    private func generateTimestamps(count: Int, interval: String) -> [Date] {
        guard count > 0 else { return [] }
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: Date())
        let component: Calendar.Component
        switch interval {
        case "1wk": component = .weekOfYear
        case "1mo": component = .month
        default: component = .day
        }

        return (0..<count).compactMap { index in
            calendar.date(byAdding: component, value: -(count - 1 - index), to: endDate)
        }
    }
}

// MARK: - Yahoo Service Extensions
extension Date {
    var yesterday: Date {
        calendar.date(byAdding: .day, value: -1, to: self) ?? self
    }
    
    var today: Date {
        calendar.startOfDay(for: self)
    }
    
    var startOfDay: Date {
        calendar.startOfDay(for: self)
    }
    
    var endOfDay: Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: self))?.addingTimeInterval(-1) ?? self
    }
}

private var calendar: Calendar { .current }
