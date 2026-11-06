import Foundation

// MARK: - Tax Lot

public struct TaxLot: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let symbol: String
    public var quantity: Double
    public let costPerShare: Double
    public let acquiredAt: Date

    public init(
        id: UUID = UUID(),
        symbol: String,
        quantity: Double,
        costPerShare: Double,
        acquiredAt: Date
    ) {
        self.id = id
        self.symbol = symbol.uppercased()
        self.quantity = quantity
        self.costPerShare = costPerShare
        self.acquiredAt = acquiredAt
    }

    public var costBasis: Double { quantity * costPerShare }
}

// MARK: - Lot Selection

public enum LotSelectionMethod: String, Codable, Sendable, CaseIterable {
    case fifo
    case lifo
    case highestCost
    case lowestCost
}

// MARK: - Realized Sale

public struct RealizedLot: Codable, Sendable, Equatable {
    public let lotID: UUID
    public let quantity: Double
    public let costPerShare: Double
    public let proceedsPerShare: Double
    public let costBasis: Double
    public let proceeds: Double
    public let gain: Double
    public let acquiredAt: Date
    public let soldAt: Date
    public let holdingDays: Int

    public var isLongTerm: Bool { holdingDays > 365 }
}

public struct RealizedSale: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let symbol: String
    public let quantity: Double
    public let averageSalePrice: Double
    public let costBasis: Double
    public let proceeds: Double
    public let fees: Double
    public let gain: Double
    public let soldAt: Date
    public let method: LotSelectionMethod
    public let lots: [RealizedLot]

    public init(
        id: UUID = UUID(),
        symbol: String,
        quantity: Double,
        averageSalePrice: Double,
        costBasis: Double,
        proceeds: Double,
        fees: Double,
        gain: Double,
        soldAt: Date,
        method: LotSelectionMethod,
        lots: [RealizedLot]
    ) {
        self.id = id
        self.symbol = symbol
        self.quantity = quantity
        self.averageSalePrice = averageSalePrice
        self.costBasis = costBasis
        self.proceeds = proceeds
        self.fees = fees
        self.gain = gain
        self.soldAt = soldAt
        self.method = method
        self.lots = lots
    }
}

// MARK: - Position Summary

public struct TaxLotPosition: Sendable, Equatable {
    public let symbol: String
    public let quantity: Double
    public let averageCost: Double
    public let costBasis: Double
    public let lotCount: Int

    public init(symbol: String, quantity: Double, averageCost: Double, costBasis: Double, lotCount: Int) {
        self.symbol = symbol
        self.quantity = quantity
        self.averageCost = averageCost
        self.costBasis = costBasis
        self.lotCount = lotCount
    }
}

// MARK: - Errors

public enum TaxLotError: Error, LocalizedError, Sendable, Equatable {
    case invalidQuantity(Double)
    case invalidPrice(Double)
    case invalidFees(Double)
    case insufficientQuantity(symbol: String, requested: Double, available: Double)

    public var errorDescription: String? {
        switch self {
        case .invalidQuantity(let quantity):
            return "Quantity must be positive (received \(quantity))"
        case .invalidPrice(let price):
            return "Price must be non-negative (received \(price))"
        case .invalidFees(let fees):
            return "Fees must be non-negative (received \(fees))"
        case .insufficientQuantity(let symbol, let requested, let available):
            return "Cannot sell \(requested) \(symbol); only \(available) available"
        }
    }
}

// MARK: - Ledger

/// Cost-basis accounting with FIFO, LIFO, highest-cost, and lowest-cost lot
/// selection. Useful for tax reporting and realized P&L.
public struct TaxLotLedger: Sendable {
    private var lotsBySymbol: [String: [TaxLot]] = [:]
    public private(set) var realizedSales: [RealizedSale] = []

    public init(initialLots: [TaxLot] = []) {
        for lot in initialLots {
            lotsBySymbol[lot.symbol, default: []].append(lot)
        }
        sortLots()
    }

    // MARK: Mutations

    @discardableResult
    public mutating func buy(
        symbol: String,
        quantity: Double,
        price: Double,
        date: Date = Date()
    ) throws -> TaxLot {
        try validate(quantity: quantity, price: price)
        let lot = TaxLot(
            symbol: symbol,
            quantity: quantity,
            costPerShare: price,
            acquiredAt: date
        )
        lotsBySymbol[lot.symbol, default: []].append(lot)
        sortLots()
        return lot
    }

    @discardableResult
    public mutating func sell(
        symbol: String,
        quantity: Double,
        price: Double,
        fees: Double = 0,
        date: Date = Date(),
        method: LotSelectionMethod = .fifo
    ) throws -> RealizedSale {
        try validate(quantity: quantity, price: price)
        guard fees.isFinite, fees >= 0 else { throw TaxLotError.invalidFees(fees) }
        let key = symbol.uppercased()
        guard var symbolLots = lotsBySymbol[key], !symbolLots.isEmpty else {
            throw TaxLotError.insufficientQuantity(symbol: key, requested: quantity, available: 0)
        }

        let available = symbolLots.reduce(0) { $0 + $1.quantity }
        guard available + 1e-9 >= quantity else {
            throw TaxLotError.insufficientQuantity(symbol: key, requested: quantity, available: available)
        }

        symbolLots.sort { lhs, rhs in
            switch method {
            case .fifo:
                return lhs.acquiredAt == rhs.acquiredAt
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : lhs.acquiredAt < rhs.acquiredAt
            case .lifo:
                return lhs.acquiredAt == rhs.acquiredAt
                    ? lhs.id.uuidString > rhs.id.uuidString
                    : lhs.acquiredAt > rhs.acquiredAt
            case .highestCost:
                return lhs.costPerShare == rhs.costPerShare
                    ? lhs.acquiredAt < rhs.acquiredAt
                    : lhs.costPerShare > rhs.costPerShare
            case .lowestCost:
                return lhs.costPerShare == rhs.costPerShare
                    ? lhs.acquiredAt < rhs.acquiredAt
                    : lhs.costPerShare < rhs.costPerShare
            }
        }

        var remaining = quantity
        var matchedLots: [RealizedLot] = []
        var totalCost = 0.0
        var totalProceeds = 0.0
        var totalGain = 0.0

        for index in symbolLots.indices {
            guard remaining > 1e-12 else { break }
            let lot = symbolLots[index]
            guard lot.quantity > 0 else { continue }
            let consumed = min(lot.quantity, remaining)
            let feeShare = quantity > 0 ? fees * consumed / quantity : 0
            let cost = consumed * lot.costPerShare
            let proceeds = consumed * price - feeShare
            let gain = proceeds - cost
            let holdingDays = max(0, Int(date.timeIntervalSince(lot.acquiredAt) / 86_400))

            matchedLots.append(RealizedLot(
                lotID: lot.id,
                quantity: consumed,
                costPerShare: lot.costPerShare,
                proceedsPerShare: price,
                costBasis: cost,
                proceeds: proceeds,
                gain: gain,
                acquiredAt: lot.acquiredAt,
                soldAt: date,
                holdingDays: holdingDays
            ))

            symbolLots[index].quantity -= consumed
            remaining -= consumed
            totalCost += cost
            totalProceeds += proceeds
            totalGain += gain
        }

        symbolLots.removeAll { $0.quantity <= 1e-12 }
        lotsBySymbol[key] = symbolLots.isEmpty ? nil : symbolLots

        let sale = RealizedSale(
            symbol: key,
            quantity: quantity,
            averageSalePrice: quantity > 0 ? (totalProceeds + fees) / quantity : price,
            costBasis: totalCost,
            proceeds: totalProceeds,
            fees: fees,
            gain: totalGain,
            soldAt: date,
            method: method,
            lots: matchedLots
        )
        realizedSales.append(sale)
        return sale
    }

    // MARK: Queries

    public func position(symbol: String) -> TaxLotPosition? {
        let key = symbol.uppercased()
        let symbolLots = lotsBySymbol[key] ?? []
        let quantity = symbolLots.reduce(0) { $0 + $1.quantity }
        guard quantity > 0 else { return nil }
        let costBasis = symbolLots.reduce(0) { $0 + $1.costBasis }
        return TaxLotPosition(
            symbol: key,
            quantity: quantity,
            averageCost: costBasis / quantity,
            costBasis: costBasis,
            lotCount: symbolLots.count
        )
    }

    public var openLots: [TaxLot] {
        lotsBySymbol.values.flatMap { $0 }.sorted {
            $0.symbol == $1.symbol
                ? $0.acquiredAt < $1.acquiredAt
                : $0.symbol < $1.symbol
        }
    }

    public var positions: [TaxLotPosition] {
        lotsBySymbol.keys.compactMap { position(symbol: $0) }
            .sorted { $0.symbol < $1.symbol }
    }

    public func realizedGain(symbol: String? = nil) -> Double {
        let sales = symbol.map { target in
            realizedSales.filter { $0.symbol == target.uppercased() }
        } ?? realizedSales
        return sales.reduce(0) { $0 + $1.gain }
    }

    public func unrealizedGain(prices: [String: Double]) -> Double {
        var gain = 0.0
        for (symbol, symbolLots) in lotsBySymbol {
            guard let price = prices[symbol.uppercased()] ?? prices[symbol] else { continue }
            for lot in symbolLots {
                gain += (price - lot.costPerShare) * lot.quantity
            }
        }
        return gain
    }

    public func totalCostBasis() -> Double {
        lotsBySymbol.values.flatMap { $0 }.reduce(0) { $0 + $1.costBasis }
    }

    // MARK: Helpers

    private mutating func sortLots() {
        for key in lotsBySymbol.keys {
            lotsBySymbol[key]?.sort { $0.acquiredAt < $1.acquiredAt }
        }
    }

    private func validate(quantity: Double, price: Double) throws {
        guard quantity.isFinite, quantity > 0 else { throw TaxLotError.invalidQuantity(quantity) }
        guard price.isFinite, price >= 0 else { throw TaxLotError.invalidPrice(price) }
    }
}
