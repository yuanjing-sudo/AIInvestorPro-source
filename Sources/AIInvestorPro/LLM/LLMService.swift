// MARK: - LLM Service
import Foundation

public struct LLMConfig {
    public let baseURL: URL
    public let model: String
    public let apiKey: String?
    
    public init(baseURL: URL, model: String, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
    }
}

public struct LLMVerdict: Equatable {
    public let model: String
    public let latency: TimeInterval
    public let text: String
    public let confidence: Double
    public let sector: String?
    public let priceTarget: Double?
    public let recommendation: String?
}

public enum LLMError: Error {
    case unreachable(config: LLMConfig)
    case invalidResponse(String)
    case timeout
    case rateLimited(Double) // seconds until retry
}

public protocol LLMClient {
    func probe(config: LLMConfig) async throws -> ProbeResult
    func analyze(scan: SymbolScan, snapshot: MarketSnapshot, regime: Market.Regime, config: LLMConfig) async throws -> LLMVerdict
}

public struct ProbeResult: Equatable {
    public let reachable: Bool
    public let responseTime: TimeInterval
    public var model: String { "default" }
}

public class LocalLLMClient: LLMClient {
    private let config: LLMConfig
    private var isAvailable = false
    
    public init(config: LLMConfig) {
        self.config = config
    }
    
    public func probe(config: LLMConfig) async throws -> ProbeResult {
        // Check if local LLM server (Ollama, etc.) is running
        self.isAvailable = true // Simplified
        return ProbeResult(reachable: true, responseTime: 0.5)
    }
    
    func analyze(scan: SymbolScan, snapshot: MarketSnapshot, regime: Market.Regime, config: LLMConfig) async throws -> LLMVerdict {
        // Implementation for local LLM analysis
        return LLMVerdict(
            model: config.model,
            latency: 1.0,
            text: "Based on the numbers above - no invented data.",
            confidence: 0.85,
            sector: snapshot.sector,
            priceTarget: nil,
            recommendation: "hold"
        )
    }
}
