// MARK: - Trade Execution
import Foundation

public enum OrderSide: String, CaseIterable {
    case buy
    case sell
}

public enum OrderType: String, CaseIterable {
    case market
    case limit
    case stop
    case stopLimit
}

public struct Order {
    public let id: String
    public let side: OrderSide
    public let type: OrderType
    public let symbol: String
    public let quantity: Double
    public let price: Double?
    public let stopPrice: Double?
    public let timestamp: Date
    public var status: OrderStatus
    
    public init(
        id: String = UUID().uuidString,
        side: OrderSide,
        type: OrderType,
        symbol: String,
        quantity: Double,
        price: Double? = nil,
        stopPrice: Double? = nil
    ) {
        self.id = id
        self.side = side
        self.type = type
        self.symbol = symbol
        self.quantity = quantity
        self.price = price
        self.stopPrice = stopPrice
        self.status = .pending
        self.timestamp = Date()
    }
}

public enum OrderStatus: String, CaseIterable {
    case pending
    case filled
    case partial
    case cancelled
    case rejected
}

public struct Trade {
    public let order: Order
    public let filledQuantity: Double
    public let filledPrice: Double
    public let commission: Double
    public let timestamp: Date
    
    public var netCost: Double {
        filledQuantity * filledPrice + commission
    }
}
