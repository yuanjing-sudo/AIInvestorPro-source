// MARK: - Portfolio
import Foundation
import Combine

public struct Holding: Identifiable, Equatable, Sendable {
    public let id: String
    public var symbol: String
    public var quantity: Double
    public var averageCost: Double
    public var currentPrice: Double

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

    public init(
        symbol: String,
        quantity: Double,
        averageCost: Double,
        currentPrice: Double? = nil,
        id: String? = nil
    ) {
        // Use the symbol as a stable identifier when the caller does not need
        // lot-level identity. Portfolio merges positions by symbol, so this
        // keeps SwiftUI identity stable across reconstruction.
        self.id = id ?? symbol
        self.symbol = symbol
        self.quantity = quantity
        self.averageCost = averageCost
        self.currentPrice = currentPrice ?? averageCost
    }
}

/// A simple long-only portfolio. Marked `ObservableObject` so SwiftUI views can
/// observe price, cash and holding changes.
public final class Portfolio: ObservableObject, Identifiable, @unchecked Sendable {
    public let id: String
    @Published public var holdings: [Holding]
    @Published public var cash: Double

    public var totalValue: Double {
        holdings.reduce(0) { $0 + $1.currentValue } + cash
    }

    public init(holdings: [Holding] = [], cash: Double = 0.0) {
        self.id = UUID().uuidString
        self.holdings = holdings
        self.cash = cash
    }

    /// Add units at their average cost. Existing positions are averaged by
    /// cost, and the current market price is preserved.
    public func add(_ holding: Holding) {
        guard holding.quantity != 0 else { return }

        if let existingIndex = holdings.firstIndex(where: { $0.symbol == holding.symbol }) {
            let existing = holdings[existingIndex]
            let newQuantity = existing.quantity + holding.quantity

            if newQuantity == 0 {
                holdings.remove(at: existingIndex)
                return
            }

            // Selling part of a position does not change its average cost.
            if holding.quantity > 0 {
                let totalCost = existing.averageCost * existing.quantity
                    + holding.averageCost * holding.quantity
                holdings[existingIndex].averageCost = totalCost / newQuantity
            }
            holdings[existingIndex].quantity = newQuantity
            holdings[existingIndex].currentPrice = holding.currentPrice
        } else if holding.quantity > 0 {
            holdings.append(holding)
        }
    }

    public func remove(symbol: String, quantity: Double) {
        guard quantity > 0,
              let existingIndex = holdings.firstIndex(where: { $0.symbol == symbol }) else {
            return
        }

        if holdings[existingIndex].quantity <= quantity {
            holdings.remove(at: existingIndex)
        } else {
            holdings[existingIndex].quantity -= quantity
        }
    }

    public func updatePrice(_ newPrice: [String: Double]) {
        for index in holdings.indices {
            if let price = newPrice[holdings[index].symbol], price > 0 {
                holdings[index].currentPrice = price
            }
        }
    }

    /// Unrealized profit and loss across all open positions.
    public func totalGainLoss() -> Double {
        holdings.reduce(0) { $0 + $1.unrealizedPnL }
    }

    public func totalGainLossPercentage() -> Double {
        let costBasis = holdings.reduce(0) { $0 + $1.costBasis }
        guard costBasis > 0 else { return 0 }
        return totalGainLoss() / costBasis * 100.0
    }
}

// MARK: - Portfolio Metrics
public extension Portfolio {
    /// Portfolio volatility requires a return history. The current model stores
    /// only the latest price, so this deliberately returns zero rather than a
    /// fabricated constant.
    var volatility: Double {
        0
    }

    /// Portfolio beta requires a market return series. The current model does
    /// not store one, so the neutral value is returned.
    var beta: Double {
        1.0
    }

    /// Sharpe ratio using total return and the available volatility estimate.
    var sharpeRatio: Double {
        let excessReturn = totalReturn() / 100.0
        let vol = volatility
        return vol > 0 ? excessReturn / vol : 0
    }

    /// Return on the cost basis plus cash, expressed as a percentage.
    func totalReturn() -> Double {
        let initialValue = holdings.reduce(0) { $0 + $1.costBasis } + cash
        guard initialValue > 0 else { return 0 }
        return (totalValue - initialValue) / initialValue * 100.0
    }
}

// MARK: - Portfolio Helper Extensions
extension Holding {
    var description: String {
        "\(symbol): \(String(format: "%.2f", quantity)) @ $\(String(format: "%.2f", averageCost)) = $\(String(format: "%.2f", currentValue)) (\(String(format: "%.2f", unrealizedPnLPercentage))%)"
    }
}

extension Portfolio {
    var description: String {
        "Portfolio: \(holdings.count) holdings, $\(String(format: "%.2f", cash)) cash, \(String(format: "%.2f", totalReturn()))% return"
    }
}
