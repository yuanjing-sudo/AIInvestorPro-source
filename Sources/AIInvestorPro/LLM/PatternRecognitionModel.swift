// MARK: - Technical Pattern Recognition
import Foundation

public enum PatternType: String, CaseIterable {
    case headAndShoulders = "head_and_shoulders"
    case doubleTop = "double_top"
    case doubleBottom = "double_bottom"
    case cupAndHandle = "cup_and_handle"
    case flag = "flag"
    case wedge = "wedge"
    case triangle = "triangle"
    case supportBreakout = "support_breakout"
    case resistanceBreakout = "resistance_breakout"
    
    public var description: String {
        rawValue.replacingUnderscoresWithSpaces()
    }
}

public struct PatternMatch: Equatable {
    public let patternType: PatternType
    public let confidence: Double // 0.0 - 1.0
    public let breakoutPrice: Double?
    public let targetPrice: Double?
    public let stopLoss: Double?
    public let completionDate: Date?
    public let description: String
    
    public static func == (lhs: PatternMatch, rhs: PatternMatch) -> Bool {
        lhs.patternType == rhs.patternType && lhs.confidence == rhs.confidence
    }
}

public struct PricePattern {
    public let highs: [Double]
    public let lows: [Double]
    public let closes: [Double]
    public let dates: [Date]
    public let volumes: [Double]
    
    init(closes: [Double], highs: [Double]? = nil, lows: [Double]? = nil, dates: [Date]? = nil, volumes: [Double]? = nil) {
        self.closes = closes
        self.highs = highs ?? closes.map { $0 * 1.02 }
        self.lows = lows ?? closes.map { $0 * 0.98 }
        self.dates = dates ?? (0..<closes.count).map { Date().addingTimeInterval(-86400 * Double($0)) }
        self.volumes = volumes ?? Array(repeating: 1_000_000, count: closes.count)
    }
}

// MARK: - Pattern Detection Engine
public final class PatternRecognizer {
    private let pricePattern: PricePattern
    
    public init(pricePattern: PricePattern) {
        self.pricePattern = pricePattern
    }
    
    // Detect head and shoulders pattern
    public func detectHeadAndShoulders() -> PatternMatch? {
        guard pricePattern.closes.count >= 20 else { return nil }
        
        let midPoint = pricePattern.closes.count / 2
        let leftMin = pricePattern.closes[0..<midPoint].min() ?? pricePattern.closes[0]
        let rightMin = pricePattern.closes[midPoint...].min() ?? pricePattern.closes.last
        let head = pricePattern.closes[midPoint]
        
        // Check if head is significantly higher than shoulders
        let shoulderThreshold = 0.03 // 3% threshold
        
        guard head > leftMin * (1 + shoulderThreshold) &&
              head > rightMin * (1 + shoulderThreshold) else {
            return nil
        }
        
        // Find shoulder dates
        let leftShoulderIdx = pricePattern.closes[0..<midPoint].firstIndex { $0 == leftMin } ?? 0
        let rightShoulderIdx = pricePattern.closes[midPoint...].firstIndex { $0 == rightMin } ?? pricePattern.closes.count - 1 midPoint
        
        let breakoutPrice = pricePattern.closes[rightShoulderIdx + 1...]?.first // Would need to check breakout
        
        // Simplified target: head height projected from neckline
        let neckline = (leftMin + rightMin) / 2
        let headHeight = head - neckline
        let targetPrice = neckline + headHeight
        
        // Stop loss below left shoulder
        let stopLoss = leftMin * 0.98
        
        return PatternMatch(
            patternType: .headAndShoulders,
            confidence: 0.8,
            breakoutPrice: breakoutPrice,
            targetPrice: targetPrice,
            stopLoss: stopLoss,
            completionDate: Date(),
            description: "Head and shoulders pattern detected with \(String(format: "%.1f", confidence * 100))% confidence"
        )
    }
    
    // Detect double bottom pattern
    public func detectDoubleBottom() -> PatternMatch? {
        guard pricePattern.closes.count >= 20 else { return nil }
        
        // Find two local minima at similar price levels
        let midPoint = pricePattern.closes.count / 2
        
        // Look for first bottom
        var firstBottomIdx = -1
        var firstBottomPrice = Double.infinity
        for i in 0..<midPoint where pricePattern.closes[i] < firstBottomPrice {
            firstBottomPrice = pricePattern.closes[i]
            firstBottomIdx = i
        }
        
        // Look for second bottom
        var secondBottomIdx = -1
        var secondBottomPrice = Double.infinity
        for i in midPoint..<pricePattern.closes.count where pricePattern.closes[i] < secondBottomPrice {
            secondBottomPrice = pricePattern.closes[i]
            secondBottomIdx = i
        }
        
        guard firstBottomIdx >= 0, secondBottomIdx >= 0,
              abs(firstBottomPrice - secondBottomPrice) / firstBottomPrice < 0.05 else {
            return nil
        }
        
        // Confirm rally between bottoms
        let betweenHigh = pricePattern.closes[(firstBottomIdx + 1)..<secondBottomIdx].max() ?? firstBottomPrice
        let rallyConfirm = betweenHigh > firstBottomPrice * 1.03 // 3% rally confirmation
        
        guard rallyConfirm else { return nil }
        
        let breakoutPrice = pricePattern.closes[secondBottomIdx + 1...]?.first
        let targetPrice = max(firstBottomPrice, secondBottomPrice) * 1.10 // 10% target
        let stopLoss = min(firstBottomPrice, secondBottomPrice) * 0.95
        
        return PatternMatch(
            patternType: .doubleBottom,
            confidence: rallyConfirm ? 0.75 : 0.5,
            breakoutPrice: breakoutPrice,
            targetPrice: targetPrice,
            stopLoss: stopLoss,
            completionDate: Date(),
            description: "Double bottom pattern detected with \(String(format: "%.1f", 0.75 * 100))% confidence"
        )
    }
    
    // Detect cup and handle pattern
    public func detectCupAndHandle() -> PatternMatch? {
        guard pricePattern.closes.count >= 30 else { return nil }
        
        // Simplified: look for U-shaped bottom followed by small consolidation
        let third = pricePattern.closes.count / 3
        
        // Find the bottom third
        let bottomSection = Array(pricePattern.closes[0..<third])
        let bottomPrice = bottomSection.min() ?? pricePattern.closes.first!
        
        // Check if price recovered
        let recoverySection = Array(pricePattern.closes[third..<third*2])
        let recoveryHigh = recoverySection.max() ?? bottomPrice
        
        // Check if recovery is roughly symmetric
        let symmetry = abs(recoveryHigh - bottomPrice) / bottomPrice
        guard symmetry < 0.30 else { return nil } // Must be within 30%
        
        // Handle phase: look for small consolidation in last third
        let handleSection = Array(pricePattern.closes[third*2..<pricePattern.closes.count])
        let handleHigh = handleSection.max() ?? bottomPrice
        let handleLow = handleSection.min() ?? handleHigh
        let handleRange = handleHigh - handleLow
        
        // Handle should be smaller than the cup depth
        let cupDepth = recoveryHigh - bottomPrice
        guard handleRange < cupDepth * 0.35 else { return nil }
        
        let targetPrice = recoveryHigh * 1.15 // 15% target from handle high
        let breakoutPrice = handleHigh
        let stopLoss = bottomPrice * 0.97
        
        return PatternMatch(
            patternType: .cupAndHandle,
            confidence: 0.7,
            breakoutPrice: breakoutPrice,
            targetPrice: targetPrice,
            stopLoss: stopLoss,
            completionDate: Date(),
            description: "Cup and handle pattern detected with \(String(format: "%.1f", 0.7 * 100))% confidence"
        )
    }
}

// MARK: - Model Registry
public final class PatternRecognitionRegistry: ObservableObject {
    @Published public var detectedPatterns: [PatternMatch] = []
    @Published public var modelInfo: String = "Pattern recognition ready"
    
    private var recognizer: PatternRecognizer?
    
    public func analyzePricePattern(_ pattern: PricePattern) {
        recognizer = PatternRecognizer(pricePattern: pattern)
        detectedPatterns = []
        
        if let hns = recognizer?.detectHeadAndShoulders() {
            detectedPatterns.append(hns)
        }
        if let db = recognizer?.detectDoubleBottom() {
            detectedPatterns.append(db)
        }
        if let ca = recognizer?.detectCupAndHandle() {
            detectedPatterns.append(ca)
        }
        
        if detectedPatterns.isEmpty {
            modelInfo = "No major patterns detected in current price action"
        } else {
            modelInfo = "Detected \(detectedPatterns.count) pattern(s)"
        }
    }
}
