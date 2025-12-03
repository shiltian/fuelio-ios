import Foundation
import SwiftUI

// MARK: - Double Extensions

extension Double {
    /// Format as currency (e.g., $3.45)
    var currencyFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: self)) ?? "$\(self)"
    }

    /// Format with specific decimal places
    func formatted(decimals: Int) -> String {
        String(format: "%.\(decimals)f", self)
    }
}

// MARK: - View Extensions

extension View {
    /// Hide keyboard
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Array Extensions

extension Array where Element == FuelingRecord {
    /// Calculate total cost for records
    var totalCost: Double {
        reduce(0) { $0 + $1.totalCost }
    }

    /// Calculate total miles for records (using cached values)
    var totalMiles: Double {
        reduce(0) { $0 + $1.getMilesDriven() }
    }

    /// Calculate total gallons for records
    var totalGallons: Double {
        reduce(0) { $0 + $1.gallons }
    }
}
