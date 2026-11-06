import SwiftUI
import AppKit

extension Color {
    static let ink = Color(hex: 0x0B0B0F)
    static let electricViolet = Color(hex: 0x7C5CFF)
    static let mint = Color(hex: 0x3DF5B0)
    static let sunnyYellow = Color(hex: 0xFFD84D)
    static let coral = Color(hex: 0xFF6B6B)

    static let acid = Color(hex: 0xD4FF8C)
    static let paper = Color(hex: 0xF4F2FF)

    static let shelfSurface = Color(hex: 0x15141D)
    static let shelfBorder = adaptive(normal: 0x272538, contrast: 0xA29DBF)
    static let primaryText = Color.paper
    static let secondaryText = adaptive(normal: 0xA29DBF, contrast: 0xF4F2FF)

    private static func adaptive(normal: UInt32, contrast: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let high = appearance.bestMatch(from: [.accessibilityHighContrastDarkAqua, .darkAqua]) == .accessibilityHighContrastDarkAqua
            let hex = high ? contrast : normal
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        })
    }

    private init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
