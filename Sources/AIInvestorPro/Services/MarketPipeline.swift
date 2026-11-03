// MARK: - Market Pipeline
import Foundation

public enum PipelineStatus {
    case idle
    case processing
    case completed
    case error(String)
    
    var description: String {
        switch self {
        case .idle: return "Idle"
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

public struct MarketDataPoint: Identifiable {
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
    
    public init(id: String = UUID().uuidString, symbol: String, timestamp: Date, open: Double, high: Double, low: Double, close: Double, volume: Double) {
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

public struct MarketSnapshot {
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
    
    public init(symbol: String, closes: [Double], opens: [Double] = [], highs: [Double] = [], lows: [Double] = [], volumes: [Double] = [], currentPrice: Double? = nil, sector: String? = nil, timestamp: Date = Date()) {
        self.symbol = symbol
        self.closes = closes
        self.opens = opens.isEmpty ? Array(repeating: currentPrice ?? 0, count: closes.count) : opens
        self.highs = highs.isEmpty ? closes.map { $0 * 1.02 } : highs
        self.lows = lows.isEmpty ? closes.map { $0 * 0.98 } : lows
        self.volumes = volumes.isEmpty ? Array(repeating: 1000000, count: closes.count) : volumes
        self.currentPrice = currentPrice ?? closes.last ?? 0
        self.sector = sector
        self.timestamp = timestamp
    }
}

public enum PipelineStep {
    case fetchData
    case calculateIndicators
    case generateSignals
    case analyzePortfolio
    case renderReport
}

public class MarketPipeline: ObservableObject {
    @Published public var status: PipelineStatus = .idle
    @Published public var currentStep: PipelineStep = .fetchData
    @Published public var progress: Double = 0.0
    @Published public var snapshots: [MarketSnapshot] = []
    @Published public var error: String?
    
    private let fetcher: MarketFetcher
    private let analyzer: TechnicalAnalyzer
    private var pipelineSteps: [PipelineStep] = [.fetchData, .calculateIndicators, .generateSignals, .analyzePortfolio, .renderReport]
    private var currentStepIndex: Int = 0
    
    public init(fetcher: MarketFetcher = MarketFetcher(), analyzer: TechnicalAnalyzer = TechnicalAnalyzer()) {
        self.fetcher = fetcher
        self.analyzer = analyzer
    }
    
    /// Start the pipeline with given symbols
    /// - Parameter symbols: Stock symbols to process
    public func start(with symbols: [String]) {
        status = .processing
        snapshots = []
        currentStepIndex = 0
        progress = 0.0
        
        Task {
            await executePipeline(symbols: symbols)
        }
    }
    
    /// Execute pipeline steps
    private func executePipeline(symbols: [String]) async {
        for step in pipelineSteps {
            currentStep = step
            progress = Double(currentStepIndex) / Double(pipelineSteps.count)
            
            switch step {
            case .fetchData:
                await fetchData(symbols: symbols)
            case .calculateIndicators:
                await calculateIndicators()
            case .generateSignals:
                await generateSignals()
            case .analyzePortfolio:
                await analyzePortfolio()
            case .renderReport:
                await renderReport()
            }
            
            currentStepIndex += 1
        }
        
        status = .completed
        progress = 1.0
    }
    
    /// Fetch market data for symbols
    private func fetchData(symbols: [String]) async {
        var fetchedSnapshots: [MarketSnapshot] = []
        
        for symbol in symbols {
            do {
                let snapshot = try await fetcher.fetch(symbol: symbol)
                fetchedSnapshots.append(snapshot)
            } catch {
                error = "Failed to fetch \(symbol): \(error.localizedDescription)"
                status = .error(error!)
                return
            }
        }
        
        snapshots = fetchedSnapshots
        currentStepIndex += 1
    }
    
    /// Calculate technical indicators
    private func calculateIndicators() async {
        guard !snapshots.isEmpty else { return }
        
        for i in snapshots.indices {
            let indicators = TechnicalIndicators.calculate(from: snapshots[i].closes)
            // Store indicators in snapshot or process further
            _ = indicators
        }
        
        currentStepIndex += 1
    }
    
    /// Generate trading signals
    private func generateSignals() async {
        guard !snapshots.isEmpty else { return }
        
        for snapshot in snapshots {
            let regime = MarketRegime.detect([snapshot])
            let scans = Screener.scan([snapshot], horizonSetting: 5)
            
            // Process scans
            _ = regime
            _ = scans
        }
        
        currentStepIndex += 1
    }
    
    /// Analyze portfolio
    private func analyzePortfolio() async {
        // Portfolio analysis logic
        currentStepIndex += 1
    }
    
    /// Render analysis report
    private func renderReport() async {
        guard let snapshot = snapshots.first else { return }
        
        // Create sample analysis result
        let analyzer = StockAnalyzer()
        let result = analyzer.analyze(snapshot)
        
        // Render report
        let report = ReportRenderer.render(result)
        _ = report
        
        currentStepIndex += 1
    }
}

// MARK: - Market Fetcher
public class MarketFetcher {
    private let urlSession: URLSession
    
    public init(urlSession: URLSession = URLSession.shared) {
        self.urlSession = urlSession
    }
    
    /// Fetch market data for a symbol
    /// - Parameter symbol: Stock symbol
    /// - Returns: Market snapshot
    public func fetch(symbol: String) async throws -> MarketSnapshot {
        // In a real implementation, this would call an API
        // For now, generate synthetic data
        let count = 100
        let closes = (0..<count).map { index in
            let base: Double = 150.0
            let variation: Double = 5.0
            let noise = Double.random(in: -variation...variation)
            return base + noise + Double(index) * 0.1 // Slight upward trend
        }
        
        let currentPrice = closes.last!
        
        // Generate related data
        let opens = closes.map { $0 * Double.random(in: 0.98...1.02) }
        let highs = zip(closes, opens).map { max($0, $1) * Double.random(in: 1...1.05) }
        let lows = zip(closes, opens).map { min($0, $1) * Double.random(in: 0.95...1) }
        let volumes = Array(repeating: Double.random(in: 1000000...50000000), count: closes.count)
        
        return MarketSnapshot(
            symbol: symbol,
            closes: closes,
            opens: opens,
            highs: highs,
            lows: lows,
            volumes: volumes,
            currentPrice: currentPrice,
            sector: "Technology" // Simplified
        )
    }
}

// MARK: - Technical Analyzer
public class TechnicalAnalyzer {
    /// Analyze a market snapshot and return results
    /// - Parameter snapshot: Market data to analyze
    /// - Returns: Analysis result
    public func analyze(_ snapshot: MarketSnapshot) -> AnalysisResult {
        let analyzer = StockAnalyzer()
        return analyzer.analyze(snapshot)
    }
    
    /// Generate trading signals from snapshot
    /// - Parameter snapshot: Market data
    /// - Returns: Trading signals
    public func signals(from snapshot: MarketSnapshot) -> [TradeSignal] {
        let scans = Screener.scan([snapshot], horizonSetting: 5)
        return scans.map { $0.recommendation == .buy ? .enterLong : .enterShort }
    }
}
