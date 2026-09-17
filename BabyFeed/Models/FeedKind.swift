import SwiftUI

/// The three ways a newborn gets fed.
enum FeedKind: String, Codable, CaseIterable, Identifiable {
    /// Bottle of formula.
    case formula
    /// Bottle of expressed breast milk.
    case breastMilk
    /// Nursing directly.
    case nursing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formula: "Formula"
        case .breastMilk: "Breast Milk"
        case .nursing: "Nursing"
        }
    }

    var systemImage: String {
        switch self {
        case .formula: "waterbottle.fill"
        case .breastMilk: "drop.fill"
        case .nursing: "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .formula: .orange
        case .breastMilk: .blue
        case .nursing: .pink
        }
    }

    /// Bottle feeds are measured by volume; nursing by duration.
    var usesVolume: Bool { self != .nursing }
}
