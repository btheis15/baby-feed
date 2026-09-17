import Foundation

enum WeightUnit: String, CaseIterable, Identifiable {
    case poundsOunces
    case kilograms

    var id: String { rawValue }

    static let gramsPerPound = 453.59237
    static let gramsPerOunce = 28.349523125

    var title: String {
        switch self {
        case .poundsOunces: "Pounds & ounces"
        case .kilograms: "Kilograms"
        }
    }

    /// "7 lb 12 oz" or "3.52 kg".
    func format(grams: Double, locale: Locale = .current) -> String {
        switch self {
        case .poundsOunces:
            let totalOunces = (grams / Self.gramsPerOunce).rounded()
            let pounds = Int(totalOunces / 16)
            let ounces = Int(totalOunces) - pounds * 16
            return ounces == 0 ? "\(pounds) lb" : "\(pounds) lb \(ounces) oz"
        case .kilograms:
            let kg = grams / 1000
            return "\(kg.formatted(.number.precision(.fractionLength(2)).locale(locale))) kg"
        }
    }

    /// Weekly gain, e.g. "+6 oz/week" or "+170 g/week".
    func formatGain(gramsPerWeek: Double) -> String {
        let sign = gramsPerWeek >= 0 ? "+" : "−"
        switch self {
        case .poundsOunces:
            let ounces = abs(gramsPerWeek) / Self.gramsPerOunce
            return "\(sign)\(ounces.formatted(.number.precision(.fractionLength(0...1)))) oz/week"
        case .kilograms:
            return "\(sign)\(Int(abs(gramsPerWeek).rounded())) g/week"
        }
    }

    static func grams(pounds: Int, ounces: Double) -> Double {
        Double(pounds) * gramsPerPound + ounces * gramsPerOunce
    }

    static func poundsAndOunces(grams: Double) -> (pounds: Int, ounces: Int) {
        let totalOunces = Int((grams / gramsPerOunce).rounded())
        return (totalOunces / 16, totalOunces % 16)
    }
}
