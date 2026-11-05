import Foundation

// MARK: - Strategy Protocol

/// A strategy maps a candle series to a target exposure per bar.
///
/// Exposure is a fraction of account equity: `1.0` = fully long, `0.0` = flat,
/// `-1.0` = fully short. The backtester executes the exposure from bar `i` at
/// the open of bar `i + 1`, which prevents look-ahead bias.
public protocol TradingStrategy: Sendable {
    var name: String { get }
    func generateExposures(candles: [Candle]) -> [Double]
}

// MARK: - Configuration

public struct BacktestConfig: Sendable, Equatable {
    public var initialCash: Double
    /// Commission in basis points (5 = 0.05%).
    public var commissionBps: Double
    /// Slippage in basis points applied against the trade direction.
    public var slippageBps: Double
    public var allowShort: Bool
    public var maxGrossExposure: Double
    public var periodsPerYear: Double
    public var riskFreeRate: Double
    public var closeOpenPositions: Bool
    /// Ignore rebalances smaller than this notional value.
    public var minimumTradeNotional: Double

    public init(
        initialCash: Double = 100_000,
        commissionBps: Double = 5,
        slippageBps: Double = 2,
        allowShort: Bool = false,
        maxGrossExposure: Double = 1,
        periodsPerYear: Double = 252,
        riskFreeRate: Double = 0,
        closeOpenPositions: Bool = true,
        minimumTradeNotional: Double = 0.01
    ) {
        self.initialCash = max(0, initialCash)
        self.commissionBps = max(0, commissionBps)
        self.slippageBps = max(0, slippageBps)
        self.allowShort = allowShort
        self.maxGrossExposure = max(0, maxGrossExposure)
        self.periodsPerYear = max(1, periodsPerYear)
        self.riskFreeRate = riskFreeRate
        self.closeOpenPositions = closeOpenPositions
        self.minimumTradeNotional = max(0, minimumTradeNotional)
    }
}

// MARK: - Result Types

public struct EquityPoint: Codable, Sendable, Identifiable, Equatable {
    public var id: Date { date }
    public let date: Date
    public let equity: Double
    public let cash: Double
    public let positionValue: Double
    public let exposure: Double

    public init(
        date: Date,
        equity: Double,
        cash: Double,
        positionValue: Double,
        exposure: Double
    ) {
        self.date = date
        self.equity = equity
        self.cash = cash
        self.positionValue = positionValue
        self.exposure = exposure
    }
}

public struct TradeFill: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let symbol: String
    public let side: TradeSide
    public let quantity: Double
    public let price: Double
    public let notional: Double
    public let commission: Double
    public let slippageCost: Double
    public let targetExposure: Double
    public let cashAfter: Double

    public init(
        id: UUID = UUID(),
        date: Date,
        symbol: String,
        side: TradeSide,
        quantity: Double,
        price: Double,
        notional: Double,
        commission: Double,
        slippageCost: Double,
        targetExposure: Double,
        cashAfter: Double
    ) {
        self.id = id
        self.date = date
        self.symbol = symbol
        self.side = side
        self.quantity = quantity
        self.price = price
        self.notional = notional
        self.commission = commission
        self.slippageCost = slippageCost
        self.targetExposure = targetExposure
        self.cashAfter = cashAfter
    }
}

public struct BacktestResult: Sendable {
    public let strategyName: String
    public let symbol: String
    public let config: BacktestConfig
    public let equityCurve: [EquityPoint]
    public let fills: [TradeFill]
    public let report: PerformanceReport?
    public let finalEquity: Double
    public let totalCommission: Double
    public let totalTurnover: Double

    public init(
        strategyName: String,
        symbol: String,
        config: BacktestConfig,
        equityCurve: [EquityPoint],
        fills: [TradeFill],
        report: PerformanceReport?,
        finalEquity: Double,
        totalCommission: Double,
        totalTurnover: Double
    ) {
        self.strategyName = strategyName
        self.symbol = symbol
        self.config = config
        self.equityCurve = equityCurve
        self.fills = fills
        self.report = report
        self.finalEquity = finalEquity
        self.totalCommission = totalCommission
        self.totalTurnover = totalTurnover
    }

    public var totalReturn: Double {
        guard let first = equityCurve.first, first.equity > 0 else { return 0 }
        return finalEquity / first.equity - 1
    }

    public var numberOfTrades: Int { fills.count }
}

// MARK: - Engine

/// Event-driven, next-bar-open backtester with commission and slippage.
public struct BacktestEngine {

    public init() {}

    /// Runs a strategy over a candle series.
    ///
    /// Returns `nil` for invalid input (fewer than two bars, non-positive
    /// prices, or non-positive initial cash).
    public func run(
        strategy: any TradingStrategy,
        candles: [Candle],
        symbol: String = "TEST",
        config: BacktestConfig = BacktestConfig()
    ) -> BacktestResult? {
        guard candles.count >= 2,
              config.initialCash > 0,
              candles.allSatisfy({
                  $0.open.isFinite && $0.open > 0
                      && $0.close.isFinite && $0.close > 0
                      && $0.high.isFinite && $0.low.isFinite
              })
        else { return nil }

        var exposures = strategy.generateExposures(candles: candles)
        if exposures.count > candles.count {
            exposures = Array(exposures.prefix(candles.count))
        } else if exposures.count < candles.count {
            let lastExposure = exposures.last ?? 0
            exposures.append(contentsOf: Array(
                repeating: lastExposure,
                count: candles.count - exposures.count
            ))
        }

        let commissionRate = config.commissionBps / 10_000.0
        let slippageRate = config.slippageBps / 10_000.0

        var cash = config.initialCash
        var shares = 0.0
        var fills: [TradeFill] = []
        var equityCurve: [EquityPoint] = [
            EquityPoint(
                date: candles[0].date,
                equity: config.initialCash,
                cash: config.initialCash,
                positionValue: 0,
                exposure: 0
            ),
        ]
        var totalCommission = 0.0
        var totalTurnover = 0.0

        for index in 0..<(candles.count - 1) {
            let bar = candles[index + 1]
            let executionPrice = bar.open
            guard executionPrice > 0 else { continue }

            var target = exposures[index]
            if !target.isFinite { target = 0 }
            if !config.allowShort { target = max(0, target) }
            target = min(max(target, -config.maxGrossExposure), config.maxGrossExposure)

            let equityAtOpen = cash + shares * executionPrice
            guard equityAtOpen > 0 else { continue }
            let targetShares = target * equityAtOpen / executionPrice
            let delta = targetShares - shares
            let notionalAtOpen = abs(delta) * executionPrice

            if notionalAtOpen >= config.minimumTradeNotional {
                let side: TradeSide = delta > 0 ? .long : .short
                let adjustedPrice = side == .long
                    ? executionPrice * (1 + slippageRate)
                    : executionPrice * (1 - slippageRate)
                let notional = abs(delta) * adjustedPrice
                let commission = notional * commissionRate
                let slippageCost = abs(adjustedPrice - executionPrice) * abs(delta)

                cash -= delta * adjustedPrice
                cash -= commission
                shares += delta
                totalCommission += commission
                totalTurnover += notional

                fills.append(TradeFill(
                    date: bar.date,
                    symbol: symbol,
                    side: side,
                    quantity: abs(delta),
                    price: adjustedPrice,
                    notional: notional,
                    commission: commission,
                    slippageCost: slippageCost,
                    targetExposure: target,
                    cashAfter: cash
                ))
            }

            let positionValue = shares * bar.close
            let equity = cash + positionValue
            equityCurve.append(EquityPoint(
                date: bar.date,
                equity: equity,
                cash: cash,
                positionValue: positionValue,
                exposure: equity > 0 ? positionValue / equity : 0
            ))
        }

        // Close any remaining position at the final close so the reported
        // equity is fully realized.
        if config.closeOpenPositions, abs(shares) > 1e-9, let last = candles.last {
            let side: TradeSide = shares > 0 ? .short : .long
            let adjustedPrice = shares > 0
                ? last.close * (1 - slippageRate)
                : last.close * (1 + slippageRate)
            let notional = abs(shares) * adjustedPrice
            let commission = notional * commissionRate
            let slippageCost = abs(adjustedPrice - last.close) * abs(shares)

            cash += shares * adjustedPrice
            cash -= commission
            totalCommission += commission
            totalTurnover += notional

            fills.append(TradeFill(
                date: last.date,
                symbol: symbol,
                side: side,
                quantity: abs(shares),
                price: adjustedPrice,
                notional: notional,
                commission: commission,
                slippageCost: slippageCost,
                targetExposure: 0,
                cashAfter: cash
            ))
            shares = 0

            if !equityCurve.isEmpty {
                equityCurve[equityCurve.count - 1] = EquityPoint(
                    date: last.date,
                    equity: cash,
                    cash: cash,
                    positionValue: 0,
                    exposure: 0
                )
            }
        }

        let finalEquity = cash + shares * (candles.last?.close ?? 0)
        let report = PerformanceAnalytics.analyze(
            equity: equityCurve.map(\.equity),
            riskFreeRate: config.riskFreeRate,
            periodsPerYear: config.periodsPerYear
        )

        return BacktestResult(
            strategyName: strategy.name,
            symbol: symbol,
            config: config,
            equityCurve: equityCurve,
            fills: fills,
            report: report,
            finalEquity: finalEquity,
            totalCommission: totalCommission,
            totalTurnover: totalTurnover
        )
    }
}
