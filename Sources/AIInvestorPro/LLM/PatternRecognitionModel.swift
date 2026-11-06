// MARK: - Technical Pattern Recognition
import Foundation
import Combine

public enum PatternType: String, CaseIterable, Identifiable, Sendable, Equatable {
    case headAndShoulders = "head_and_shoulders"
    case doubleTop = "double_top"
    case doubleBottom = "double_bottom"
    case cupAndHandle = "cup_and_handle"
    case flag = "flag"
    case wedge = "wedge"
    case triangle = "triangle"
    case supportBreakout = "support_breakout"
    case resistanceBreakout = "resistance_breakout"

    public var id: String { rawValue }

    public var description: String {
        rawValue.replacingUnderscoresWithSpaces
    }
}

public struct PatternMatch: Identifiable, Equatable, Sendable {
    public var id: String { patternType.rawValue }
    public let patternType: PatternType
    public let confidence: Double
    public let breakoutPrice: Double?
    public let targetPrice: Double?
    public let stopLoss: Double?
    public let completionDate: Date?
    public let description: String

    public init(
        patternType: PatternType,
        confidence: Double,
        breakoutPrice: Double? = nil,
        targetPrice: Double? = nil,
        stopLoss: Double? = nil,
        completionDate: Date? = nil,
        description: String
    ) {
        self.patternType = patternType
        self.confidence = confidence
        self.breakoutPrice = breakoutPrice
        self.targetPrice = targetPrice
        self.stopLoss = stopLoss
        self.completionDate = completionDate
        self.description = description
    }

    public static func == (lhs: PatternMatch, rhs: PatternMatch) -> Bool {
        lhs.patternType == rhs.patternType && lhs.confidence == rhs.confidence
    }
}

public struct PricePattern: Sendable {
    public let highs: [Double]
    public let lows: [Double]
    public let closes: [Double]
    public let dates: [Date]
    public let volumes: [Double]

    public init(
        closes: [Double],
        highs: [Double]? = nil,
        lows: [Double]? = nil,
        dates: [Date]? = nil,
        volumes: [Double]? = nil
    ) {
        self.closes = closes
        self.highs = highs ?? closes.map { $0 * 1.02 }
        self.lows = lows ?? closes.map { $0 * 0.98 }
        self.dates = dates ?? (0..<closes.count).map {
            Date().addingTimeInterval(-86_400 * Double(closes.count - 1 - $0))
        }
        self.volumes = volumes ?? Array(repeating: 1_000_000, count: closes.count)
    }
}

// MARK: - Pattern Detection Engine
public final class PatternRecognizer {
    private let pricePattern: PricePattern

    public init(pricePattern: PricePattern) {
        self.pricePattern = pricePattern
    }

    public func detectHeadAndShoulders() -> PatternMatch? {
        let closes = pricePattern.closes
        guard closes.count >= 20 else { return nil }

        let midPoint = closes.count / 2
        let leftSection = closes[0..<midPoint]
        let rightSection = closes[midPoint...]
        guard let leftMin = leftSection.min(),
              let rightMin = rightSection.min(),
              let rightIndex = rightSection.firstIndex(of: rightMin) else {
            return nil
        }

        let head = closes[midPoint]
        let shoulderThreshold = 0.03
        guard head > leftMin * (1 + shoulderThreshold),
              head > rightMin * (1 + shoulderThreshold) else {
            return nil
        }

        let breakoutPrice = rightIndex + 1 < closes.count ? closes[rightIndex + 1] : nil
        let neckline = (leftMin + rightMin) / 2
        let targetPrice = neckline + (head - neckline)
        let stopLoss = leftMin * 0.98
        let confidence = 0.8

        return PatternMatch(
            patternType: .headAndShoulders,
            confidence: confidence,
            breakoutPrice: breakoutPrice,
            targetPrice: targetPrice,
            stopLoss: stopLoss,
            completionDate: Date(),
            description: "Head and shoulders pattern detected with \(String(format: "%.1f", confidence * 100))% confidence"
        )
    }

    public func detectDoubleBottom() -> PatternMatch? {
        let closes = pricePattern.closes
        guard closes.count >= 20 else { return nil }

        let midPoint = closes.count / 2
        let firstSection = closes[0..<midPoint]
        let secondSection = closes[midPoint...]
        guard let firstBottomPrice = firstSection.min(),
              let firstBottomOffset = firstSection.firstIndex(of: firstBottomPrice),
              let secondBottomPrice = secondSection.min(),
              let secondBottomOffset = secondSection.firstIndex(of: secondBottomPrice),
              firstBottomPrice > 0 else {
            return nil
        }

        guard abs(firstBottomPrice - secondBottomPrice) / firstBottomPrice < 0.05 else {
            return nil
        }

        let betweenStart = firstBottomOffset + 1
        let betweenEnd = secondBottomOffset
        guard betweenStart < betweenEnd else { return nil }
        let betweenHigh = closes[betweenStart..<betweenEnd].max() ?? firstBottomPrice
        guard betweenHigh > firstBottomPrice * 1.03 else { return nil }

        let breakoutPrice = secondBottomOffset + 1 < closes.count ? closes[secondBottomOffset + 1] : nil
        let targetPrice = max(firstBottomPrice, secondBottomPrice) * 1.10
        let stopLoss = min(firstBottomPrice, secondBottomPrice) * 0.95
        let confidence = 0.75

        return PatternMatch(
            patternType: .doubleBottom,
            confidence: confidence,
            breakoutPrice: breakoutPrice,
            targetPrice: targetPrice,
            stopLoss: stopLoss,
            completionDate: Date(),
            description: "Double bottom pattern detected with \(String(format: "%.1f", confidence * 100))% confidence"
        )
    }

    public func detectCupAndHandle() -> PatternMatch? {
        let closes = pricePattern.closes
        guard closes.count >= 30 else { return nil }

        let third = closes.count / 3
        guard third > 0 else { return nil }

        let bottomPrice = closes[0..<third].min()
        let recoveryHigh = closes[third..<(third * 2)].max()
        guard let bottomPrice, let recoveryHigh, bottomPrice > 0 else { return nil }

        let symmetry = abs(recoveryHigh - bottomPrice) / bottomPrice
        guard symmetry < 0.30 else { return nil }

        let handleSection = closes[(third * 2)..<closes.count]
        guard let handleHigh = handleSection.max(),
              let handleLow = handleSection.min() else {
            return nil
        }
        let handleRange = handleHigh - handleLow
        let cupDepth = recoveryHigh - bottomPrice
        guard cupDepth > 0, handleRange < cupDepth * 0.35 else { return nil }

        let targetPrice = handleHigh * 1.15
        let stopLoss = bottomPrice * 0.97
        let confidence = 0.7

        return PatternMatch(
            patternType: .cupAndHandle,
            confidence: confidence,
            breakoutPrice: handleHigh,
            targetPrice: targetPrice,
            stopLoss: stopLoss,
            completionDate: Date(),
            description: "Cup and handle pattern detected with \(String(format: "%.1f", confidence * 100))% confidence"
        )
    }
}

// MARK: - Model Registry
public final class PatternRecognitionRegistry: ObservableObject {
    @Published public var detectedPatterns: [PatternMatch] = []
    @Published public var modelInfo: String = "Pattern recognition ready"

    private var recognizer: PatternRecognizer?

    public init() {}

    public func analyzePricePattern(_ pattern: PricePattern) {
        recognizer = PatternRecognizer(pricePattern: pattern)
        detectedPatterns = []

        if let headAndShoulders = recognizer?.detectHeadAndShoulders() {
            detectedPatterns.append(headAndShoulders)
        }
        if let doubleBottom = recognizer?.detectDoubleBottom() {
            detectedPatterns.append(doubleBottom)
        }
        if let cupAndHandle = recognizer?.detectCupAndHandle() {
            detectedPatterns.append(cupAndHandle)
        }

        modelInfo = detectedPatterns.isEmpty
            ? "No major patterns detected in current price action"
            : "Detected \(detectedPatterns.count) pattern(s)"
    }
}
