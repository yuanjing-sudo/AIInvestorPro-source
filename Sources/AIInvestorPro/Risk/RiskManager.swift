// MARK: - Risk Management
import Foundation

public struct RiskLimits {
    public var maxPositionSize: Double      // Maximum position size in currency
    public var maxDailyLoss: Double         // Maximum daily loss in currency
    public var maxDrawdown: Double          // Maximum drawdown percentage
    public var maxLeverage: Double          // Maximum allowed leverage
    public var maxConcurrentTrades: Int     // Maximum open positions
    
    public init(
        maxPositionSize: Double = 100_000,
        maxDailyLoss: Double = 2_000,
        maxDrawdown: Double = 0.10,
        maxLeverage: Double = 5.0,
        maxConcurrentTrades: Int = 10
    ) {
        self.maxPositionSize = maxPositionSize
        self.maxDailyLoss = maxDailyLoss
        self.maxDrawdown = maxDrawdown
        self.maxLeverage = maxLeverage
        self.maxConcurrentTrades = maxConcurrentTrades
    }
}

public class RiskManager {
    private let limits: RiskLimits
    private var dailyPnL: Double = 0
    private var openTrades: [String: Double] = [:] // symbol -> position size
    private var tradeHistory: [Trade] = []
    
    public init(limits: RiskLimits = RiskLimits()) {
        self.limits = limits
    }
    
    public func canEnterTrade(
        symbol: String,
        quantity: Double,
        price: Double,
        side: RiskManager.OrderSide
    ) -> (allowed: Bool, reason: String?) {
        // Check position size
        let positionValue = quantity * price
        guard positionValue <= limits.maxPositionSize else {
            return (false, "Position size exceeds maximum \(limits.maxPositionSize.formatCurrency)")
        }
        
        // Check daily loss
        guard dailyPnL + positionValue >= -limits.maxDailyLoss else {
            return (false, "Would exceed daily loss limit of \(limits.maxDailyLoss.formatCurrency)")
        }
        
        // Check concurrent trades
        let activeCount = openTrades.filter { $0.value != 0 }.count
        guard activeCount < limits.maxConcurrentTrades else {
            return (false, "Maximum concurrent trades (\(limits.maxConcurrentTrades)) reached")
        }
        
        return (true, nil)
    }
    
    public func recordTrade(_ trade: Trade) {
        dailyPnL += trade.netCost
        openTrades[trade.order.symbol] = trade.filledQuantity
        tradeHistory.append(trade)
    }
    
    public func getExposure(symbol: String) -> Double {
        return openTrades[symbol] ?? 0
    }
}
