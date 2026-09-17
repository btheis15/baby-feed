import Foundation

/// Display unit for bottle volumes. Everything is stored in milliliters;
/// this type converts and formats for the screen.
enum VolumeUnit: String, CaseIterable, Identifiable {
    case ounces
    case milliliters

    var id: String { rawValue }

    static let millilitersPerOunce = 29.5735

    var symbol: String {
        switch self {
        case .ounces: "oz"
        case .milliliters: "ml"
        }
    }

    var title: String {
        switch self {
        case .ounces: "Ounces (oz)"
        case .milliliters: "Milliliters (ml)"
        }
    }

    /// Increment used by the − / + buttons.
    var step: Double {
        switch self {
        case .ounces: 0.5
        case .milliliters: 10
        }
    }

    /// Quick-pick amounts shown as chips.
    var presets: [Double] {
        switch self {
        case .ounces: [1, 2, 3, 4, 5, 6]
        case .milliliters: [30, 60, 90, 120, 150, 180]
        }
    }

    /// Sensible starting amount for a brand-new user, in this unit.
    var defaultAmount: Double {
        switch self {
        case .ounces: 2
        case .milliliters: 60
        }
    }

    var maximum: Double {
        switch self {
        case .ounces: 12
        case .milliliters: 360
        }
    }

    func toMilliliters(_ value: Double) -> Double {
        switch self {
        case .ounces: value * Self.millilitersPerOunce
        case .milliliters: value
        }
    }

    func fromMilliliters(_ ml: Double) -> Double {
        switch self {
        case .ounces: ml / Self.millilitersPerOunce
        case .milliliters: ml
        }
    }

    /// Rounds a value in this unit to the nearest step so converted values
    /// don't show up as 2.4999 oz.
    func rounded(_ value: Double) -> Double {
        (value / step).rounded() * step
    }

    /// "2.5" or "75" – number only, no unit.
    func formatValue(_ value: Double, locale: Locale = .current) -> String {
        switch self {
        case .ounces:
            value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        case .milliliters:
            value.formatted(.number.precision(.fractionLength(0)).locale(locale))
        }
    }

    /// "2.5 oz" or "75 ml".
    func format(milliliters ml: Double, locale: Locale = .current) -> String {
        "\(formatValue(fromMilliliters(ml), locale: locale)) \(symbol)"
    }
}
