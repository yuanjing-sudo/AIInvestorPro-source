// MARK: - Alerts Module
import Foundation

public struct Alert {
    public let symbol: String
    public let alertType: AlertType
    public let targetPrice: Double
    public let triggeredPrice: Double?
    public let triggeredAt: Date?
    public var isTriggered: Bool { triggeredPrice != nil }
    
    public init(symbol: String, alertType: AlertType, targetPrice: Double) {
        self.symbol = symbol
        self.alertType = alertType
        self.targetPrice = targetPrice
        self.triggeredAt = nil
    }
}

public enum AlertType: String, CaseIterable {
    case above = "above"
    case below = "below"
    case crossAbove = "cross above"
    case crossBelow = "cross below"
}

public struct AlertStore: ObservableObject {
    @Published public var alerts: [Alert] = []
    @Published public var triggeredCount: Int = 0
    
    public init() {}
    
    /// Add a new price alert
    mutating func add(symbol: String, alertType: AlertType, targetPrice: Double) {
        // Check if alert already exists
        if !alerts.contains(where: { $0.symbol == symbol && $0.alertType == alertType && $0.targetPrice == targetPrice }) {
            alerts.append(Alert(symbol: symbol, alertType: alertType, targetPrice: targetPrice))
        }
    }
    
    /// Check and trigger alerts against current market data
    mutating func checkAlerts(for snapshots: [MarketSnapshot]) {
        triggeredCount = 0
        
        for snapshot in snapshots where snapshots.count > 0 {
            for index in alerts.indices.reversed() {
                let alert = alerts[index]
                let currentPrice = snapshot.currentPrice
                
                var triggered = false
                
                switch alert.alertType {
                case .above:
                    triggered = currentPrice >= alert.targetPrice
                case .below:
                    triggered = currentPrice <= alert.targetPrice
                case .crossAbove:
                    // Would need previous price - simplified
                    triggered = currentPrice >= alert.targetPrice
                case .crossBelow:
                    // Would need previous price - simplified
                    triggered = currentPrice <= alert.targetPrice
                }
                
                if triggered && !alert.isTriggered {
                    alerts[index].triggeredPrice = currentPrice
                    alerts[index].triggeredAt = Date()
                    triggeredCount += 1
                }
            }
        }
    }
    
    /// Remove triggered alerts
    mutating func clearTriggered() {
        alerts.removeAll { $0.isTriggered }
        triggeredCount = 0
    }
}

// MARK: - Alert Extensions
extension Alert {
    var description: String {
        "\(symbol) \(alertType.rawValue) \(String(format: "$%.2f", targetPrice))"
    }
}
