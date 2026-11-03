// MARK: - Trade Execution
import Foundation

public enum ExecutionStatus: String, CaseIterable {
    case pending
    case submitted
    case partialFilled
    case filled
    case cancelled
    case rejected
    case expired
    
    public var description: String {
        rawValue.capitalized
    }
}

public enum OrderDuration: String, CaseIterable {
    case day = "day"
    case gtc = "good_til_cancelled"  // Good 'til cancelled
    case ioc = "immediate_or_cancel" // Immediate or cancel
    case fok = "fill_or_kill"        // Fill or kill
    
    public var description: String {
        rawValue.replacingUnderscoresWithSpaces
    }
}

public enum OrderCondition: String, CaseIterable {
    case priceBelow = "price_below"
    case priceAbove = "price_above"
    case volumeAbove = "volume_above"
    case volumeBelow = "volume_below"
    case maCross = "moving_average_cross"
    
    public var description: String {
        rawValue.replacingUnderscoresWithSpaces
    }
}

// MARK: - Execution Result
public struct ExecutionResult {
    public let orderId: String
    public let status: ExecutionStatus
    public let filledQuantity: Double
    public let filledPrice: Double?
    public let averagePrice: Double?
    public let commission: Double
    public let timestamp: Date
    public let error: String?
    
    public var isComplete: Bool {
        status == .filled || status == .cancelled || status == .rejected || status == .expired
    }
    
    public var isSuccessful: Bool {
        status == .filled
    }
    
    public var pnl: Double {
        guard let filledPrice = filledPrice else { return 0 }
        return filledQuantity * (filledPrice - 0) // Simplified PnL
    }
}

// MARK: - Execution Manager
public class ExecutionManager: ObservableObject {
    @Published public var activeOrders: [Order] = []
    @Published public var executionHistory: [ExecutionResult] = []
    @Published public var statusMessage: String = "Ready"
    
    private var orderCounter: Int = 0
    
    public init() {}
    
    // MARK: - Submit Order
    /// Submit a new order for execution
    /// - Parameter order: Order to execute
    /// - Returns: Order ID
    @discardableResult
    public func submit(_ order: Order) -> String {
        orderCounter += 1
        let orderId = "ORD-\(String(format: "%06d", orderCounter))"
        
        // Mark as pending
        var order = order
        order.status = .pending
        
        // Add to active orders
        activeOrders.append(order)
        
        // In a real implementation, this would send to exchange
        // For now, simulate execution
        Task {
            await simulateExecution(orderId: orderId, order: order)
        }
        
        return orderId
    }
    
    // MARK: - Simulate Execution
    private func simulateExecution(orderId: String, _ order: Order) async {
        // Simulate execution delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Determine fill status
        let fillProbability: Double = 0.8 // 80% fill probability
        let randomValue = Double.random(in: 0...1)
        
        let result: ExecutionResult
        
        if randomValue < fillProbability && order.quantity > 0 {
            // Partial or full fill
            let fillQuantity = min(order.quantity, Double.random(in: 0...order.quantity))
            let fillPrice = order.price ?? order.entryPrice
            
            result = ExecutionResult(
                orderId: orderId,
                status: .filled,
                filledQuantity: fillQuantity,
                filledPrice: fillPrice,
                averagePrice: fillPrice,
                commission: fillQuantity * 0.001, // $0.001 per share
                timestamp: Date(),
                error: nil
            )
            
            // Update order status
            if let index = activeOrders.firstIndex(where: { $0.id == order.id }) {
                activeOrders[index].status = .filled
                activeOrders[index].filledQuantity = fillQuantity
                activeOrders[index].filledPrice = fillPrice
            }
        } else {
            // Cancelled or rejected
            result = ExecutionResult(
                orderId: orderId,
                status: .rejected,
                filledQuantity: 0,
                filledPrice: nil,
                averagePrice: nil,
                commission: 0,
                timestamp: Date(),
                error: "Order rejected: insufficient funds or invalid parameters"
            )
        }
        
        // Add to history
        executionHistory.append(result)
        statusMessage = result.status.description
        
        // Remove from active orders after some time
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            self.activeOrders.removeAll { $0.id == orderId }
        }
    }
    
    // MARK: - Cancel Order
    /// Cancel an active order
    /// - Parameter orderId: Order ID to cancel
    public func cancel(orderId: String) {
        if let index = activeOrders.firstIndex(where: { $0.id == orderId }) {
            activeOrders[index].status = .cancelled
            
            let result = ExecutionResult(
                orderId: orderId,
                status: .cancelled,
                filledQuantity: 0,
                filledPrice: nil,
                averagePrice: nil,
                commission: 0,
                timestamp: Date(),
                error: nil
            )
            
            executionHistory.append(result)
            statusMessage = "Order cancelled"
        } else {
            statusMessage = "Order not found"
        }
    }
    
    /// Replace an order (cancel and resubmit)
    /// - Parameters:
    ///   - orderId: Existing order ID
    ///   - newOrder: New order to replace with
    public func replace(orderId: String, with newOrder: Order) {
        cancel(orderId: orderId)
        _ = submit(newOrder)
    }
    
    // MARK: - Order Filtering
    public var pendingOrders: [Order] {
        activeOrders.filter { $0.status == .pending }
    }
    
    public var filledOrders: [Order] {
        activeOrders.filter { $0.status == .filled }
    }
    
    public var cancelledOrders: [Order] {
        activeOrders.filter { $0.status == .cancelled }
    }
    
    // MARK: - Active Position Tracking
    public var openPositions: [RiskManager.Position] {
        activeOrders.compactMap { order in
            guard let (allowed, _, positionSize) = RiskManager().canEnterTrade(
                symbol: order.symbol,
                quantity: order.quantity,
                entryPrice: order.price ?? 0,
                side: order.side
            ) else { return nil }
            
            return RiskManager.Position(
                symbol: order.symbol,
                side: order.side,
                quantity: positionSize,
                entryPrice: order.price ?? 0,
                currentPrice: order.price ?? 0
            )
        }
    }
}

// MARK: - Order Extensions
public extension Order {
    var displayPrice: String {
        price.map { "$\(String(format: "%.2f", $0))" } ?? "MKT"
    }
    
    var displayDuration: String {
        duration.rawValue.replacingUnderscoresWithSpaces
    }
    
    var isMarketOrder: Bool {
        type == .market
    }
    
    var isLimitOrder: Bool {
        type == .limit
    }
}

// MARK: - Duration Extension
private extension String {
    mutating func replacingUnderscoresWithSpaces() -> String {
        self.replacingOccurrences(of: "_", with: " ")
    }
}
