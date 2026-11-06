import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Provider Protocol

/// Abstraction over any market-data source (Yahoo, a broker, a local cache, or
/// a deterministic mock used in tests).
public protocol MarketDataProvider: Sendable {
    func quote(symbol: String) async throws -> Quote
    func candles(symbol: String, range: CandleRange, interval: CandleInterval) async throws -> [Candle]
}

// MARK: - Enums

public enum CandleRange: String, Codable, Sendable, CaseIterable {
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

public enum CandleInterval: String, Codable, Sendable, CaseIterable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case oneDay = "1d"
    case oneWeek = "1wk"
    case oneMonth = "1mo"
}

// MARK: - Errors

public enum MarketDataError: Error, LocalizedError, Sendable, Equatable {
    case invalidSymbol(String)
    case httpStatus(Int)
    case rateLimited(retryAfter: TimeInterval)
    case decoding(String)
    case noData(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSymbol(let symbol):
            return "Invalid symbol: \(symbol)"
        case .httpStatus(let status):
            return "Market data request failed with HTTP \(status)"
        case .rateLimited(let seconds):
            return "Rate limited; retry in \(Int(seconds.rounded(.up)))s"
        case .decoding(let message):
            return "Could not decode market data: \(message)"
        case .noData(let symbol):
            return "No market data available for \(symbol)"
        case .network(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Yahoo Finance Provider

/// A production-shaped Yahoo Finance chart client.
///
/// Notes:
/// - Uses the public `query1.finance.yahoo.com/v8/finance/chart` endpoint.
/// - Requests are serialized by the actor and throttled.
/// - Transient failures (429/5xx/network) are retried with exponential backoff.
/// - Responses are cached briefly to avoid hammering the endpoint.
/// - Yahoo's endpoint is unofficial; callers should be prepared for upstream
///   changes and should not treat this as a licensed real-time feed.
public actor YahooFinanceProvider: MarketDataProvider {

    private struct CacheEntry: Sendable {
        let createdAt: Date
        let candles: [Candle]
        let meta: ChartMeta
    }

    private struct ChartMeta: Sendable {
        let symbol: String
        let currency: String?
        let regularMarketPrice: Double?
        let previousClose: Double?
        let volume: Double?
        let marketState: String?
    }

    private let session: URLSession
    private let minRequestInterval: TimeInterval
    private let cacheTTL: TimeInterval
    private let maxRetries: Int
    private var lastRequestAt: Date?
    private var cache: [String: CacheEntry] = [:]

    public init(
        session: URLSession = .shared,
        minRequestInterval: TimeInterval = 0.35,
        cacheTTL: TimeInterval = 45,
        maxRetries: Int = 3
    ) {
        self.session = session
        self.minRequestInterval = max(0, minRequestInterval)
        self.cacheTTL = max(0, cacheTTL)
        self.maxRetries = max(1, maxRetries)
    }

    // MARK: Public API

    public func quote(symbol: String) async throws -> Quote {
        let clean = try validated(symbol)
        let (meta, candles) = try await chart(symbol: clean, range: .fiveDays, interval: .oneDay)
        guard let last = candles.last else {
            throw MarketDataError.noData(clean)
        }
        let previous = candles.count >= 2
            ? candles[candles.count - 2].effectiveClose
            : meta.previousClose
        let price = meta.regularMarketPrice ?? last.close
        return Quote(
            symbol: clean,
            price: price,
            previousClose: previous,
            volume: meta.volume ?? last.volume,
            currency: meta.currency,
            marketState: meta.marketState,
            timestamp: last.date
        )
    }

    public func candles(
        symbol: String,
        range: CandleRange,
        interval: CandleInterval
    ) async throws -> [Candle] {
        let clean = try validated(symbol)
        let (_, candles) = try await chart(symbol: clean, range: range, interval: interval)
        return candles
    }

    // MARK: Implementation

    private func validated(_ symbol: String) throws -> String {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty, trimmed.count <= 24 else {
            throw MarketDataError.invalidSymbol(symbol)
        }
        return trimmed
    }

    private func chart(
        symbol: String,
        range: CandleRange,
        interval: CandleInterval
    ) async throws -> (ChartMeta, [Candle]) {
        let key = "\(symbol)|\(range.rawValue)|\(interval.rawValue)"
        if let entry = cache[key], Date().timeIntervalSince(entry.createdAt) < cacheTTL {
            return (entry.meta, entry.candles)
        }

        let url = try chartURL(symbol: symbol, range: range, interval: interval)
        let data = try await requestData(url)

        let response: ChartResponse
        do {
            response = try JSONDecoder().decode(ChartResponse.self, from: data)
        } catch {
            throw MarketDataError.decoding(error.localizedDescription)
        }

        if let apiError = response.chart.error {
            throw MarketDataError.noData(apiError.description ?? symbol)
        }
        guard let result = response.chart.result?.first else {
            throw MarketDataError.noData(symbol)
        }

        let candles = try decodeCandles(result, symbol: symbol)
        guard !candles.isEmpty else { throw MarketDataError.noData(symbol) }

        let meta = ChartMeta(
            symbol: result.meta.symbol ?? symbol,
            currency: result.meta.currency,
            regularMarketPrice: result.meta.regularMarketPrice,
            previousClose: result.meta.chartPreviousClose,
            volume: result.meta.regularMarketVolume,
            marketState: result.meta.marketState
        )
        cache[key] = CacheEntry(createdAt: Date(), candles: candles, meta: meta)
        return (meta, candles)
    }

    private func decodeCandles(
        _ result: ChartResponse.Result,
        symbol: String
    ) throws -> [Candle] {
        guard let timestamps = result.timestamp,
              let quoteBlocks = result.indicators.quote,
              let block = quoteBlocks.first
        else {
            throw MarketDataError.decoding("missing timestamps or quote block")
        }
        let adjClose = result.indicators.adjclose?.first?.adjclose

        var candles: [Candle] = []
        candles.reserveCapacity(timestamps.count)
        for index in timestamps.indices {
            guard index < block.close.count,
                  let close = block.close[index],
                  close.isFinite, close > 0
            else { continue }

            let date = Date(timeIntervalSince1970: TimeInterval(timestamps[index]))
            let open = safe(block.open, index) ?? close
            let high = safe(block.high, index) ?? max(open, close)
            let low = safe(block.low, index) ?? min(open, close)
            let volume = safe(block.volume, index) ?? 0
            let adjusted = adjClose.flatMap { safe($0, index) }

            candles.append(Candle(
                date: date,
                open: open,
                high: max(max(high, open), close),
                low: min(min(low, open), close),
                close: close,
                volume: max(0, volume),
                adjustedClose: adjusted
            ))
        }
        guard !candles.isEmpty else {
            throw MarketDataError.noData(symbol)
        }
        return candles.sorted { $0.date < $1.date }
    }

    private func safe(_ values: [Double?], _ index: Int) -> Double? {
        guard index >= 0, index < values.count else { return nil }
        guard let value = values[index], value.isFinite else { return nil }
        return value
    }

    private func chartURL(
        symbol: String,
        range: CandleRange,
        interval: CandleInterval
    ) throws -> URL {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: allowed) ?? symbol
        guard var components = URLComponents(
            string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)"
        ) else {
            throw MarketDataError.invalidSymbol(symbol)
        }
        components.queryItems = [
            URLQueryItem(name: "range", value: range.rawValue),
            URLQueryItem(name: "interval", value: interval.rawValue),
            URLQueryItem(name: "includePrePost", value: "false"),
            URLQueryItem(name: "events", value: "div,splits"),
        ]
        guard let url = components.url else {
            throw MarketDataError.invalidSymbol(symbol)
        }
        return url
    }

    private func requestData(_ url: URL) async throws -> Data {
        var lastError: MarketDataError = .network("unknown")

        for attempt in 0..<maxRetries {
            do {
                try await throttle()
                let (data, response) = try await fetch(url)
                guard let http = response as? HTTPURLResponse else {
                    throw MarketDataError.network("non-HTTP response")
                }

                if http.statusCode == 200 {
                    return data
                }

                let retryable = http.statusCode == 429 || (500...599).contains(http.statusCode)
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init)
                    ?? pow(2.0, Double(attempt)) * 0.5
                lastError = retryable
                    ? .rateLimited(retryAfter: retryAfter)
                    : .httpStatus(http.statusCode)

                guard retryable, attempt < maxRetries - 1 else { throw lastError }
                try await Task.sleep(nanoseconds: Self.nanos(min(retryAfter, 5)))
            } catch let error as MarketDataError {
                if attempt < maxRetries - 1, case .network = error {
                    lastError = error
                } else {
                    throw error
                }
            } catch {
                lastError = .network(error.localizedDescription)
                guard attempt < maxRetries - 1 else { throw lastError }
            }
        }
        throw lastError
    }

    /// `URLSession.data(from:)` is unavailable on Linux. Bridge the
    /// completion-handler API so the same provider compiles on every platform.
    private func fetch(_ url: URL) async throws -> (Data, URLResponse) {
        #if canImport(FoundationNetworking)
        return try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: url) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: MarketDataError.network("empty response"))
                }
            }.resume()
        }
        #else
        return try await session.data(from: url)
        #endif
    }

    private func throttle() async throws {
        if let last = lastRequestAt {
            let elapsed = Date().timeIntervalSince(last)
            let remaining = minRequestInterval - elapsed
            if remaining > 0 {
                try await Task.sleep(nanoseconds: Self.nanos(remaining))
            }
        }
        lastRequestAt = Date()
    }

    private static func nanos(_ seconds: TimeInterval) -> UInt64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return UInt64(min(seconds, 60) * 1_000_000_000)
    }
}

// MARK: - Yahoo JSON

private struct ChartResponse: Decodable {
    let chart: Chart

    struct Chart: Decodable {
        let result: [Result]?
        let error: APIError?
    }

    struct APIError: Decodable {
        let code: String?
        let description: String?
    }

    struct Result: Decodable {
        let meta: Meta
        let timestamp: [Int]?
        let indicators: Indicators
    }

    struct Meta: Decodable {
        let symbol: String?
        let currency: String?
        let regularMarketPrice: Double?
        let chartPreviousClose: Double?
        let regularMarketVolume: Double?
        let marketState: String?
    }

    struct Indicators: Decodable {
        let quote: [QuoteBlock]?
        let adjclose: [AdjCloseBlock]?
    }

    struct QuoteBlock: Decodable {
        let open: [Double?]
        let high: [Double?]
        let low: [Double?]
        let close: [Double?]
        let volume: [Double?]

        private enum CodingKeys: String, CodingKey {
            case open, high, low, close, volume
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            open = (try? container.decodeIfPresent([Double?].self, forKey: .open)) ?? []
            high = (try? container.decodeIfPresent([Double?].self, forKey: .high)) ?? []
            low = (try? container.decodeIfPresent([Double?].self, forKey: .low)) ?? []
            close = (try? container.decodeIfPresent([Double?].self, forKey: .close)) ?? []
            volume = (try? container.decodeIfPresent([Double?].self, forKey: .volume)) ?? []
        }
    }

    struct AdjCloseBlock: Decodable {
        let adjclose: [Double?]

        private enum CodingKeys: String, CodingKey {
            case adjclose
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            adjclose = (try? container.decodeIfPresent([Double?].self, forKey: .adjclose)) ?? []
        }
    }
}

// MARK: - Mock Provider

/// Deterministic synthetic provider. Prices for a given symbol/interval are
/// reproducible across runs (timestamps are anchored to the current clock),
/// which makes it useful for tests and demos.
public struct MockMarketDataProvider: MarketDataProvider, Sendable {
    public let seed: UInt64
    public let startingPrice: Double

    public init(seed: UInt64 = 42, startingPrice: Double = 150) {
        self.seed = seed
        self.startingPrice = max(1, startingPrice)
    }

    public func quote(symbol: String) async throws -> Quote {
        let clean = symbol.uppercased()
        guard !clean.isEmpty else { throw MarketDataError.invalidSymbol(symbol) }
        let series = makeCandles(symbol: clean, range: .fiveDays, interval: .oneDay)
        guard let last = series.last else { throw MarketDataError.noData(clean) }
        let previous = series.count >= 2 ? series[series.count - 2].close : last.close
        return Quote(
            symbol: clean,
            price: last.close,
            previousClose: previous,
            volume: last.volume,
            currency: "USD",
            marketState: "REGULAR",
            timestamp: last.date
        )
    }

    public func candles(
        symbol: String,
        range: CandleRange,
        interval: CandleInterval
    ) async throws -> [Candle] {
        let clean = symbol.uppercased()
        guard !clean.isEmpty else { throw MarketDataError.invalidSymbol(symbol) }
        return makeCandles(symbol: clean, range: range, interval: interval)
    }

    private func makeCandles(
        symbol: String,
        range: CandleRange,
        interval: CandleInterval
    ) -> [Candle] {
        let count = max(2, bars(range: range, interval: interval))
        let step = seconds(interval: interval)
        let base = seed ^ fnv1a(symbol) ^ fnv1a(interval.rawValue)
        var generator = SeededGenerator(seed: base)

        var price = startingPrice * (0.7 + generator.nextDouble() * 0.8)
        let drift = 0.00035
        let volatility = 0.018
        let now = Date()

        var candles: [Candle] = []
        candles.reserveCapacity(count)
        for index in 0..<count {
            let shock = generator.nextGaussian() * volatility
            let change = drift + shock
            let open = price
            let close = max(0.05, open * (1 + change))
            let wick = abs(generator.nextGaussian()) * volatility * 0.5
            let high = max(open, close) * (1 + wick)
            let low = min(open, close) * max(0.01, 1 - wick)
            let volume = 500_000 + generator.nextDouble() * 9_500_000
            let date = now.addingTimeInterval(-Double(count - 1 - index) * step)
            candles.append(Candle(
                date: date,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume,
                adjustedClose: close
            ))
            price = close
        }
        return candles
    }

    private func bars(range: CandleRange, interval: CandleInterval) -> Int {
        let days: Double
        switch range {
        case .oneDay: days = 1
        case .fiveDays: days = 5
        case .oneMonth: days = 22
        case .threeMonths: days = 66
        case .sixMonths: days = 132
        case .oneYear: days = 252
        case .twoYears: days = 504
        case .fiveYears: days = 1260
        case .max: days = 2520
        }
        let perDay: Double
        switch interval {
        case .oneMinute: perDay = 390
        case .fiveMinutes: perDay = 78
        case .fifteenMinutes: perDay = 26
        case .thirtyMinutes: perDay = 13
        case .oneHour: perDay = 7
        case .oneDay: perDay = 1
        case .oneWeek: perDay = 1.0 / 5.0
        case .oneMonth: perDay = 1.0 / 21.0
        }
        return max(2, min(6000, Int(days * perDay)))
    }

    private func seconds(interval: CandleInterval) -> TimeInterval {
        switch interval {
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1_800
        case .oneHour: return 3_600
        case .oneDay: return 86_400
        case .oneWeek: return 604_800
        case .oneMonth: return 2_592_000
        }
    }

    private func fnv1a(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}
