import SwiftUI

enum Style {
    static func rarity(_ r: Int) -> Color {
        switch r {
        case 0: return Color(white: 0.55)
        case 1: return Color(red: 0.62, green: 0.74, blue: 0.84)
        case 2: return Color(red: 0.88, green: 0.72, blue: 0.28)
        case 3: return Color(red: 0.93, green: 0.42, blue: 0.20)
        case 4: return Color(red: 0.62, green: 0.40, blue: 0.85)
        default: return Color(red: 0.90, green: 0.40, blue: 0.62)
        }
    }

    static func legality(_ s: LegalStatus) -> Color {
        switch s {
        case .legal: return Color(red: 0.25, green: 0.70, blue: 0.42)
        case .restricted: return Color(red: 0.90, green: 0.68, blue: 0.18)
        case .banned: return Color(red: 0.88, green: 0.30, blue: 0.30)
        case .notLegal: return Color.secondary
        }
    }

    static let cardAspect: CGFloat = 0.7168
}
