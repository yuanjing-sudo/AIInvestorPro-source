import Foundation

// MARK: - Candle

/// A single OHLCV bar.
public struct Candle: Codable, Hashable, Sendable, Identifiable {
    public var id: Date { date }

    public let date: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double
    public let adjustedClose: Double?

    public init(
        date: Date,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        volume: Double,
        adjustedClose: Double? = nil
    ) {
        self.date = date
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
        self.adjustedClose = adjustedClose
    }

    /// (high + low + close) / 3
    public var typicalPrice: Double { (high + low + close) / 3.0 }

    /// high - low
    public var range: Double { max(0, high - low) }

    public var isBullish: Bool { close >= open }

    /// The close used for return calculations (adjusted when available).
    public var effectiveClose: Double { adjustedClose ?? close }
}

// MARK: - Quote

/// A lightweight, point-in-time quote.
public struct Quote: Codable, Hashable, Sendable {
    public let symbol: String
    public let price: Double
    public let previousClose: Double?
    public let change: Double?
    public let changePercent: Double?
    public let volume: Double?
    public let currency: String?
    public let marketState: String?
    public let timestamp: Date

    public init(
        symbol: String,
        price: Double,
        previousClose: Double? = nil,
        change: Double? = nil,
        changePercent: Double? = nil,
        volume: Double? = nil,
        currency: String? = nil,
        marketState: String? = nil,
        timestamp: Date = Date()
    ) {
        self.symbol = symbol
        self.price = price
        self.previousClose = previousClose
        self.change = change ?? previousClose.map { price - $0 }
        self.changePercent = changePercent ?? previousClose.flatMap { previous in
            previous > 0 ? (price - previous) / previous * 100.0 : nil
        }
        self.volume = volume
        self.currency = currency
        self.marketState = marketState
        self.timestamp = timestamp
    }
}

// MARK: - PriceSeries

/// An ordered collection of candles for one symbol.
public struct PriceSeries: Sendable {
    public let symbol: String
    public let candles: [Candle]

    public init(symbol: String, candles: [Candle]) {
        self.symbol = symbol
        self.candles = candles
    }

    public var closes: [Double] { candles.map(\.close) }
    public var adjustedCloses: [Double] { candles.map(\.effectiveClose) }
    public var opens: [Double] { candles.map(\.open) }
    public var highs: [Double] { candles.map(\.high) }
    public var lows: [Double] { candles.map(\.low) }
    public var volumes: [Double] { candles.map(\.volume) }
    public var dates: [Date] { candles.map(\.date) }

    public var lastPrice: Double { candles.last?.close ?? 0 }
    public var isEmpty: Bool { candles.isEmpty }
    public var count: Int { candles.count }

    /// Simple returns between consecutive effective closes.
    public var simpleReturns: [Double] {
        let prices = adjustedCloses
        guard prices.count > 1 else { return [] }
        return zip(prices.dropFirst(), prices.dropLast()).map { current, previous in
            previous > 0 ? current / previous - 1.0 : 0.0
        }
    }
}

// MARK: - Trade Side

public enum TradeSide: String, Codable, Sendable, CaseIterable {
    case long = "long"
    case short = "short"
}

// MARK: - Number Formatting

public extension Double {
    /// Formats a fraction (0.1234) as a percentage string ("12.34%").
    func formattedPercent(decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f%%", self * 100.0)
    }

    /// Formats a value as currency using the current locale.
    func formattedCurrency(code: String = "USD", decimals: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: self)) ?? String(format: "$%.\(decimals)f", self)
    }
}
