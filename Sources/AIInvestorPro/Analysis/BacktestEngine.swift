// MARK: - Backtesting Engine
import Foundation

public enum OrderSide: String, CaseIterable {
    case buy
    case sell
}

public enum TradeSignal: String, CaseIterable {
    case buy = "buy"
    case sell = "sell"
    case hold = "hold"
}

public struct TradeRecord {
    public let entryDate: Date
    public let exitDate: Date?
    public let symbol: String
    public let entryPrice: Double
    public let exitPrice: Double?
    public let quantity: Double
    public let side: OrderSide
    public let pnl: Double?
    public let pnlPercentage: Double?
    public let signal: TradeSignal
    public let reason: String
    
    public var isClosed: Bool { exitDate != nil }
    public var isWinning: Double? { pnl.map { $0 > 0 } }
    
    public init(
        entryDate: Date,
        symbol: String,
        entryPrice: Double,
        quantity: Double,
        side: OrderSide,
        signal: TradeSignal,
        reason: String,
        exitPrice: Double? = nil
    ) {
        self.entryDate = entryDate
        self.symbol = symbol
        self.entryPrice = entryPrice
        self.quantity = quantity
        self.side = side
        self.signal = signal
        self.reason = reason
        self.exitPrice = exitPrice
        self.exitDate = exitPrice != nil ? Date() : nil
        
        if let exitPrice = exitPrice {
            self.pnl = (exitPrice - entryPrice) * quantity * (side == .buy ? 1 : -1)
            self.pnlPercentage = (exitPrice - entryPrice) / entryPrice * 100.0
        } else {
            self.pnl = nil
            self.pnlPercentage = nil
        }
    }
}

public class BacktestEngine {
    private var initialCapital: Double
    private var capital: Double
    private var position: Double? // Current position size (positive = long, negative = short)
    private var entryPrice: Double?
    private var tradeHistory: [TradeRecord] = []
    private var equityCurve: [Double] = []
    private let commissionPct: Double
    private let slippagePct: Double
    
    public init(initialCapital: Double = 10000.0, commissionPct: Double = 0.001, slippagePct: Double = 0.0005) {
        self.initialCapital = initialCapital
        self.capital = initialCapital
        self.commissionPct = commissionPct
        self.slippagePct = slippagePct
        self.equityCurve.append(initialCapital)
    }
    
    // Execute a signal
    public func executeSignal(
        _ signal: TradeSignal,
        _ symbol: String,
        _ price: Double,
        _ quantity: Double,
        _ date: Date,
        _ strategyName: String,
        _ reason: String
    ) {
        let adjustedPrice = price * (1 + Double.random(in: -slippagePct...slippagePct))
        
        switch signal {
        case .buy:
            executeBuy(symbol, adjustedPrice, quantity, date, strategyName, reason)
        case .sell:
            executeSell(symbol, adjustedPrice, quantity, date, strategyName, reason)
        case .hold:
            // No action, record reason
            let record = TradeRecord(
                entryDate: date,
                symbol: symbol,
                entryPrice: 0,
                quantity: 0,
                side: .buy,
                signal: .hold,
                reason: reason
            )
            tradeHistory.append(record)
        }
    }
    
    private func executeBuy(_ symbol: String, _ price: Double, _ quantity: Double, _ date: Date, _ strategyName: String, _ reason: String) {
        // Check if we have enough capital
        let totalCost = price * quantity * (1 + commissionPct)
        
        guard totalCost <= capital else {
            // Not enough capital - reduce quantity
            let affordableQuantity = capital / (price * (1 + commissionPct))
            executePartialBuy(symbol, price, affordableQuantity, date, strategyName, reason)
            return
        }
        
        // Full buy
        capital -= totalCost
        position = (position ?? 0) + quantity
        entryPrice = position! > 0 ? (entryPrice ?? 0 + price) / 2 : price
        
        let record = TradeRecord(
            entryDate: date,
            symbol: symbol,
            entryPrice: price,
            quantity: quantity,
            side: .buy,
            signal: .buy,
            reason: reason
        )
        tradeHistory.append(record)
        equityCurve.append(capital + (position ?? 0) * price)
    }
    
    private func executePartialBuy(_ symbol: String, _ price: Double, _ quantity: Double, _ date: Date, _ strategyName: String, _ reason: String) {
        let totalCost = price * quantity * (1 + commissionPct)
        capital -= totalCost
        position = (position ?? 0) + quantity
        entryPrice = price
        
        let record = TradeRecord(
            entryDate: date,
            symbol: symbol,
            entryPrice: price,
            quantity: quantity,
            side: .buy,
            signal: .buy,
            reason: reason
        )
        tradeHistory.append(record)
        equityCurve.append(capital + (position ?? 0) * price)
    }
    
    private func executeSell(_ symbol: String, _ price: Double, _ quantity: Double, _ date: Date, _ strategyName: String, _ reason: String) {
        let sharesToSell = min(quantity, position ?? 0)
        let adjustedPrice = price * (1 - Double.random(in: 0...slippagePct)) // Assume sell at slightly lower
        
        if sharesToSell >= position ?? 0 {
            // Close entire position
            let proceeds = adjustedPrice * sharesToSell * (1 - commissionPct)
            capital += proceeds
            
            let pnl = capital - initialCapital + (position ?? 0) * price // Simplified
            let pnlPct = (capital - initialCapital) / initialCapital * 100.0
            
            let record = TradeRecord(
                entryDate: date,
                symbol: symbol,
                entryPrice: entryPrice ?? 0,
                quantity: sharesToSell,
                side: .sell,
                signal: .sell,
                reason: reason,
                exitPrice: adjustedPrice
            )
            record.pnl = pnl - initialCapital // Net PnL
            record.pnlPercentage = pnlPct
            
            tradeHistory.append(record)
            position = 0
            entryPrice = nil
        } else {
            // Partial sell
            let proceeds = adjustedPrice * sharesToSell * (1 - commissionPct)
            capital += proceeds
            
            let pnl = (adjustedPrice - (entryPrice ?? price)) * sharesToSell
            let pnlPct = pnl / (entryPrice ?? price) * 100.0
            
            position!.remove(sharesToSell) // Simplified
            
            let record = TradeRecord(
                entryDate: date,
                symbol: symbol,
                entryPrice: entryPrice ?? price,
                quantity: sharesToSell,
                side: .sell,
                signal: .sell,
                reason: reason,
                exitPrice: adjustedPrice
            )
            record.pnl = pnl
            record.pnlPercentage = pnlPct
            
            tradeHistory.append(record)
        }
        
        equityCurve.append(capital + (position ?? 0) * price)
    }
    
    // Get performance metrics
    public func getMetrics() -> BacktestMetrics {
        let closedTrades = tradeHistory.filter { $0.isClosed }
        let winningTrades = closedTrades.filter { $0.pnlPercentage ?? 0 > 0 }
        let losingTrades = closedTrades.filter { $0.pnlPercentage ?? 0 <= 0 }
        
        let totalTrades = closedTrades.count
        let winRate = totalTrades > 0 ? Double(winningTrades.count) / Double(totalTrades) * 100.0 : 0
        let totalReturn = (capital - initialCapital) / initialCapital * 100.0
        let totalPnl = capital - initialCapital
        
        // Average win/loss
        let avgWin = winningTrades.isEmpty ? 0 : winningTrades.map { $0.pnlPercentage! }.reduce(0, +) / Double(winningTrades.count)
        let avgLoss = losingTrades.isEmpty ? 0 : losingTrades.map { $0.pnlPercentage! }.reduce(0, +) / Double(losingTrades.count)
        
        // Profit factor
        let grossWins = winningTrades.map { $0.pnl ?? 0 }.reduce(0, +)
        let grossLosses = abs(losingTrades.map { $0.pnl ?? 0 }.reduce(0, +))
        let profitFactor = grossLosses > 0 ? grossWins / grossLosses : grossWins > 0 ? Double.infinity : 0
        
        // Max drawdown
        let peak = equityCurve[0]
        var maxDrawdown: Double = 0
        for value in equityCurve {
            if value > peak {
                peak = value
            }
            let drawdown = (peak - value) / peak * 100.0
            maxDrawdown = max(maxDrawdown, drawdown)
        }
        
        // Sharpe ratio (assuming risk-free rate of 0)
        let returns = zip(equityCurve.dropFirst(), equityCurve.dropLast()).map { $1 / $0 - 1 }
        let avgReturn = returns.reduce(0, +) / Double(returns.count)
        let returnStd = returns.standardDeviation
        let sharpeRatio = returnStd > 0 ? avgReturn / returnStd * sqrt(252) : 0
        
        return BacktestMetrics(
            totalTrades: totalTrades,
            winningTrades: winningTrades.count,
            losingTrades: losingTrades.count,
            winRate: winRate,
            totalReturn: totalReturn,
            totalPnl: totalPnl,
            avgWin: avgWin,
            avgLoss: avgLoss,
            profitFactor: profitFactor,
            maxDrawdown: maxDrawdown,
            sharpeRatio: sharpeRatio,
            finalCapital: capital,
            initialCapital: initialCapital
        )
    }
    
    // Get trade statistics
    public func getTradeStatistics() -> TradeStatistics {
        let closedTrades = tradeHistory.filter { $0.isClosed }
        let total = closedTrades.count
        
        return TradeStatistics(
            totalTrades: total,
            winRate: total > 0 ? Double(closedTrades.filter { $0.pnlPercentage ?? 0 > 0 }.count) / Double(total) * 100.0 : 0,
            avgHoldingPeriod: closedTrades.isEmpty ? 0 : Double(closedTrades.map { Calendar.current.dateComponents(.day, from: $0.entryDate, to: $0.exitDate!).day ?? 0 }.reduce(0, +)) / Double(total),
            largestWin: closedTrades.map { $0.pnlPercentage ?? 0 }.max() ?? 0,
            largestLoss: closedTrades.map { $0.pnlPercentage ?? 0 }.min() ?? 0,
            avgWinPct: closedTrades.filter { $0.pnlPercentage ?? 0 > 0 }.isEmpty ? 0 : closedTrades.filter { $0.pnlPercentage ?? 0 > 0 }.map { $0.pnlPercentage! }.reduce(0, +) / Double(closedTrades.filter { $0.pnlPercentage ?? 0 > 0 }.count),
            avgLossPct: closedTrades.filter { $0.pnlPercentage ?? 0 <= 0 }.isEmpty ? 0 : closedTrades.filter { $0.pnlPercentage ?? 0 <= 0 }.map { $0.pnlPercentage! }.reduce(0, +) / Double(closedTrades.filter { $0.pnlPercentage ?? 0 <= 0 }.count)
        )
    }
}

// MARK: - Performance Metrics
public struct BacktestMetrics {
    public let totalTrades: Int
    public let winningTrades: Int
    public let losingTrades: Int
    public let winRate: Double
    public let totalReturn: Double
    public let totalPnl: Double
    public let avgWin: Double
    public let avgLoss: Double
    public let profitFactor: Double
    public let maxDrawdown: Double
    public let sharpeRatio: Double
    public let finalCapital: Double
    public let initialCapital: Double
    
    var description: String {
        "Backtest Results:\n" +
        "  Total Trades: \(totalTrades)\n" +
        "  Win Rate: \(String(format: "%.2f%", winRate))%\n" +
        "  Total Return: \(String(format: "%.2f%", totalReturn))%\n" +
        "  Total PnL: $\(String(format: "%.2f", totalPnl))\n" +
        "  Profit Factor: \(String(format: "%.2f", profitFactor))\n" +
        "  Sharpe Ratio: \(String(format: "%.2f", sharpeRatio))\n" +
        "  Max Drawdown: \(String(format: "%.2f%", maxDrawdown))%"
    }
}

public struct TradeStatistics {
    public let totalTrades: Int
    public let winRate: Double
    public let avgHoldingPeriod: Double
    public let largestWin: Double
    public let largestLoss: Double
    public let avgWinPct: Double
    public let avgLossPct: Double
    
    var summary: String {
        "Trades: \(totalTrades), Win: \(String(format: "%.1f%", winRate))%, " +
        "Largest Win: \(String(format: "%.2f%", largestWin))%, " +
        "Largest Loss: \(String(format: "%.2f%", largestLoss))%"
    }
}
