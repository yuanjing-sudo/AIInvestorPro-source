import Foundation

// MARK: - Alert Types

public enum AlertCondition: String, Codable, Sendable, CaseIterable {
    case priceAbove = "price_above"
    case priceBelow = "price_below"
    case crossesAbove = "crosses_above"
    case crossesBelow = "crosses_below"
    case percentChangeAbove = "percent_change_above"
    case percentChangeBelow = "percent_change_below"
}

public struct AlertRule: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let symbol: String
    public let condition: AlertCondition
    /// Price for price conditions, or percent (for example `5` = +5%) for
    /// percent-change conditions.
    public let threshold: Double
    public var isEnabled: Bool
    public var isOneShot: Bool
    public var cooldown: TimeInterval
    public var lastTriggeredAt: Date?
    public var note: String?

    public init(
        id: UUID = UUID(),
        symbol: String,
        condition: AlertCondition,
        threshold: Double,
        isEnabled: Bool = true,
        isOneShot: Bool = false,
        cooldown: TimeInterval = 60,
        lastTriggeredAt: Date? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.symbol = symbol.uppercased()
        self.condition = condition
        self.threshold = threshold
        self.isEnabled = isEnabled
        self.isOneShot = isOneShot
        self.cooldown = max(0, cooldown)
        self.lastTriggeredAt = lastTriggeredAt
        self.note = note
    }
}

public struct AlertEvent: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let ruleID: UUID
    public let symbol: String
    public let condition: AlertCondition
    public let threshold: Double
    public let observedPrice: Double
    public let triggeredAt: Date
    public let message: String

    public init(
        id: UUID = UUID(),
        ruleID: UUID,
        symbol: String,
        condition: AlertCondition,
        threshold: Double,
        observedPrice: Double,
        triggeredAt: Date,
        message: String
    ) {
        self.id = id
        self.ruleID = ruleID
        self.symbol = symbol
        self.condition = condition
        self.threshold = threshold
        self.observedPrice = observedPrice
        self.triggeredAt = triggeredAt
        self.message = message
    }
}

// MARK: - Engine

/// Edge-triggered alert engine.
///
/// A rule fires when its condition transitions from `false` to `true`, subject
/// to an optional cooldown. This avoids re-firing a "price above 150" alert on
/// every poll while the price remains above the threshold. Use the `crosses*`
/// conditions when you only care about the crossing event itself.
public struct AlertRuleEngine: Sendable {
    public private(set) var rules: [AlertRule]
    private var previousPrices: [String: Double] = [:]
    private var conditionState: [UUID: Bool] = [:]

    public init(rules: [AlertRule] = []) {
        self.rules = rules
    }

    // MARK: Rule management

    public mutating func add(_ rule: AlertRule) {
        rules.append(rule)
        conditionState[rule.id] = false
    }

    public mutating func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        conditionState.removeValue(forKey: id)
    }

    public mutating func removeAll() {
        rules.removeAll()
        conditionState.removeAll()
        previousPrices.removeAll()
    }

    public mutating func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isEnabled = enabled
        if enabled {
            // Re-arm so an already-true condition can fire once after enabling.
            conditionState[id] = false
        }
    }

    public mutating func resetHistory() {
        previousPrices.removeAll()
        conditionState = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, false) })
        for index in rules.indices {
            rules[index].lastTriggeredAt = nil
        }
    }

    // MARK: Evaluation

    public mutating func evaluate(_ quotes: [Quote], at date: Date = Date()) -> [AlertEvent] {
        var quotesBySymbol: [String: Quote] = [:]
        for quote in quotes {
            quotesBySymbol[quote.symbol.uppercased()] = quote
        }

        var events: [AlertEvent] = []

        for index in rules.indices {
            let rule = rules[index]
            guard rule.isEnabled,
                  let quote = quotesBySymbol[rule.symbol]
            else { continue }

            let observed = quote.price
            let met = isConditionMet(rule: rule, quote: quote, observed: observed)
            let wasMet = conditionState[rule.id] ?? false
            conditionState[rule.id] = met

            guard met, !wasMet else { continue }

            if let last = rule.lastTriggeredAt,
               date.timeIntervalSince(last) < rule.cooldown {
                continue
            }

            let event = AlertEvent(
                ruleID: rule.id,
                symbol: rule.symbol,
                condition: rule.condition,
                threshold: rule.threshold,
                observedPrice: observed,
                triggeredAt: date,
                message: message(for: rule, observed: observed)
            )
            events.append(event)
            rules[index].lastTriggeredAt = date
            if rule.isOneShot {
                rules[index].isEnabled = false
            }
        }

        for quote in quotes {
            previousPrices[quote.symbol.uppercased()] = quote.price
        }
        return events
    }

    // MARK: Internals

    private func isConditionMet(rule: AlertRule, quote: Quote, observed: Double) -> Bool {
        switch rule.condition {
        case .priceAbove:
            return observed >= rule.threshold
        case .priceBelow:
            return observed <= rule.threshold
        case .crossesAbove:
            guard let previous = previousPrices[rule.symbol] else { return false }
            return previous < rule.threshold && observed >= rule.threshold
        case .crossesBelow:
            guard let previous = previousPrices[rule.symbol] else { return false }
            return previous > rule.threshold && observed <= rule.threshold
        case .percentChangeAbove:
            guard let change = percentChange(quote: quote) else { return false }
            return change >= rule.threshold
        case .percentChangeBelow:
            guard let change = percentChange(quote: quote) else { return false }
            return change <= rule.threshold
        }
    }

    private func percentChange(quote: Quote) -> Double? {
        if let change = quote.changePercent {
            return change
        }
        if let previous = quote.previousClose, previous > 0 {
            return (quote.price - previous) / previous * 100
        }
        if let previous = previousPrices[quote.symbol.uppercased()], previous > 0 {
            return (quote.price - previous) / previous * 100
        }
        return nil
    }

    private func message(for rule: AlertRule, observed: Double) -> String {
        switch rule.condition {
        case .priceAbove:
            return "\(rule.symbol) rose to \(observed.formattedCurrency()), above \(rule.threshold.formattedCurrency())"
        case .priceBelow:
            return "\(rule.symbol) fell to \(observed.formattedCurrency()), below \(rule.threshold.formattedCurrency())"
        case .crossesAbove:
            return "\(rule.symbol) crossed above \(rule.threshold.formattedCurrency()) at \(observed.formattedCurrency())"
        case .crossesBelow:
            return "\(rule.symbol) crossed below \(rule.threshold.formattedCurrency()) at \(observed.formattedCurrency())"
        case .percentChangeAbove:
            return "\(rule.symbol) moved \(String(format: "%.2f", rule.threshold))% or more, now at \(observed.formattedCurrency())"
        case .percentChangeBelow:
            return "\(rule.symbol) moved \(String(format: "%.2f", rule.threshold))% or less, now at \(observed.formattedCurrency())"
        }
    }
}
