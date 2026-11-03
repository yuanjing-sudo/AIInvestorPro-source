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

public class AlertStore: ObservableObject {
    @Published public var alerts: [Alert] = []
    @Published public var triggeredCount: Int = 0
    
    public init() {}
    
    /// Add a new price alert
    func add(symbol: String, alertType: AlertType, targetPrice: Double) {
        // Check if alert already exists
        if !alerts.contains(where: { $0.symbol == symbol && $0.alertType == alertType && $0.targetPrice == targetPrice }) {
            alerts.append(Alert(symbol: symbol, alertType: alertType, targetPrice: targetPrice))
        }
    }
    
    /// Check and trigger alerts against current market data
    func checkAlerts(for snapshots: [MarketSnapshot]) {
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
                    // For cross detection, would need previous price
                    triggered = currentPrice >= alert.targetPrice
                case .crossBelow:
                    // For cross detection, would need previous price
                    triggered = currentPrice <= alert.targetPrice
                }
                
                if triggered && !alert.isTriggered {
                    // Update the alert with triggered price
                    // Since Alert is a struct with let properties, we need to create a new one
                    alerts[index] = Alert(
                        symbol: alert.symbol,
                        alertType: alert.alertType,
                        targetPrice: alert.targetPrice
                    )
                    alerts[index].triggeredPrice = currentPrice
                    alerts[index].triggeredAt = Date()
                    triggeredCount += 1
                }
            }
        }
    }
    
    /// Clear triggered alerts
    func clearTriggered() {
        alerts.removeAll { $0.isTriggered }
        triggeredCount = 0
    }
}
