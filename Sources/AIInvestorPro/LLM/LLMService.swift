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
    public let risk assessment: RiskAssessment?
    
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

// MARK: - LLM Client Protocol
public protocol LLMClient {
    func probe(config: LLMConfig) async throws -> ProbeResult
    func analyze(scan: SymbolScan, snapshot: MarketSnapshot, regime: Market.Regime, config: LLMConfig) async throws -> LLMVerdict
    func analyzePortfolio(portfolio: Portfolio, marketRegime: Market.Regime, config: LLMConfig) async throws -> LLMVerdict
    func generateTradeIdeas(marketData: [MarketSnapshot], regime: Market.Regime, config: LLMConfig) async throws -> [TradeIdea]
    func assessPortfolioRisk(portfolio: Portfolio, marketRegime: Market.Regime, config: LLMConfig) async throws -> RiskAssessment
}

public struct ProbeResult: Equatable {
    public let reachable: Bool
    public let responseTime: TimeInterval
    public var model: String { "default" }
    public var supportedFeatures: [String]?
}

public struct TradeIdea {
    public let symbol: String
    public let direction: OrderSide
    public let entryPrice: Double
    public let targetPrice: Double
    public let stopLoss: Double
    public let confidence: Double
    public let rationale: String
    public let expectedReturn: Double?
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
        // Check if local LLM server (Ollama, etc.) is running
        // In a real implementation, this would ping the server
        self.isAvailable = true // Simplified for demo
        self.lastProbe = Date()
        
        return ProbeResult(
            reachable: true,
            responseTime: 0.5,
            model: config.model,
            supportedFeatures: ["technical_analysis", "portfolio_risk", "trade_ideas"]
        )
    }
    
    public func analyze(scan: SymbolScan, snapshot: MarketSnapshot, regime: Market.Regime, config: LLMConfig) async throws -> LLMVerdict {
        // Implementation for local LLM analysis
        // This would call Ollama or similar local model
        return LLMVerdict(
            model: config.model,
            latency: 1.0,
            text: "Based on the technical analysis: RSI \(String(format: "%.1f", scan.forecast.predictedReturn > 0 ? "bullish" : "bearish")), confidence: 0.85",
            confidence: 0.85,
            sector: snapshot.sector,
            priceTarget: nil,
            recommendation: scan.recommendation.rawValue,
            riskAssessment: RiskAssessment(
                riskLevel: .moderate,
                positionSizeSuggestion: 2.0,
                stopLossSuggestion: nil,
                takeProfitSuggestion: nil,
                rationale: "Technical indicators suggest moderate risk/reward ratio"
            )
        )
    }
    
    func analyzePortfolio(portfolio: Portfolio, marketRegime: Market.Regime, config: LLMConfig) async throws -> LLMVerdict {
        // Portfolio analysis implementation
        return LLMVerdict(
            model: config.model,
            latency: 1.0,
            text: "Portfolio analysis: \(portfolio.totalValue.formattedCurrency) with \(portfolio.holdings.count) positions",
            confidence: 0.8,
            sector: nil,
            priceTarget: nil,
            recommendation: "hold",
            riskAssessment: RiskAssessment(
                riskLevel: .moderate,
                positionSizeSuggestion: 5.0,
                stopLossSuggestion: nil,
                takeProfitSuggestion: nil,
                rationale: "Diversified portfolio with moderate risk"
            )
        )
    }
    
    func generateTradeIdeas(marketData: [MarketSnapshot], regime: Market.Regime, config: LLMConfig) async throws -> [TradeIdea] {
        // Generate trade ideas from market data
        var ideas: [TradeIdea] = []
        
        for snapshot in marketData.prefix(5) {
            let idea = TradeIdea(
                symbol: snapshot.symbol,
                direction: .buy,
                entryPrice: snapshot.currentPrice,
                targetPrice: snapshot.currentPrice * 1.05, // 5% target
                stopLoss: snapshot.currentPrice * 0.95, // 5% stop
                confidence: 0.7,
                rationale: "Technical analysis suggests bullish momentum in \(regime.rawValue) regime",
                expectedReturn: 0.05
            )
            ideas.append(idea)
        }
        
        return ideas
    }
    
    func assessPortfolioRisk(portfolio: Portfolio, marketRegime: Market.Regime, config: LLMConfig) async throws -> RiskAssessment {
        // Risk assessment implementation
        let riskLevel: RiskLevel = marketRegime == .bullish ? .moderate : .aggressive
        
        return RiskAssessment(
            riskLevel: riskLevel,
            positionSizeSuggestion: 3.0,
            stopLossSuggestion: nil,
            takeProfitSuggestion: nil,
            rationale: "Portfolio analysis based on \(portfolio.holdings.count) holdings and \(marketRegime.rawValue) market regime"
        }
    }
}

// MARK: - Trade Idea
public struct TradeIdea {
    public let symbol: String
    public let direction: OrderSide
    public let entryPrice: Double
    public let targetPrice: Double
    public let stopLoss: Double
    public let confidence: Double
    public let rationale: String
    public let expectedReturn: Double?
}

// MARK: - Market Snapshot for LLM
extension MarketSnapshot {
    var llmSummary: String {
        "\(symbol) at \(String(format: "$%.2f", currentPrice)) - \(regime.rawValue) regime, \(closes.count) days data, \(technical.rsi > 50 ? "bullish" : "bearish") RSI"
    }
}
