// MARK: - Trade Execution
import Foundation
import Combine

public enum ExecutionStatus: String, CaseIterable, Equatable, Sendable {
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

public enum OrderDuration: String, CaseIterable, Sendable {
    case day = "day"
    case gtc = "good_til_cancelled"
    case ioc = "immediate_or_cancel"
    case fok = "fill_or_kill"

    public var description: String {
        rawValue.replacingUnderscoresWithSpaces
    }
}

public enum OrderCondition: String, CaseIterable, Sendable {
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
public struct ExecutionResult: Identifiable, Sendable {
    public let id: String
    public let orderId: String
    public let status: ExecutionStatus
    public let filledQuantity: Double
    public let filledPrice: Double?
    public let averagePrice: Double?
    public let commission: Double
    public let timestamp: Date
    public let error: String?

    public var isComplete: Bool {
        [.filled, .cancelled, .rejected, .expired].contains(status)
    }

    public var isSuccessful: Bool {
        status == .filled
    }

    public init(
        id: String = UUID().uuidString,
        orderId: String,
        status: ExecutionStatus,
        filledQuantity: Double,
        filledPrice: Double?,
        averagePrice: Double?,
        commission: Double,
        timestamp: Date = Date(),
        error: String? = nil
    ) {
        self.id = id
        self.orderId = orderId
        self.status = status
        self.filledQuantity = filledQuantity
        self.filledPrice = filledPrice
        self.averagePrice = averagePrice
        self.commission = commission
        self.timestamp = timestamp
        self.error = error
    }
}

// MARK: - Execution Manager
@MainActor
public final class ExecutionManager: ObservableObject {
    @Published public var activeOrders: [Order] = []
    @Published public var executionHistory: [ExecutionResult] = []
    @Published public var statusMessage: String = "Ready"

    private var orderCounter: Int = 0

    public init() {}

    @discardableResult
    public func submit(_ order: Order) -> String {
        orderCounter += 1
        let orderId = "ORD-\(String(format: "%06d", orderCounter))"

        var pending = order
        pending.status = .pending
        activeOrders.append(pending)

        Task {
            await simulateExecution(orderId: orderId, order: pending)
        }
        return orderId
    }

    /// Deterministic paper-fill: valid marketable orders fill completely at
    /// the limit price (or the supplied price), while orders without any price
    /// reference are rejected. No randomness is used, so results are
    /// reproducible.
    private func simulateExecution(orderId: String, order: Order) async {
        try? await Task.sleep(nanoseconds: 200_000_000)

        guard order.quantity > 0,
              let fillPrice = order.price ?? order.stopPrice,
              fillPrice > 0 else {
            let rejection = ExecutionResult(
                orderId: orderId,
                status: .rejected,
                filledQuantity: 0,
                filledPrice: nil,
                averagePrice: nil,
                commission: 0,
                error: "Order rejected: missing price or quantity"
            )
            executionHistory.append(rejection)
            statusMessage = rejection.status.description
            return
        }

        let result = ExecutionResult(
            orderId: orderId,
            status: .filled,
            filledQuantity: order.quantity,
            filledPrice: fillPrice,
            averagePrice: fillPrice,
            commission: order.quantity * 0.001,
            error: nil
        )

        if let index = activeOrders.firstIndex(where: { $0.id == order.id }) {
            activeOrders[index].status = .filled
            activeOrders[index].filledQuantity = order.quantity
            activeOrders[index].filledPrice = fillPrice
            activeOrders[index].commission = result.commission
        }
        executionHistory.append(result)
        statusMessage = result.status.description
    }

    public func cancel(orderId: String) {
        guard let index = activeOrders.firstIndex(where: { $0.id == orderId }) else {
            statusMessage = "Order not found"
            return
        }
        activeOrders[index].status = .cancelled
        executionHistory.append(ExecutionResult(
            orderId: orderId,
            status: .cancelled,
            filledQuantity: 0,
            filledPrice: nil,
            averagePrice: nil,
            commission: 0
        ))
        statusMessage = "Order cancelled"
    }

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
            guard order.status == .filled,
                  let price = order.filledPrice ?? order.price,
                  price > 0 else { return nil }

            return RiskManager.Position(
                symbol: order.symbol,
                side: order.side,
                quantity: order.filledQuantity,
                entryPrice: price,
                currentPrice: price
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
