// MARK: - LLM Service
import Foundation
import Combine

public struct LLMConfig {
    public let baseURL: URL
    public let model: String
    public let apiKey: String?
    public let temperature: Double
    public var maxTokens: Int?
    public var timeout: TimeInterval
    
    public init(
        baseURL: URL,
        model: String,
        apiKey: String? = nil,
        temperature: Double = 0.2,
        maxTokens: Int? = nil,
        timeout: TimeInterval = 120.0
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.timeout = timeout
    }
}

// MARK: - LLM Response Types
public struct LLMVerdict: Equatable {
    public let model: String
    public let latency: TimeInterval
    public let text: String
    public let confidence: Double
    public let sector: String?
    public let priceTarget: Double?
    public let recommendation: String?
    public let tradeActions: [String]?
    public let riskAssessment: RiskAssessment?
    
    public static func == (lhs: LLMVerdict, rhs: LLMVerdict) -> Bool {
        lhs.model == rhs.model &&
        lhs.latency == rhs.latency &&
        lhs.confidence == rhs.confidence
    }
}

public struct RiskAssessment {
    public let riskLevel: RiskLevel
    public let positionSizeSuggestion: Double
    public let stopLossSuggestion: Double?
    public let takeProfitSuggestion: Double?
    public let rationale: String
    
    public enum RiskLevel: String, CaseIterable {
        case conservative
        case moderate
        case aggressive
    }
}

public enum LLMError: Error {
    case unreachable(config: LLMConfig)
    case invalidResponse(String)
    case timeout
    case rateLimited(Double) // seconds until retry
    case contentFilter(String)
    case tokenLimitExceeded
    case contextTooLong
}

// MARK: - Trade Idea
public enum Direction: String, CaseIterable {
    case buy
    case sell
    
    public var description: String {
        rawValue.capitalized
    }
}

public struct TradeIdea {
    public let symbol: String
    public let direction: Direction
    public let entryPrice: Double
    public let targetPrice: Double
    public let stopLoss: Double
    public let confidence: Double
    public let rationale: String
    public let expectedReturn: Double?
}

// MARK: - Probe Result
public struct ProbeResult: Equatable {
    public let reachable: Bool
    public let responseTime: TimeInterval
    public var modelName: String // Changed from 'model' to avoid conflict
    public var supportedFeatures: [String]?
    
    public init(reachable: Bool, responseTime: TimeInterval, modelName: String = "default", supportedFeatures: [String]? = nil) {
        self.reachable = reachable
        self.responseTime = responseTime
        self.modelName = modelName
        self.supportedFeatures = supportedFeatures
    }
}

// MARK: - LLM Client Protocol
public protocol LLMClient {
    func probe(config: LLMConfig) async throws -> ProbeResult
    func analyze(scan: SymbolScan, snapshot: MarketSnapshot, regime: MarketRegime, config: LLMConfig) async throws -> LLMVerdict
    func analyzePortfolio(portfolio: Portfolio, marketRegime: MarketRegime, config: LLMConfig) async throws -> LLMVerdict
    func generateTradeIdeas(marketData: [MarketSnapshot], regime: MarketRegime, config: LLMConfig) async throws -> [TradeIdea]
    func assessPortfolioRisk(portfolio: Portfolio, marketRegime: MarketRegime, config: LLMConfig) async throws -> RiskAssessment
}

// MARK: - Local LLM Client
public class LocalLLMClient: LLMClient {
    private let config: LLMConfig
    private var isAvailable = false
    private var lastProbe: Date?
    private var probeInterval: TimeInterval = 300.0 // 5 minutes
    
    public init(config: LLMConfig) {
        self.config = config
    }
    
    public func probe(config: LLMConfig) async throws -> ProbeResult {
        self.isAvailable = true // Simplified for demo
        self.lastProbe = Date()
        
        return ProbeResult(
            reachable: true,
            responseTime: 0.5,
            modelName: config.model,
            supportedFeatures: ["technical_analysis", "portfolio_risk", "trade_ideas"]
        )
    }
    
    public func analyze(scan: SymbolScan, snapshot: MarketSnapshot, regime: MarketRegime, config: LLMConfig) async throws -> LLMVerdict {
        return LLMVerdict(
            model: config.model,
            latency: 1.0,
            text: "Based on technical analysis, confidence: 0.85",
            confidence: 0.85,
            sector: snapshot.sector,
            priceTarget: nil,
            recommendation: "hold",
            tradeActions: nil,
            riskAssessment: RiskAssessment(
                riskLevel: .moderate,
                positionSizeSuggestion: 2.0,
                stopLossSuggestion: nil,
                takeProfitSuggestion: nil,
                rationale: "Technical analysis suggested"
            )
        )
    }
    
    public func analyzePortfolio(portfolio: Portfolio, marketRegime: MarketRegime, config: LLMConfig) async throws -> LLMVerdict {
        return LLMVerdict(
            model: config.model,
            latency: 1.0,
            text: "Portfolio analysis: \(portfolio.holdings.count) positions",
            confidence: 0.8,
            sector: nil,
            priceTarget: nil,
            recommendation: "hold",
            tradeActions: nil,
            riskAssessment: RiskAssessment(
                riskLevel: .moderate,
                positionSizeSuggestion: 5.0,
                stopLossSuggestion: nil,
                takeProfitSuggestion: nil,
                rationale: "Portfolio risk assessment"
            )
        )
    }
    
    public func generateTradeIdeas(marketData: [MarketSnapshot], regime: MarketRegime, config: LLMConfig) async throws -> [TradeIdea] {
        var ideas: [TradeIdea] = []
        
        for snapshot in marketData.prefix(5) {
            let idea = TradeIdea(
                symbol: snapshot.symbol,
                direction: .buy,
                entryPrice: snapshot.currentPrice,
                targetPrice: snapshot.currentPrice * 1.05,
                stopLoss: snapshot.currentPrice * 0.95,
                confidence: 0.7,
                rationale: "Technical analysis suggested",
                expectedReturn: 0.05
            )
            ideas.append(idea)
        }
        
        return ideas
    }
    
    public func assessPortfolioRisk(portfolio: Portfolio, marketRegime: MarketRegime, config: LLMConfig) async throws -> RiskAssessment {
        let riskLevel: RiskAssessment.RiskLevel = marketRegime == .bullish ? .moderate : .aggressive
        
        return RiskAssessment(
            riskLevel: riskLevel,
            positionSizeSuggestion: 3.0,
            stopLossSuggestion: nil,
            takeProfitSuggestion: nil,
            rationale: "Portfolio risk assessment"
        )
    }
}
