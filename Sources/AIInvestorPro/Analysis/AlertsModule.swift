// MARK: - Alerts Module
import Foundation
import Combine

public struct Alert: Identifiable, Equatable, Sendable {
    public let id: String
    public let symbol: String
    public let alertType: AlertType
    public let targetPrice: Double
    public var triggeredPrice: Double?
    public var triggeredAt: Date?

    public var isTriggered: Bool { triggeredPrice != nil }

    public init(
        id: String = UUID().uuidString,
        symbol: String,
        alertType: AlertType,
        targetPrice: Double,
        triggeredPrice: Double? = nil,
        triggeredAt: Date? = nil
    ) {
        self.id = id
        self.symbol = symbol
        self.alertType = alertType
        self.targetPrice = targetPrice
        self.triggeredPrice = triggeredPrice
        self.triggeredAt = triggeredAt
    }
}

public enum AlertType: String, CaseIterable, Sendable, Equatable {
    case above = "above"
    case below = "below"
    case crossAbove = "cross above"
    case crossBelow = "cross below"
}

public final class AlertStore: ObservableObject {
    @Published public var alerts: [Alert] = []
    @Published public var triggeredCount: Int = 0

    /// Previous observed price per symbol, used to distinguish a real crossing
    /// from a price that was already beyond the threshold.
    private var lastPrices: [String: Double] = [:]

    public init() {}

    public func add(symbol: String, alertType: AlertType, targetPrice: Double) {
        guard !alerts.contains(where: {
            $0.symbol == symbol && $0.alertType == alertType && $0.targetPrice == targetPrice
        }) else { return }
        alerts.append(Alert(symbol: symbol, alertType: alertType, targetPrice: targetPrice))
    }

    /// Check alerts against current snapshots. An alert only evaluates the
    /// snapshot for its own symbol.
    public func checkAlerts(for snapshots: [MarketSnapshot]) {
        let prices = Dictionary(
            snapshots.map { ($0.symbol, $0.currentPrice) },
            uniquingKeysWith: { first, _ in first }
        )
        triggeredCount = 0

        for index in alerts.indices {
            let symbol = alerts[index].symbol
            guard let currentPrice = prices[symbol],
                  !alerts[index].isTriggered else { continue }

            let alert = alerts[index]
            let previousPrice = lastPrices[symbol]
            let triggered: Bool
            switch alert.alertType {
            case .above:
                triggered = currentPrice >= alert.targetPrice
            case .below:
                triggered = currentPrice <= alert.targetPrice
            case .crossAbove:
                triggered = (previousPrice ?? alert.targetPrice) <= alert.targetPrice
                    && currentPrice > alert.targetPrice
            case .crossBelow:
                triggered = (previousPrice ?? alert.targetPrice) >= alert.targetPrice
                    && currentPrice < alert.targetPrice
            }

            if triggered {
                alerts[index].triggeredPrice = currentPrice
                alerts[index].triggeredAt = Date()
                triggeredCount += 1
            }
        }

        for (symbol, price) in prices {
            lastPrices[symbol] = price
        }
    }

    public func clearTriggered() {
        alerts.removeAll { $0.isTriggered }
        triggeredCount = 0
    }
}
