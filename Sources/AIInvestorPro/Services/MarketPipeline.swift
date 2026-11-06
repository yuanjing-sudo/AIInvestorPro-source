// MARK: - Market Pipeline
import Foundation
import Combine

public enum PipelineStatus: Sendable {
    case idle
    case processing
    case completed
    case error(String)

    var description: String {
        switch self {
        case .idle: return "Idle"
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .error(let message): return "Error: \(message)"
        }
    }
}

public struct MarketDataPoint: Identifiable, Sendable {
    public let id: String
    public let symbol: String
    public let timestamp: Date
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double
    public let volume: Double

    public var currentPrice: Double { close }
    public var symbolKey: String { symbol }

    public init(
        id: String = UUID().uuidString,
        symbol: String,
        timestamp: Date,
        open: Double,
        high: Double,
        low: Double,
        close: Double,
        volume: Double
    ) {
        self.id = id
        self.symbol = symbol
        self.timestamp = timestamp
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }
}

public struct MarketSnapshot: Sendable {
    public let symbol: String
    public var closes: [Double]
    public var opens: [Double]
    public var highs: [Double]
    public var lows: [Double]
    public var volumes: [Double]
    public var currentPrice: Double
    public var sector: String?
    public var timestamp: Date

    public var description: String {
        "\(symbol) at \(currentPrice.formattedCurrency) - \(closes.count) data points"
    }

    public init(
        symbol: String,
        closes: [Double],
        opens: [Double] = [],
        highs: [Double] = [],
        lows: [Double] = [],
        volumes: [Double] = [],
        currentPrice: Double? = nil,
        sector: String? = nil,
        timestamp: Date = Date()
    ) {
        self.symbol = symbol
        self.closes = closes
        let fallbackPrice = currentPrice ?? closes.last ?? 0
        self.opens = opens.isEmpty ? Array(repeating: fallbackPrice, count: closes.count) : opens
        self.highs = highs.isEmpty ? closes.map { $0 * 1.02 } : highs
        self.lows = lows.isEmpty ? closes.map { $0 * 0.98 } : lows
        self.volumes = volumes.isEmpty ? Array(repeating: 1_000_000, count: closes.count) : volumes
        self.currentPrice = fallbackPrice
        self.sector = sector
        self.timestamp = timestamp
    }
}

public enum PipelineStep: Sendable {
    case fetchData
    case calculateIndicators
    case generateSignals
    case analyzePortfolio
    case renderReport
}

@MainActor
public final class MarketPipeline: ObservableObject {
    @Published public var status: PipelineStatus = .idle
    @Published public var currentStep: PipelineStep = .fetchData
    @Published public var progress: Double = 0.0
    @Published public var snapshots: [MarketSnapshot] = []
    @Published public var error: String?

    private let fetcher: MarketFetcher
    private let analyzer: TechnicalAnalyzer
    private let pipelineSteps: [PipelineStep] = [
        .fetchData, .calculateIndicators, .generateSignals, .analyzePortfolio, .renderReport
    ]

    public init(
        fetcher: MarketFetcher = MarketFetcher(),
        analyzer: TechnicalAnalyzer = TechnicalAnalyzer()
    ) {
        self.fetcher = fetcher
        self.analyzer = analyzer
    }

    public func start(with symbols: [String]) {
        status = .processing
        snapshots = []
        progress = 0.0
        error = nil

        Task {
            await executePipeline(symbols: symbols)
        }
    }

    private func executePipeline(symbols: [String]) async {
        for (index, step) in pipelineSteps.enumerated() {
            currentStep = step
            progress = Double(index) / Double(pipelineSteps.count)

            switch step {
            case .fetchData:
                let succeeded = await fetchData(symbols: symbols)
                if !succeeded { return }
            case .calculateIndicators:
                calculateIndicators()
            case .generateSignals:
                generateSignals()
            case .analyzePortfolio:
                break
            case .renderReport:
                renderReport()
            }
        }

        status = .completed
        progress = 1.0
    }

    private func fetchData(symbols: [String]) async -> Bool {
        var fetchedSnapshots: [MarketSnapshot] = []

        for symbol in symbols {
            do {
                fetchedSnapshots.append(try await fetcher.fetch(symbol: symbol))
            } catch {
                let message = "Failed to fetch \(symbol): \(error.localizedDescription)"
                self.error = message
                self.status = .error(message)
                return false
            }
        }

        snapshots = fetchedSnapshots
        return true
    }

    private func calculateIndicators() {
        for snapshot in snapshots {
            _ = TechnicalIndicators.calculate(
                from: snapshot.closes,
                high: snapshot.highs,
                low: snapshot.lows,
                volume: snapshot.volumes
            )
        }
    }

    private func generateSignals() {
        for snapshot in snapshots {
            _ = MarketRegime.detect([snapshot])
            _ = Screener.scan(snapshot, horizon: 5)
        }
    }

    private func renderReport() {
        guard let snapshot = snapshots.first else { return }
        let result = analyzer.analyze(snapshot)
        _ = ReportRenderer.render(result)
    }
}

// MARK: - Market Fetcher
public final class MarketFetcher: @unchecked Sendable {
    private let urlSession: URLSession

    public init(urlSession: URLSession = URLSession.shared) {
        self.urlSession = urlSession
    }

    /// Fetch synthetic but deterministic market data for a symbol. The same
    /// symbol always produces the same series, which keeps demos, tests and
    /// screenshots reproducible. Replace this method with a real provider.
    public func fetch(symbol: String) async throws -> MarketSnapshot {
        guard !symbol.isEmpty else { throw YahooServiceError.invalidSymbol(symbol) }

        var generator = SeededGenerator(seed: stableSeed(for: symbol))
        let count = 100
        var closes: [Double] = []
        var price = 100.0 + Double(generator.next(in: 0...50))

        for _ in 0..<count {
            let drift = 0.0004
            let shock = generator.next(in: -0.02...0.02)
            price = max(1, price * (1 + drift + shock))
            closes.append(price)
        }

        let opens = closes.map { $0 * (1 + generator.next(in: -0.01...0.01)) }
        let highs = zip(closes, opens).map { max($0.0, $0.1) * (1 + generator.next(in: 0...0.02)) }
        let lows = zip(closes, opens).map { min($0.0, $0.1) * (1 - generator.next(in: 0...0.02)) }
        let volumes = (0..<count).map { _ in generator.next(in: 1_000_000...20_000_000) }

        return MarketSnapshot(
            symbol: symbol,
            closes: closes,
            opens: opens,
            highs: highs,
            lows: lows,
            volumes: volumes,
            currentPrice: closes.last ?? price,
            sector: "Technology"
        )
    }

    private func stableSeed(for symbol: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in symbol.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}

// MARK: - Technical Analyzer
public struct TechnicalAnalyzer: Sendable {
    public init() {}

    public func analyze(_ snapshot: MarketSnapshot) -> AnalysisResult {
        StockAnalyzer().analyze(snapshot)
    }

    public func signals(from snapshot: MarketSnapshot) -> [TradeSignal] {
        let scan = Screener.scan(snapshot, horizon: 5)
        return [scan.recommendation == .buy ? .enterLong : .hold]
    }
}

// MARK: - Deterministic RNG
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
