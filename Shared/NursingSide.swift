import Foundation

enum NursingSide: String, Codable, CaseIterable, Identifiable {
    case left
    case right
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .both: "Both"
        }
    }
}
