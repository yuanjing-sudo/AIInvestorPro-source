import Foundation

// MARK: - Candidate

/// A symbol plus the cheap metrics needed by the screener. Strategies can
/// populate `metrics` with any values they like; the built-in keys are:
/// `rsi`, `momentum` (percent), `volatility` (annualized percent),
/// `priceToSMA` (ratio), `volumeRatio`, and `peRatio`.
public struct ScreenCandidate: Codable, Sendable, Identifiable, Equatable {
    public var id: String { symbol }
    public let symbol: String
    public let price: Double
    public let volume: Double
    public let marketCap: Double?
    public let sector: String?
    public let metrics: [String: Double]

    public init(
        symbol: String,
        price: Double,
        volume: Double = 0,
        marketCap: Double? = nil,
        sector: String? = nil,
        metrics: [String: Double] = [:]
    ) {
        self.symbol = symbol.uppercased()
        self.price = price
        self.volume = volume
        self.marketCap = marketCap
        self.sector = sector
        self.metrics = metrics
    }

    public func metric(_ key: String) -> Double? {
        guard let value = metrics[key], value.isFinite else { return nil }
        return value
    }
}

// MARK: - Filter

public struct ScreenFilter: Sendable, Equatable {
    public var minPrice: Double?
    public var maxPrice: Double?
    public var minVolume: Double?
    public var minMarketCap: Double?
    public var sectors: Set<String>?
    public var minRSI: Double?
    public var maxRSI: Double?
    public var minMomentum: Double?
    public var maxVolatility: Double?
    public var minPriceToSMA: Double?
    public var minVolumeRatio: Double?
    public var maxPE: Double?
    public var minScore: Double?
    public var maxResults: Int?

    public init(
        minPrice: Double? = nil,
        maxPrice: Double? = nil,
        minVolume: Double? = nil,
        minMarketCap: Double? = nil,
        sectors: Set<String>? = nil,
        minRSI: Double? = nil,
        maxRSI: Double? = nil,
        minMomentum: Double? = nil,
        maxVolatility: Double? = nil,
        minPriceToSMA: Double? = nil,
        minVolumeRatio: Double? = nil,
        maxPE: Double? = nil,
        minScore: Double? = nil,
        maxResults: Int? = nil
    ) {
        self.minPrice = minPrice
        self.maxPrice = maxPrice
        self.minVolume = minVolume
        self.minMarketCap = minMarketCap
        self.sectors = sectors
        self.minRSI = minRSI
        self.maxRSI = maxRSI
        self.minMomentum = minMomentum
        self.maxVolatility = maxVolatility
        self.minPriceToSMA = minPriceToSMA
        self.minVolumeRatio = minVolumeRatio
        self.maxPE = maxPE
        self.minScore = minScore
        self.maxResults = maxResults
    }

    public var isEmpty: Bool {
        minPrice == nil && maxPrice == nil && minVolume == nil && minMarketCap == nil
            && (sectors?.isEmpty ?? true) && minRSI == nil && maxRSI == nil
            && minMomentum == nil && maxVolatility == nil && minPriceToSMA == nil
            && minVolumeRatio == nil && maxPE == nil && minScore == nil
    }

    /// Human-readable list of failed rules for a candidate.
    public func failures(for candidate: ScreenCandidate) -> [String] {
        var failures: [String] = []

        if let minPrice, candidate.price < minPrice {
            failures.append("price below \(minPrice.formattedCurrency())")
        }
        if let maxPrice, candidate.price > maxPrice {
            failures.append("price above \(maxPrice.formattedCurrency())")
        }
        if let minVolume, candidate.volume < minVolume {
            failures.append("volume below \(Int(minVolume))")
        }
        if let minMarketCap {
            if let marketCap = candidate.marketCap {
                if marketCap < minMarketCap {
                    failures.append("market cap below \(Int(minMarketCap))")
                }
            } else {
                failures.append("market cap unavailable")
            }
        }
        if let sectors, !sectors.isEmpty {
            guard let sector = candidate.sector else {
                failures.append("sector unavailable")
                return failures
            }
            if !sectors.contains(sector) {
                failures.append("sector \(sector) not selected")
            }
        }
        if let minRSI {
            if let rsi = candidate.metric("rsi") {
                if rsi < minRSI { failures.append("RSI below \(minRSI)") }
            } else {
                failures.append("RSI unavailable")
            }
        }
        if let maxRSI {
            if let rsi = candidate.metric("rsi") {
                if rsi > maxRSI { failures.append("RSI above \(maxRSI)") }
            } else {
                failures.append("RSI unavailable")
            }
        }
        if let minMomentum {
            if let momentum = candidate.metric("momentum") {
                if momentum < minMomentum { failures.append("momentum below \(minMomentum)%") }
            } else {
                failures.append("momentum unavailable")
            }
        }
        if let maxVolatility {
            if let volatility = candidate.metric("volatility") {
                if volatility > maxVolatility { failures.append("volatility above \(maxVolatility)%") }
            } else {
                failures.append("volatility unavailable")
            }
        }
        if let minPriceToSMA {
            if let ratio = candidate.metric("priceToSMA") {
                if ratio < minPriceToSMA { failures.append("price-to-SMA below \(minPriceToSMA)") }
            } else {
                failures.append("price-to-SMA unavailable")
            }
        }
        if let minVolumeRatio {
            if let ratio = candidate.metric("volumeRatio") {
                if ratio < minVolumeRatio { failures.append("volume ratio below \(minVolumeRatio)") }
            } else {
                failures.append("volume ratio unavailable")
            }
        }
        if let maxPE {
            if let pe = candidate.metric("peRatio") {
                if pe > maxPE { failures.append("P/E above \(maxPE)") }
            } else {
                // Be consistent with the other metric filters: a required
                // metric that is missing cannot satisfy the constraint.
                failures.append("P/E unavailable")
            }
        }
        return failures
    }
}

// MARK: - Result

public struct ScreenResult: Sendable, Identifiable, Equatable {
    public var id: String { candidate.symbol }
    public let candidate: ScreenCandidate
    public let score: Double
    public let failures: [String]

    public var passed: Bool { failures.isEmpty }

    public init(candidate: ScreenCandidate, score: Double, failures: [String]) {
        self.candidate = candidate
        self.score = score
        self.failures = failures
    }
}

// MARK: - Engine

public enum ScreenerEngine {

    public static func evaluate(
        _ candidate: ScreenCandidate,
        filter: ScreenFilter
    ) -> ScreenResult {
        var failures = filter.failures(for: candidate)
        let score = score(candidate)
        if let minScore = filter.minScore, score < minScore {
            failures.append("score below \(String(format: "%.2f", minScore))")
        }
        return ScreenResult(candidate: candidate, score: score, failures: failures)
    }

    /// Returns passing candidates sorted by score (highest first).
    public static func run(
        candidates: [ScreenCandidate],
        filter: ScreenFilter
    ) -> [ScreenResult] {
        let results = candidates
            .map { evaluate($0, filter: filter) }
            .filter(\.passed)
            .sorted { $0.score > $1.score }
        if let maxResults = filter.maxResults, maxResults > 0 {
            return Array(results.prefix(maxResults))
        }
        return results
    }

    /// A transparent 0...1 composite score built from whatever metrics are
    /// available. Missing metrics are ignored rather than penalized.
    public static func score(_ candidate: ScreenCandidate) -> Double {
        var components: [Double] = []

        if let momentum = candidate.metric("momentum") {
            components.append(0.5 + clamp(momentum / 40.0, -0.5, 0.5))
        }
        if let ratio = candidate.metric("priceToSMA") {
            components.append(0.5 + clamp((ratio - 1.0) * 5.0, -0.5, 0.5))
        }
        if let volumeRatio = candidate.metric("volumeRatio") {
            components.append(clamp(volumeRatio / 2.0, 0, 1))
        }
        if let rsi = candidate.metric("rsi") {
            components.append(1.0 - clamp(abs(rsi - 50) / 50.0, 0, 1))
        }
        if let volatility = candidate.metric("volatility") {
            components.append(1.0 - clamp(volatility / 60.0, 0, 1))
        }
        if let pe = candidate.metric("peRatio"), pe > 0 {
            components.append(1.0 - clamp(pe / 40.0, 0, 1))
        }

        guard !components.isEmpty else { return 0 }
        return components.reduce(0, +) / Double(components.count)
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
