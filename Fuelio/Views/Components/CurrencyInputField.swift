import SwiftUI
import UIKit

/// A text field that handles right-to-left digit entry with fixed decimal places.
/// - Right-to-left: typing "247" displays "2.47" for 2 decimal places
/// - Explicit decimal: typing "2.47" also displays "2.47"
/// - Extra digits after decimal limit are ignored
struct CurrencyInputField: View {
    @Binding var value: Int  // Value in smallest units (cents for 2 decimals, mills for 3)
    let decimalPlaces: Int
    let width: CGFloat

    init(
        value: Binding<Int>,
        decimalPlaces: Int = 2,
        width: CGFloat = 100
    ) {
        self._value = value
        self.decimalPlaces = decimalPlaces
        self.width = width
    }

    var body: some View {
        CurrencyTextFieldRepresentable(
            value: $value,
            decimalPlaces: decimalPlaces
        )
        .frame(width: width, height: 22)
    }
}

// MARK: - Integer Power Helper
private func intPow(_ base: Int, _ exp: Int) -> Int {
    guard exp >= 0 else { return 0 }
    var result = 1
    for _ in 0..<exp {
        result *= base
    }
    return result
}

// MARK: - Display Formatting
private func formatValue(_ value: Int, decimalPlaces: Int) -> String {
    let divisor = intPow(10, decimalPlaces)
    let integerPart = value / divisor
    let decimalPart = abs(value % divisor)
    // Pad decimal part with leading zeros
    let decimalString = String(format: "%0\(decimalPlaces)d", decimalPart)
    return "\(integerPart).\(decimalString)"
}

// MARK: - UIViewRepresentable
private struct CurrencyTextFieldRepresentable: UIViewRepresentable {
    @Binding var value: Int
    let decimalPlaces: Int

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.keyboardType = .decimalPad
        textField.textAlignment = .right
        textField.font = UIFont(name: "Avenir Next", size: 16)
        textField.text = formatValue(value, decimalPlaces: decimalPlaces)
        textField.delegate = context.coordinator

        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        // Only update if the value changed externally (e.g., from calculation)
        // and we're not currently editing
        if !textField.isFirstResponder {
            textField.text = formatValue(value, decimalPlaces: decimalPlaces)
            // Reset coordinator state when not editing
            context.coordinator.resetState()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator (State Machine)
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CurrencyTextFieldRepresentable

        // State machine
        private var isDecimalMode: Bool = false
        private var decimalPosition: Int = 0

        init(_ parent: CurrencyTextFieldRepresentable) {
            self.parent = parent
        }

        func resetState() {
            isDecimalMode = false
            decimalPosition = 0
        }

        // MARK: - UITextFieldDelegate

        func textFieldDidBeginEditing(_ textField: UITextField) {
            resetState()
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            resetState()
            // Ensure display is formatted correctly
            textField.text = formatValue(parent.value, decimalPlaces: parent.decimalPlaces)
        }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {

            let decimalPlaces = parent.decimalPlaces
            let multiplier = intPow(10, decimalPlaces)

            // Handle backspace/delete
            if string.isEmpty {
                handleBackspace(multiplier: multiplier, decimalPlaces: decimalPlaces)
                textField.text = formatValue(parent.value, decimalPlaces: decimalPlaces)
                return false
            }

            // Handle decimal point
            if string == "." || string == "," {
                handleDecimalPoint(multiplier: multiplier)
                textField.text = formatValue(parent.value, decimalPlaces: decimalPlaces)
                return false
            }

            // Only allow digits
            guard CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: string)) else {
                return false
            }

            // Process each digit
            for char in string {
                if let digit = Int(String(char)) {
                    handleDigit(digit, decimalPlaces: decimalPlaces)
                }
            }

            textField.text = formatValue(parent.value, decimalPlaces: decimalPlaces)
            return false
        }

        // MARK: - State Machine Operations

        private func handleDigit(_ digit: Int, decimalPlaces: Int) {
            if isDecimalMode {
                // Decimal mode: fill decimal places from left to right
                guard decimalPosition < decimalPlaces else {
                    // All decimal places filled - IGNORE additional digits
                    return
                }

                let positionMultiplier = intPow(10, decimalPlaces - 1 - decimalPosition)

                // Clear existing digit at this position
                let existingDigit = (parent.value / positionMultiplier) % 10
                parent.value -= existingDigit * positionMultiplier

                // Add new digit
                parent.value += digit * positionMultiplier
                decimalPosition += 1
            } else {
                // Normal mode: right-to-left entry
                let newValue = parent.value * 10 + digit

                // Prevent overflow
                if newValue <= 999_999_999 && newValue >= parent.value {
                    parent.value = newValue
                }
            }
        }

        private func handleDecimalPoint(multiplier: Int) {
            guard !isDecimalMode else {
                // Already in decimal mode - ignore
                return
            }

            // Switch to decimal mode
            // Current value becomes integer part
            let newValue = parent.value * multiplier

            // Check for overflow
            if newValue <= 999_999_999 && (parent.value == 0 || newValue / multiplier == parent.value) {
                parent.value = newValue
                isDecimalMode = true
                decimalPosition = 0
            }
        }

        private func handleBackspace(multiplier: Int, decimalPlaces: Int) {
            if isDecimalMode {
                if decimalPosition > 0 {
                    // Clear the last entered decimal digit
                    let targetPosition = decimalPosition - 1
                    let positionMultiplier = intPow(10, decimalPlaces - 1 - targetPosition)

                    let existingDigit = (parent.value / positionMultiplier) % 10
                    parent.value -= existingDigit * positionMultiplier
                    decimalPosition -= 1
                } else {
                    // At position 0 - transition back to normal mode
                    parent.value = parent.value / multiplier
                    isDecimalMode = false
                }
            } else {
                // Normal mode: remove last digit
                parent.value = parent.value / 10
            }

            // Ensure non-negative
            if parent.value < 0 {
                parent.value = 0
            }
        }
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @State private var totalCost: Int = 0
        @State private var gallons: Int = 0
        @State private var price: Int = 0

        var body: some View {
            Form {
                Section("Total Cost (2 decimals)") {
                    HStack {
                        Text("$")
                        CurrencyInputField(value: $totalCost, decimalPlaces: 2)
                    }
                    Text("Raw: \(totalCost) cents = $\(String(format: "%.2f", Double(totalCost)/100))")
                        .font(.caption)
                }

                Section("Gallons (3 decimals)") {
                    HStack {
                        CurrencyInputField(value: $gallons, decimalPlaces: 3)
                        Text("gal")
                    }
                    Text("Raw: \(gallons) mills")
                        .font(.caption)
                }

                Section("Price (3 decimals)") {
                    HStack {
                        Text("$")
                        CurrencyInputField(value: $price, decimalPlaces: 3)
                    }
                    Text("Raw: \(price) mills")
                        .font(.caption)
                }

                Section("Instructions") {
                    Text("• Type '247' → 2.47 (right-to-left)")
                    Text("• Type '2.47' → 2.47 (explicit decimal)")
                    Text("• Type '1.23456' → 1.23 (extra digits ignored)")
                }
                .font(.caption)
            }
        }
    }

    return PreviewWrapper()
}

