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

    /// The other one: what goes in parentheses, for the doctor who asks in
    /// the unit you don't use.
    var other: VolumeUnit { self == .ounces ? .milliliters : .ounces }

    /// The finest amount worth typing or showing: a whole ml, a quarter oz,
    /// which is how finely a bottle marked in ounces is read.
    var precision: Double {
        switch self {
        case .ounces: 0.25
        case .milliliters: 1
        }
    }

    /// What the feed sheet's − / + move by: a quarter oz, or 10 ml.
    var adjustStep: Double {
        switch self {
        case .ounces: 0.25
        case .milliliters: 10
        }
    }

    /// The parts of an ounce the feed sheet offers as chips.
    static let ounceFractions: [(value: Double, label: String)] = [(0.25, "¼"), (0.5, "½"), (0.75, "¾")]

    /// Rounds a value in this unit to the nearest step so converted values
    /// don't show up as 2.4999 oz.
    func rounded(_ value: Double) -> Double {
        (value / step).rounded() * step
    }

    /// Rounds to `precision` rather than to the step, so an exact 75 ml stays
    /// 75 ml instead of snapping to 80.
    func roundedToPrecision(_ value: Double) -> Double {
        (value / precision).rounded() * precision
    }

    /// The same amount converted into this unit from another, to its precision.
    func converted(_ value: Double, from unit: VolumeUnit) -> Double {
        roundedToPrecision(fromMilliliters(unit.toMilliliters(value)))
    }

    /// "2.25" or "75" – number only, no unit. Ounces go to the quarter, so
    /// 90 ml reads "3 oz", not "3.04 oz".
    func formatValue(_ value: Double, locale: Locale = .current) -> String {
        switch self {
        case .ounces:
            roundedToPrecision(value).formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        case .milliliters:
            value.formatted(.number.precision(.fractionLength(0)).locale(locale))
        }
    }

    /// "2.5 oz" or "75 ml".
    func format(milliliters ml: Double, locale: Locale = .current) -> String {
        "\(formatValue(fromMilliliters(ml), locale: locale)) \(symbol)"
    }

    /// "4 oz (118 ml)": this unit first, the other in parentheses. For the
    /// places someone reads an amount back to a doctor, not for every label.
    func formatWithOther(milliliters ml: Double, locale: Locale = .current) -> String {
        "\(format(milliliters: ml, locale: locale)) (\(other.format(milliliters: ml, locale: locale)))"
    }
}
