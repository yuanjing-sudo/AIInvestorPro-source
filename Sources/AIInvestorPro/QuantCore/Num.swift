// MARK: - Numerical Utilities
import Foundation

public extension Double {
    var formattedCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter.string(from: self as NSNumber) ?? "\(self)"
    }
}
