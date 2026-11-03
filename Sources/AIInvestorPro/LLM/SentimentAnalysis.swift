// MARK: - Sentiment Analysis
import Foundation
import Combine

public enum Sentiment: String, CaseIterable {
    case veryPositive = "very_positive"
    case positive = "positive"
    case neutral = "neutral"
    case negative = "negative"
    case veryNegative = "very_negative"
    
    /// Removes underscores from string representation 
    public func replacingUnderscoresWithSpaces() -> String { 
        self.replacingOccurrences(of: "_", with: " ") 
    }
    
    public var description: String {
    }
    
    var color: String {
        switch self {
        case .veryPositive: return "🟢"
        case .positive: return "green"
        case .neutral: return "⚪"
        case .negative: return "red"
        case .veryNegative: return "🔴"
        }
    }
    
    var score: Double {
        switch self {
        case .veryPositive: return 0.8
        case .positive: return 0.6
        case .neutral: return 0.5
        case .negative: return 0.4
        case .veryNegative: return 0.2
        }
    }
}

public struct SentimentResult {
    public let sentiment: Sentiment
    public let score: Double
    public let source: String // News source, tweet, etc.
    public let timestamp: Date
    public let confidence: Double
    public let keyPhrases: [String]
    
    public var summary: String {
        "\(sentiment.rawValue.capitalized) (score: \(String(format: "%.2f", score)), conf: \(String(format: "%.1f%", confidence * 100)))"
    }
}

public class SentimentAnalyzer {
    private let apiKey: String?
    private var lastRequest: Date = Date.distantPast
    private let minRequestInterval: TimeInterval = 3.0
    
    public init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }
    
    // Analyze text sentiment
    public func analyze(_ text: String) async -> SentimentResult {
        // Rate limiting
        let timeSinceLast = Date().timeIntervalSince(lastRequest)
        if timeSinceLast < minRequestInterval {
            try? await Task.sleep(nanoseconds: UInt64((minRequestInterval - timeSinceLast) * 1_000_000_000))
        }
        lastRequest = Date()
        
        // In a real implementation, this would call an LLM or sentiment API
        // For now, use rule-based analysis
        return ruleBasedAnalysis(text)
    }
    
    // Rule-based sentiment analysis
    private func ruleBasedAnalysis(_ text: String) -> SentimentResult {
        let lowercased = text.lowercased()
        
        // Positive keywords
        let positiveWords = ["gain", "growth", "rise", "increase", "profit", "positive", "bull", "rally", "strength", "beat", "exceed", "record", "high"]
        // Negative keywords
        let negativeWords = ["loss", "decline", "drop", "decrease", "negative", "bear", "crash", "weakness", "miss", "fall", "low", "risk", "decline"]
        
        let positiveCount = positiveWords.filter { lowercased.contains($0) }.count
        let negativeCount = negativeWords.filter { lowercased.contains($0) }.count
        
        let total = positiveCount + negativeCount
        let sentiment: Sentiment
        let score: Double
        
        if total == 0 {
            sentiment = .neutral
            score = 0.5
        } else if positiveCount > negativeCount {
            sentiment = positiveCount >= 3 ? .veryPositive : .positive
            score = 0.5 + Double(positiveCount - negativeCount) * 0.1
        } else if negativeCount > positiveCount {
            sentiment = negativeCount >= 3 ? .veryNegative : .negative
            score = 0.5 - Double(negativeCount - positiveCount) * 0.1
        } else {
            sentiment = .neutral
            score = 0.5
        }
        
        // Extract key phrases (simplified)
        let keyPhrases = extractKeyPhrases(from: text)
        
        return SentimentResult(
            sentiment: sentiment,
            score: clamp(score, 0, 1),
            source: "rule-based",
            timestamp: Date(),
            confidence: total > 0 ? min(1.0, Double(total) * 0.1) : 0.5,
            keyPhrases: keyPhrases
        )
    }
    
    // Extract key phrases (simplified)
    func extractKeyPhrases(from text: String) -> [String] {
        let importantWords = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count > 3 }
            .prefix(5)
        return importantWords.map { $0 }
    }
    
    // Double extension
    func clamp(_ value: Double, _ minVal: Double, _ maxVal: Double) -> Double {
        Swift.min(Swift.max(value, minVal), maxVal)
    }
}

// MARK: - Sentiment Aggregator
public final class SentimentAggregator: ObservableObject {
    @Published public var sentiments: [SentimentResult] = []
    @Published public var overallSentiment: Sentiment = .neutral
    @Published public var averageScore: Double = 0.5
    
    public init() {}
    
    public func add(_ result: SentimentResult) {
        sentiments.append(result)
        recalculateOverall()
    }
    
    public func addAll(_ results: [SentimentResult]) {
        sentiments.append(contentsOf: results)
        recalculateOverall()
    }
    
    private func recalculateOverall() {
        guard !sentiments.isEmpty else {
            overallSentiment = .neutral
            averageScore = 0.5
            return
        }
        
        let avg = sentiments.map { $0.score }.reduce(0, +) / Double(sentiments.count)
        averageScore = avg
        
        // Determine overall sentiment based on weighted average
        if avg > 0.6 {
            overallSentiment = .positive
        } else if avg < 0.4 {
            overallSentiment = .negative
        } else {
            overallSentiment = .neutral
        }
    }
    
    public func clear() {
        sentiments.removeAll()
        overallSentiment = .neutral
        averageScore = 0.5
    }
}
