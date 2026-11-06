import Foundation

// MARK: - Persisted Models

public struct StoredHolding: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let symbol: String
    public var quantity: Double
    public var averageCost: Double

    public init(
        id: UUID = UUID(),
        symbol: String,
        quantity: Double,
        averageCost: Double
    ) {
        self.id = id
        self.symbol = symbol.uppercased()
        self.quantity = quantity
        self.averageCost = averageCost
    }

    public var costBasis: Double { quantity * averageCost }
}

public struct StoredTransaction: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let symbol: String
    public let side: TradeSide
    public let quantity: Double
    public let price: Double
    public let fees: Double
    public let date: Date
    public let note: String?

    public init(
        id: UUID = UUID(),
        symbol: String,
        side: TradeSide,
        quantity: Double,
        price: Double,
        fees: Double = 0,
        date: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.symbol = symbol.uppercased()
        self.side = side
        self.quantity = quantity
        self.price = price
        self.fees = fees
        self.date = date
        self.note = note
    }
}

public struct StoredPortfolio: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var cash: Double
    public var holdings: [StoredHolding]
    public var transactions: [StoredTransaction]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "My Portfolio",
        cash: Double = 0,
        holdings: [StoredHolding] = [],
        transactions: [StoredTransaction] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.cash = cash
        self.holdings = holdings
        self.transactions = transactions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var totalHoldingsCost: Double {
        holdings.reduce(0) { $0 + $1.costBasis }
    }

    public var totalValueAtCost: Double {
        cash + totalHoldingsCost
    }

    public func holding(symbol: String) -> StoredHolding? {
        holdings.first { $0.symbol == symbol.uppercased() }
    }

    /// Applies a transaction, updating cash, quantity, and weighted-average
    /// cost. Throws if a sale exceeds the current position.
    public mutating func apply(_ transaction: StoredTransaction) throws {
        guard transaction.quantity.isFinite, transaction.quantity > 0,
              transaction.price.isFinite, transaction.price >= 0,
              transaction.fees.isFinite, transaction.fees >= 0
        else {
            throw PortfolioStoreError.invalidTransaction
        }

        switch transaction.side {
        case .long:
            cash -= transaction.quantity * transaction.price + transaction.fees
            if let index = holdings.firstIndex(where: { $0.symbol == transaction.symbol }) {
                let existing = holdings[index]
                let newQuantity = existing.quantity + transaction.quantity
                let newCostBasis = existing.costBasis + transaction.quantity * transaction.price
                holdings[index].quantity = newQuantity
                holdings[index].averageCost = newQuantity > 0 ? newCostBasis / newQuantity : 0
            } else {
                holdings.append(StoredHolding(
                    symbol: transaction.symbol,
                    quantity: transaction.quantity,
                    averageCost: transaction.price
                ))
            }

        case .short:
            guard let index = holdings.firstIndex(where: { $0.symbol == transaction.symbol }) else {
                throw PortfolioStoreError.insufficientQuantity(
                    symbol: transaction.symbol,
                    requested: transaction.quantity,
                    available: 0
                )
            }
            let existing = holdings[index]
            guard existing.quantity + 1e-9 >= transaction.quantity else {
                throw PortfolioStoreError.insufficientQuantity(
                    symbol: transaction.symbol,
                    requested: transaction.quantity,
                    available: existing.quantity
                )
            }
            cash += transaction.quantity * transaction.price - transaction.fees
            let newQuantity = existing.quantity - transaction.quantity
            if newQuantity <= 1e-9 {
                holdings.remove(at: index)
            } else {
                holdings[index].quantity = newQuantity
            }
        }

        transactions.append(transaction)
        updatedAt = Date()
    }
}

// MARK: - Errors

public enum PortfolioStoreError: Error, LocalizedError, Sendable, Equatable {
    case invalidTransaction
    case insufficientQuantity(symbol: String, requested: Double, available: Double)
    case encoding(String)
    case decoding(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTransaction:
            return "Transaction has invalid quantity, price, or fees"
        case .insufficientQuantity(let symbol, let requested, let available):
            return "Cannot sell \(requested) \(symbol); only \(available) available"
        case .encoding(let message):
            return "Could not encode portfolio: \(message)"
        case .decoding(let message):
            return "Could not decode portfolio: \(message)"
        case .io(let message):
            return "Portfolio storage error: \(message)"
        }
    }
}

// MARK: - Store

/// Actor-isolated, atomic JSON persistence for a portfolio. Also keeps a
/// single `.bak` copy of the previous revision.
public actor PortfolioStore {
    public let fileURL: URL
    private let keepBackup: Bool

    public init(fileURL: URL, keepBackup: Bool = true) {
        self.fileURL = fileURL
        self.keepBackup = keepBackup
    }

    public static func defaultFileURL(appName: String = "AIInvestorPro") throws -> URL {
        let base: URL
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        #else
        base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share", isDirectory: true)
        #endif
        let directory = base.appendingPathComponent(appName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw PortfolioStoreError.io(error.localizedDescription)
        }
        return directory.appendingPathComponent("portfolio.json")
    }

    public func exists() -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    public func load() throws -> StoredPortfolio? {
        guard exists() else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(StoredPortfolio.self, from: data)
        } catch let error as PortfolioStoreError {
            throw error
        } catch {
            throw PortfolioStoreError.decoding(error.localizedDescription)
        }
    }

    public func save(_ portfolio: StoredPortfolio) throws {
        var copy = portfolio
        copy.updatedAt = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data: Data
        do {
            data = try encoder.encode(copy)
        } catch {
            throw PortfolioStoreError.encoding(error.localizedDescription)
        }

        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if keepBackup, exists() {
                let backup = fileURL.appendingPathExtension("bak")
                if FileManager.default.fileExists(atPath: backup.path) {
                    try? FileManager.default.removeItem(at: backup)
                }
                try? FileManager.default.copyItem(at: fileURL, to: backup)
            }
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw PortfolioStoreError.io(error.localizedDescription)
        }
    }

    public func delete() throws {
        guard exists() else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw PortfolioStoreError.io(error.localizedDescription)
        }
    }

    public func export(to destination: URL) throws {
        guard exists() else { throw PortfolioStoreError.io("No portfolio file to export") }
        do {
            let directory = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: fileURL, to: destination)
        } catch {
            throw PortfolioStoreError.io(error.localizedDescription)
        }
    }
}
