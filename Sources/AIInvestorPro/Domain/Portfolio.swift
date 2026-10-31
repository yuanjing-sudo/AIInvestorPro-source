// MARK: - Portfolio
import Foundation

public struct Portfolio {
    public let cash: Double
    public let holdings: [String: Double]
    
    public var totalValue: Double {
        cash + holdings.reduce(0) { $0 + $1.value }
    }
}
