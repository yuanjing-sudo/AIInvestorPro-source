// MARK: - Risk Management
import Foundation

public struct RiskLimits: Sendable {
    public var maxPositionSizePct: Double = 2.0
    public var maxDailyLossPct: Double = 5.0
    public var maxDrawdownPct: Double = 15.0
    public var maxLeverage: Double = 3.0
    public var maxConcurrentTrades: Int = 10
    public var maxPositionCorrelation: Double = 0.7
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
public struct Order: Identifiable, Sendable {
    public let id: String
    public let side: OrderSide
    public let type: OrderType
    public let symbol: String
    public let quantity: Double
    public let price: Double?
    public let stopPrice: Double?
    public let duration: OrderDuration
    public let timestamp: Date
    public var status: OrderStatus
    public var filledQuantity: Double
    public var filledPrice: Double?
    public var commission: Double

    public init(
        id: String = UUID().uuidString,
        side: OrderSide,
        type: OrderType,
        symbol: String,
        quantity: Double,
        price: Double? = nil,
        stopPrice: Double? = nil,
        duration: OrderDuration = .day
    ) {
        self.id = id
        self.side = side
        self.type = type
        self.symbol = symbol
        self.quantity = quantity
        self.price = price
        self.stopPrice = stopPrice
        self.duration = duration
        self.status = .pending
        self.filledQuantity = 0
        self.filledPrice = nil
        self.commission = 0.0
        self.timestamp = Date()
    }
}

public enum OrderType: String, CaseIterable, Sendable, Equatable {
    case market
    case limit
    case stop
    case stopLimit
    case trailingStop
}

public enum OrderStatus: String, CaseIterable, Sendable, Equatable {
    case pending
    case pendingNew
    case partialFilled
    case filled
    case cancelled
    case rejected
    case expired
}

// MARK: - Trade
public struct Trade: Sendable {
    public let order: Order
    public let filledQuantity: Double
    public let filledPrice: Double
    public let commission: Double
    public let timestamp: Date

    public init(
        order: Order,
        filledQuantity: Double,
        filledPrice: Double,
        commission: Double = 0,
        timestamp: Date = Date()
    ) {
        self.order = order
        self.filledQuantity = filledQuantity
        self.filledPrice = filledPrice
        self.commission = commission
        self.timestamp = timestamp
    }

    public var netCost: Double {
        let sign = order.side == .buy ? 1.0 : -1.0
        return filledQuantity * filledPrice * sign + commission
    }

    public var pnl: Double {
        guard let entry = order.price, entry > 0 else { return 0 }
        let direction = order.side == .buy ? 1.0 : -1.0
        return (filledPrice - entry) * filledQuantity * direction - commission
    }
}

// MARK: - Risk Manager
public final class RiskManager {
    public struct Position: Identifiable, Sendable {
        public let id: String
        public let symbol: String
        public let side: OrderSide
        public let quantity: Double
        public let entryPrice: Double
        public var currentPrice: Double
        public let stopPrice: Double?
        public let takeProfit: Double?
        public var unrealizedPnL: Double
        public var realizedPnL: Double
        public var marginUsed: Double

        public var pnlPercentage: Double {
            guard entryPrice > 0 else { return 0 }
            return (currentPrice - entryPrice) / entryPrice * 100.0 * (side == .buy ? 1 : -1)
        }

        public init(
            id: String = UUID().uuidString,
            symbol: String,
            side: OrderSide,
            quantity: Double,
            entryPrice: Double,
            currentPrice: Double,
            stopPrice: Double? = nil,
            takeProfit: Double? = nil,
            unrealizedPnL: Double = 0,
            realizedPnL: Double = 0,
            marginUsed: Double = 0
        ) {
            self.id = id
            self.symbol = symbol
            self.side = side
            self.quantity = quantity
            self.entryPrice = entryPrice
            self.currentPrice = currentPrice
            self.stopPrice = stopPrice
            self.takeProfit = takeProfit
            self.unrealizedPnL = unrealizedPnL
            self.realizedPnL = realizedPnL
            self.marginUsed = marginUsed
        }
    }

    private let limits: RiskLimits
    private var dailyPnL: Double = 0.0
    private var dailyPnLResetDate: Date = Date()
    private var openPositions: [String: Position] = [:]
    private var tradeHistory: [Trade] = []

    public init(limits: RiskLimits = RiskLimits()) {
        self.limits = limits
    }

    /// Check if a new trade can be entered.
    public func canEnterTrade(
        symbol: String,
        quantity: Double,
        entryPrice: Double,
        side: OrderSide,
        stopPrice: Double? = nil,
        portfolioValue: Double = 100_000
    ) -> (allowed: Bool, reason: String?, positionSize: Double?) {
        let maxPositionValue = limits.maxPositionSizePct / 100.0 * portfolioValue
        let positionValue = abs(quantity * entryPrice)

        guard positionValue <= maxPositionValue else {
            return (false, "Position size \(currency(positionValue)) exceeds max \(currency(maxPositionValue))", nil)
        }

        guard dailyPnL >= -limits.maxDailyLossPct / 100.0 * portfolioValue else {
            return (false, "Would exceed daily loss limit of \(currency(limits.maxDailyLossPct / 100.0 * portfolioValue))", nil)
        }

        let activeCount = openPositions.values.filter { $0.unrealizedPnL != 0 }.count
        guard activeCount < limits.maxConcurrentTrades else {
            return (false, "Maximum concurrent trades (\(limits.maxConcurrentTrades)) already open", nil)
        }

        guard dailyPnL >= -limits.maxDrawdownPct / 100.0 * portfolioValue else {
            return (false, "Would exceed max drawdown of \(currency(limits.maxDrawdownPct / 100.0 * portfolioValue))", nil)
        }

        let riskAmount = limits.riskPerTradePct / 100.0 * portfolioValue
        let referenceStop = stopPrice ?? entryPrice * 0.95
        let priceRisk = abs(entryPrice - referenceStop)
        guard priceRisk > 0 else {
            return (false, "Stop price must differ from entry price", nil)
        }
        let quantityToRisk = riskAmount / priceRisk
        let positionSize = min(abs(quantity), quantityToRisk) * (side == .buy ? 1 : -1)
        _ = symbol
        return (true, nil, positionSize)
    }

    public func recordTrade(_ trade: Trade) {
        dailyPnL += trade.netCost
        tradeHistory.append(trade)
    }

    public func getExposure(symbol: String) -> Double {
        openPositions[symbol]?.pnlPercentage ?? 0.0
    }

    public func maxPositionValue(portfolioValue: Double = 100_000) -> Double {
        limits.maxPositionSizePct / 100.0 * portfolioValue
    }

    public func resetDailyPnL() {
        dailyPnL = 0
        dailyPnLResetDate = Date()
    }
}
