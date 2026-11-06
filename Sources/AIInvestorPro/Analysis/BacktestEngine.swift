// MARK: - Backtesting Engine
import Foundation

public enum OrderSide: String, CaseIterable, Sendable, Equatable {
    case buy
    case sell
}

public struct TradeRecord: Identifiable, Sendable {
    public let id: String
    public let entryDate: Date
    public let exitDate: Date?
    public let symbol: String
    public let entryPrice: Double
    public let exitPrice: Double?
    public let quantity: Double
    public let side: OrderSide
    public var pnl: Double?
    public var pnlPercentage: Double?
    public let signal: TradeSignal
    public let reason: String

    public var isClosed: Bool { exitDate != nil }
    public var isWinning: Bool { (pnl ?? 0) > 0 }

    public init(
        entryDate: Date,
        symbol: String,
        entryPrice: Double,
        quantity: Double,
        side: OrderSide,
        signal: TradeSignal,
        reason: String,
        exitPrice: Double? = nil,
        exitDate: Date? = nil,
        id: String = UUID().uuidString
    ) {
        self.id = id
        self.entryDate = entryDate
        self.symbol = symbol
        self.entryPrice = entryPrice
        self.quantity = quantity
        self.side = side
        self.signal = signal
        self.reason = reason
        self.exitPrice = exitPrice
        self.exitDate = exitPrice == nil ? nil : (exitDate ?? Date())

        if let exitPrice, entryPrice != 0 {
            let gross = (exitPrice - entryPrice) * quantity * (side == .buy ? 1 : -1)
            self.pnl = gross
            self.pnlPercentage = (exitPrice - entryPrice) / entryPrice * 100.0
        } else {
            self.pnl = nil
            self.pnlPercentage = nil
        }
    }
}

/// A deterministic, long-or-flat backtester. Signals are executed at the
/// supplied price, with commission and slippage applied against the trader.
public final class BacktestEngine {
    private let initialCapital: Double
    private var capital: Double
    private var position: Double = 0
    private var entryPrice: Double?
    private var positionEntryDate: Date?
    private var tradeHistory: [TradeRecord] = []
    private var equityCurve: [Double] = []
    private let commissionPct: Double
    private let slippagePct: Double

    public init(
        initialCapital: Double = 10000.0,
        commissionPct: Double = 0.001,
        slippagePct: Double = 0.0005
    ) {
        self.initialCapital = initialCapital
        self.capital = initialCapital
        self.commissionPct = commissionPct
        self.slippagePct = slippagePct
        self.equityCurve = [initialCapital]
    }

    /// Execute a signal. `.buy`, `.strongBuy` and `.enterLong` open or add to a
    /// long position; `.sell`, `.strongSell`, `.exit` and `.enterShort` reduce
    /// or close it. `.hold` only records the decision.
    public func executeSignal(
        _ signal: TradeSignal,
        _ symbol: String,
        _ price: Double,
        _ quantity: Double,
        _ date: Date,
        _ strategyName: String,
        _ reason: String
    ) {
        _ = strategyName
        guard price > 0, quantity > 0 else { return }

        switch signal {
        case .buy, .strongBuy, .enterLong:
            let fill = price * (1 + slippagePct)
            executeBuy(symbol, fill, quantity, date, reason)
        case .sell, .strongSell, .exit, .enterShort:
            let fill = price * (1 - slippagePct)
            executeSell(symbol, fill, quantity, date, reason)
        case .hold:
            tradeHistory.append(TradeRecord(
                entryDate: date,
                symbol: symbol,
                entryPrice: price,
                quantity: 0,
                side: .buy,
                signal: .hold,
                reason: reason
            ))
            equityCurve.append(capital + position * price)
        }
    }

    private func executeBuy(_ symbol: String, _ price: Double, _ quantity: Double, _ date: Date, _ reason: String) {
        let unitCost = price * (1 + commissionPct)
        let affordableQuantity = unitCost > 0 ? min(quantity, capital / unitCost) : 0
        guard affordableQuantity > 0.000_000_1 else { return }

        let totalCost = unitCost * affordableQuantity
        let previousQuantity = position
        let previousCost = (entryPrice ?? price) * previousQuantity
        capital -= totalCost
        position += affordableQuantity

        let newQuantity = position
        if newQuantity > 0 {
            entryPrice = (previousCost + price * affordableQuantity) / newQuantity
        } else {
            entryPrice = price
        }
        if positionEntryDate == nil {
            positionEntryDate = date
        }

        tradeHistory.append(TradeRecord(
            entryDate: date,
            symbol: symbol,
            entryPrice: price,
            quantity: affordableQuantity,
            side: .buy,
            signal: .buy,
            reason: reason
        ))
        equityCurve.append(capital + position * price)
    }

    private func executeSell(_ symbol: String, _ price: Double, _ quantity: Double, _ date: Date, _ reason: String) {
        guard position > 0 else { return }
        let sharesToSell = min(quantity, position)
        guard sharesToSell > 0 else { return }

        let proceeds = price * sharesToSell * (1 - commissionPct)
        capital += proceeds

        let basis = entryPrice ?? price
        let pnl = (price - basis) * sharesToSell - price * sharesToSell * commissionPct
        let pnlPercentage = basis > 0 ? (price - basis) / basis * 100.0 : 0

        position -= sharesToSell
        if position <= 0.000_000_1 {
            position = 0
            entryPrice = nil
            positionEntryDate = nil
        }

        tradeHistory.append(TradeRecord(
            entryDate: positionEntryDate ?? date,
            symbol: symbol,
            entryPrice: basis,
            quantity: sharesToSell,
            side: .sell,
            signal: .sell,
            reason: reason,
            exitPrice: price,
            exitDate: date
        ))
        if let last = tradeHistory.indices.last {
            tradeHistory[last].pnl = pnl
            tradeHistory[last].pnlPercentage = pnlPercentage
        }
        equityCurve.append(capital + position * price)
    }

    /// Net liquidation value if the current position is marked at `price`.
    public func equity(at price: Double) -> Double {
        capital + position * price
    }

    public func getMetrics() -> BacktestMetrics {
        let closedTrades = tradeHistory.filter { $0.isClosed }
        let winningTrades = closedTrades.filter { ($0.pnl ?? 0) > 0 }
        let losingTrades = closedTrades.filter { ($0.pnl ?? 0) <= 0 }

        let totalTrades = closedTrades.count
        let winRate = totalTrades > 0 ? Double(winningTrades.count) / Double(totalTrades) * 100.0 : 0
        let totalReturn = initialCapital > 0 ? (capital - initialCapital) / initialCapital * 100.0 : 0
        let totalPnl = capital - initialCapital

        let avgWin = winningTrades.isEmpty
            ? 0
            : winningTrades.compactMap(\.pnlPercentage).reduce(0, +) / Double(winningTrades.count)
        let avgLoss = losingTrades.isEmpty
            ? 0
            : losingTrades.compactMap(\.pnlPercentage).reduce(0, +) / Double(losingTrades.count)

        let grossWins = winningTrades.compactMap(\.pnl).reduce(0, +)
        let grossLosses = abs(losingTrades.compactMap(\.pnl).reduce(0, +))
        let profitFactor = grossLosses > 0 ? grossWins / grossLosses : (grossWins > 0 ? .infinity : 0)

        let peak = equityCurve.max() ?? initialCapital
        var runningPeak = equityCurve.first ?? initialCapital
        var maxDrawdown: Double = 0
        for value in equityCurve {
            runningPeak = max(runningPeak, value)
            let drawdown = runningPeak > 0 ? (runningPeak - value) / runningPeak * 100.0 : 0
            maxDrawdown = max(maxDrawdown, drawdown)
        }
        _ = peak

        let returns = zip(equityCurve.dropFirst(), equityCurve.dropLast()).map { $0.0 / $0.1 - 1 }
        let averageReturn = returns.mean
        let returnStd = returns.standardDeviation
        let sharpeRatio = returnStd > 0 ? averageReturn / returnStd * sqrt(252) : 0

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

    public func getTradeStatistics() -> TradeStatistics {
        let closedTrades = tradeHistory.filter { $0.isClosed }
        let total = closedTrades.count
        let wins = closedTrades.filter { ($0.pnlPercentage ?? 0) > 0 }
        let losses = closedTrades.filter { ($0.pnlPercentage ?? 0) <= 0 }

        let holdingPeriods = closedTrades.map { trade in
            guard let exitDate = trade.exitDate else { return 0 }
            return Calendar.current.dateComponents([.day], from: trade.entryDate, to: exitDate).day ?? 0
        }

        return TradeStatistics(
            totalTrades: total,
            winRate: total > 0 ? Double(wins.count) / Double(total) * 100.0 : 0,
            avgHoldingPeriod: total > 0 ? Double(holdingPeriods.reduce(0, +)) / Double(total) : 0,
            largestWin: closedTrades.compactMap(\.pnlPercentage).max() ?? 0,
            largestLoss: closedTrades.compactMap(\.pnlPercentage).min() ?? 0,
            avgWinPct: wins.isEmpty ? 0 : wins.compactMap(\.pnlPercentage).reduce(0, +) / Double(wins.count),
            avgLossPct: losses.isEmpty ? 0 : losses.compactMap(\.pnlPercentage).reduce(0, +) / Double(losses.count)
        )
    }
}

// MARK: - Performance Metrics
public struct BacktestMetrics: Sendable {
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
        "  Win Rate: \(String(format: "%.2f", winRate))%\n" +
        "  Total Return: \(String(format: "%.2f", totalReturn))%\n" +
        "  Total PnL: $\(String(format: "%.2f", totalPnl))\n" +
        "  Profit Factor: \(String(format: "%.2f", profitFactor))\n" +
        "  Sharpe Ratio: \(String(format: "%.2f", sharpeRatio))\n" +
        "  Max Drawdown: \(String(format: "%.2f", maxDrawdown))%"
    }
}

public struct TradeStatistics: Sendable {
    public let totalTrades: Int
    public let winRate: Double
    public let avgHoldingPeriod: Double
    public let largestWin: Double
    public let largestLoss: Double
    public let avgWinPct: Double
    public let avgLossPct: Double

    var summary: String {
        "Trades: \(totalTrades), Win: \(String(format: "%.1f", winRate))%, " +
        "Largest Win: \(String(format: "%.2f", largestWin))%, " +
        "Largest Loss: \(String(format: "%.2f", largestLoss))%"
    }
}
