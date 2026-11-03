// MARK: - Portfolio
import Foundation

public struct Holding: Identifiable, Equatable {
    public let id: String
    public let symbol: String
    public let quantity: Double
    public let averageCost: Double
    public let currentPrice: Double
    public var currentValue: Double {
        quantity * currentPrice
    }
    public var costBasis: Double {
        quantity * averageCost
    }
    public var unrealizedPnL: Double {
        currentValue - costBasis
    }
    public var unrealizedPnLPercentage: Double {
        guard averageCost > 0 else { return 0 }
        return (currentPrice - averageCost) / averageCost * 100.0
    }
    
    public init(symbol: String, quantity: Double, averageCost: Double) {
        self.id = UUID().uuidString
        self.symbol = symbol
        self.quantity = quantity
        self.averageCost = averageCost
        self.currentPrice = averageCost // Initialize to average cost
    }
}

public struct Portfolio: Equatable {
    public var id: String { uuidString }
    public let uuidString: String
    public var holdings: [Holding]
    public var cash: Double
    public var totalValue: Double {
        holdings.reduce(0) { $0 + $1.currentValue } + cash
    }
    
    public init(holdings: [Holding] = [], cash: Double = 0.0) {
        self.uuidString = UUID().uuidString
        self.holdings = holdings
        self.cash = cash
    }
    
    public mutating func add(_ holding: Holding) {
        if let existingIndex = holdings.firstIndex(where: { $0.symbol == holding.symbol }) {
            holdings[existingIndex].quantity += holding.quantity
        } else {
            holdings.append(holding)
        }
    }
    
    public mutating func remove(symbol: String, quantity: Double) {
        if let existingIndex = holdings.firstIndex(where: { $0.symbol == symbol }) {
            if holdings[existingIndex].quantity <= quantity {
                holdings.remove(at: existingIndex)
            } else {
                holdings[existingIndex].quantity -= quantity
            }
        }
    }
    
    public mutating func updatePrice(_ newPrice: [String: Double]) {
        for i in holdings.indices {
            if let price = newPrice[holdings[i].symbol] {
                holdings[i].currentPrice = price
            }
        }
    }
    
    public func totalGainLoss() -> Double {
        holdings.reduce(0) { $0 + $1.unrealizedPnL } + (cash > 0 ? 0 : 0)
    }
    
    public func totalGainLossPercentage() -> Double {
        guard totalValue > 0 else { return 0 }
        let costBasis = holdings.reduce(0) { $0 + $1.costBasis }
        return (totalValue - costBasis) / totalValue * 100.0
    }
}

// MARK: - Portfolio Metrics
public extension Portfolio {
    /// Calculate portfolio volatility (approximate)
    var volatility: Double {
        guard holdings.count > 1 else { return 0 }
        let returns = holdings.map { holding in
            // Simplified: assume 1-month return based on price change
            0.0 // Would need price history
        }
        return returns.isEmpty ? 0 : 0.1 // Placeholder
    }
    
    /// Calculate portfolio beta vs market
    var beta: Double {
        // Would need market data comparison
        return 1.0
    }
    
    /// Calculate Sharpe ratio (assuming risk-free rate)
    var sharpeRatio: Double {
        let excessReturn = totalReturn() / 100.0 // Simplified
        let vol = volatility
        return vol > 0 ? excessReturn / vol : 0
    }
    
    /// Calculate total return percentage
    func totalReturn() -> Double {
        guard totalValue > 0 else { return 0 }
        let initialValue = holdings.reduce(0) { $0 + $1.costBasis } + cash
        return (totalValue - initialValue) / initialValue * 100.0
    }
}

// MARK: - Portfolio Helper Extensions
extension Holding {
    var description: String {
        "\(symbol): \(String(format: "%.2f", quantity)) @ $\(String(format: "%.2f", averageCost)) = $\(String(format: "%.2f", currentValue)) (\(String(format: "%.2f%", unrealizedPnLPercentage)))"
    }
}

extension Portfolio {
    var description: String {
        "Portfolio: \(holdings.count) holdings, $\(String(format: "%.2f", totalValue)) cash, +\(String(format: "%.2f%", totalReturn())) return"
    }
}
