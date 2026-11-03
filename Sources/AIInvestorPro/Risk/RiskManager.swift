// MARK: - Risk Management
import Foundation

public struct RiskLimits {
    /// Maximum position size as percentage of portfolio
    public var maxPositionSizePct: Double = 2.0
    /// Maximum daily loss as percentage of portfolio
    public var maxDailyLossPct: Double = 5.0
    /// Maximum drawdown as percentage of portfolio
    public var maxDrawdownPct: Double = 15.0
    /// Maximum leverage allowed
    public var maxLeverage: Double = 3.0
    /// Maximum concurrent open positions
    public var maxConcurrentTrades: Int = 10
    /// Maximum correlation between positions
    public var maxPositionCorrelation: Double = 0.7
    
    /// Risk per trade as percentage of portfolio
    public var riskPerTradePct: Double = 1.0
    
    public init(
        maxPositionSizePct: Double = 2.0,
        maxDailyLossPct: Double = 5.0,
        maxDrawdownPct: Double = 15.0,
        maxLeverage: Double = 3.0,
        maxConcurrentTrades: Int = 10,
        maxPositionCorrelation: Double = 0.7,
        riskPerTradePct: Double = 1.0
    ) {
        self.maxPositionSizePct = maxPositionSizePct
        self.maxDailyLossPct = maxDailyLossPct
        self.maxDrawdownPct = maxDrawdownPct
        self.maxLeverage = maxLeverage
        self.maxConcurrentTrades = maxConcurrentTrades
        self.maxPositionCorrelation = maxPositionCorrelation
        self.riskPerTradePct = riskPerTradePct
    }
}


// MARK: - Order
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
    public var filledQuantity: Double
    public let filledPrice: Double?
    public let commission: Double
    
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
        self.filledQuantity = 0
        self.filledPrice = nil
        self.commission = 0.0
        self.timestamp = Date()
    }
}

// MARK: - Order Type
public enum OrderType: String, CaseIterable {
    case market
    case limit
    case stop
    case stopLimit
    case trailingStop
}

// MARK: - Order Status
public enum OrderStatus: String, CaseIterable {
    case pending
    case pendingNew
    case partialFilled
    case filled
    case cancelled
    case rejected
    case expired
}

// MARK: - Trade
public struct Trade {
    public let order: Order
    public let filledQuantity: Double
    public let filledPrice: Double
    public let commission: Double
    public let timestamp: Date
    
    public var netCost: Double {
        filledQuantity * filledPrice + commission
    }
    
    public var pnl: Double {
        // Profit and loss calculation
        // (filledPrice - entryPrice) * filledQuantity - commission
        // This would need entryPrice from the original order
        return 0.0
    }
}

// MARK: - RiskManager
public class RiskManager {
    private let limits: RiskLimits
    private var dailyPnL: Double = 0.0
    private var dailyPnLResetDate: Date = Date()
    private var openPositions: [String: Position] = [:]
    private var tradeHistory: [Trade] = []
    private var correlationMatrix: [[Double]] = [:][]
    
    public init(limits: RiskLimits = RiskLimits()) {
        self.limits = limits
    }
    
    // MARK: - Position
    public struct Position {
        public let symbol: String
        public let side: OrderSide
        public let quantity: Double
        public let entryPrice: Double
        public let currentPrice: Double
        public let stopPrice: Double?
        public let takeProfit: Double?
        public var unrealizedPnL: Double
        public var realizedPnL: Double
        public var marginUsed: Double
        public var tradeId: String
        
        var pnlPercentage: Double {
            guard entryPrice > 0 else { return 0 }
            return (currentPrice - entryPrice) / entryPrice * 100.0 * (side == .buy ? 1 : -1)
        }
    }
    
    public init(
        symbol: String,
        side: OrderSide,
        quantity: Double,
        entryPrice: Double,
        currentPrice: Double,
        stopPrice: Double? = nil,
        takeProfit: Double? = nil,
        tradeId: String = UUID().uuidString
    ) {
        self.symbol = symbol
        self.side = side
        self.quantity = quantity
        self.entryPrice = entryPrice
        self.currentPrice = currentPrice
        self.stopPrice = stopPrice
        self.takeProfit = takeProfit
        self.unrealizedPnL = 0.0
        self.realizedPnL = 0.0
        self.marginUsed = 0.0
        self.tradeId = tradeId
    }
}

// MARK: - Risk Assessment
public extension RiskManager {
    /// Check if a new trade can be entered given current risk state
    /// - Parameters:
    ///   - symbol: Trading symbol
    ///   - quantity: Trade quantity
    ///   - entryPrice: Expected entry price
    ///   - side: Order side (buy/sell)
    /// - Returns: (allowed: Bool, reason: String?, positionSize: Double?)
    func canEnterTrade(
        symbol: String,
        quantity: Double,
        entryPrice: Double,
        side: OrderSide
    ) -> (allowed: Bool, reason: String?, positionSize: Double?) {
        // 1. Check position size limit
        let maxPositionValue = limits.maxPositionSizePct / 100.0 * 10000.0 // Assuming $100k portfolio
        let positionValue = abs(quantity * entryPrice)
        
        guard positionValue <= maxPositionValue else {
            return (false, "Position size $\(String(format: "%.0f", positionValue)) exceeds max $\(String(format: "%.0f", limits.maxPositionSizePct * 1000))", nil)
        }
        
        // 2. Check daily loss limit
        guard dailyPnL >= -limits.maxDailyLossPct / 100.0 * 10000.0 else {
            return (false, "Would exceed daily loss limit of $\(String(format: "%.0f", limits.maxDailyLossPct * 10))", nil)
        }
        
        // 3. Check max concurrent trades
        let activeCount = openPositions.filter { $0.unrealizedPnL != 0 }.count
        guard activeCount < limits.maxConcurrentTrades else {
            return (false, "Maximum concurrent trades (\(limits.maxConcurrentTrades)) already open", nil)
        }
        
        // 4. Check drawdown limit
        guard dailyPnL >= -limits.maxDrawdownPct / 100.0 * 10000.0 else {
            return (false, "Would exceed max drawdown of $\(String(format: "%.0f", limits.maxDrawdownPct * 10))", nil)
        }
        
        // 5. Calculate position size
        let riskAmount = limits.riskPerTradePct / 100.0 * 10000.0 // Portfolio risk amount
        let priceRisk = abs(entryPrice - (stopPrice ?? entryPrice * 0.95)) // Using stop as reference
        let quantityToRisk = riskAmount / priceRisk
        let positionSize = min(quantity, quantityToRisk)
        
        return (true, nil, positionSize)
    }
    
    /// Record a trade and update risk state
    /// - Parameter trade: The executed trade
    func recordTrade(_ trade: Trade) {
        dailyPnL += trade.netCost
        tradeHistory.append(trade)
        
        // Update position tracking
        if let symbol = trade.order.symbol {
            // In a full implementation, we'd track the position details
            // For now, just record the trade
        }
    }
    
    /// Get current portfolio exposure by symbol
    func getExposure(symbol: String) -> Double {
        openPositions[symbol]?.pnlPercentage ?? 0.0
    }
    
    /// Get maximum allowed position size in currency
    func maxPositionValue() -> Double {
        // Assuming $100k portfolio for calculation
        return limits.maxPositionSizePct / 100.0 * 100000.0
    }
}
