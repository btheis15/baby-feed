import SwiftUI
import UIKit

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
        case .breastMilk: .breastMilk
        case .nursing: .pink
        }
    }

    /// Bottle feeds are measured by volume; nursing by duration.
    var usesVolume: Bool { self != .nursing }
}

extension Color {
    /// Warm cream for expressed breast milk – a blue drop reads as water.
    ///
    /// Built from a dynamic `UIColor` rather than an asset catalog colour
    /// because `FeedKind` is compiled into the widget as well, and the widget
    /// target has no asset catalogue of its own to look a named colour up in.
    ///
    /// The two shades are not the same hue lightened: the colour is used both
    /// as `foregroundStyle` for the label and, at 15% opacity, as the button
    /// background, so light mode needs a deep enough tan to stay legible on
    /// white while dark mode needs a pale cream to stay legible on black.
    static let breastMilk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.87, blue: 0.71, alpha: 1)
            : UIColor(red: 0.72, green: 0.55, blue: 0.27, alpha: 1)
    })
}
