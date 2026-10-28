import SwiftUI
import UIKit

/// One theme for the whole app: deep indigo ink on warm cream paper, with amber as the single warm accent.
/// Dark mode inverts it: cream text on night-indigo, with a lighter periwinkle accent.
enum Theme {
    // Brand colours (fixed)
    static let ink = Color(hex: 0x1E2352)         // deep indigo
    static let cream = Color(hex: 0xF3E9D2)
    static let periwinkle = Color(hex: 0x8C8FF0)
    static let amber = Color(hex: 0xF2A65A)

    // Surfaces and text (adapt to dark mode)
    static let background = dynamic(light: (0.973, 0.957, 0.918), dark: (0.075, 0.082, 0.16))
    static let card = dynamic(light: (1.0, 1.0, 1.0), dark: (0.125, 0.137, 0.25))
    static let text = dynamic(light: (0.118, 0.137, 0.32), dark: (0.95, 0.92, 0.85))

    /// Secondary text: a softer indigo-grey instead of system grey.
    static let muted = dynamic(light: (0.38, 0.40, 0.55), dark: (0.68, 0.69, 0.80))

    /// Links, icons, labels.
    static let accent = dynamic(light: (0.20, 0.23, 0.60), dark: (0.66, 0.68, 1.0))
    /// Filled buttons and badges; use `onAccent` for the content on top.
    static let accentFill = dynamic(light: (0.20, 0.23, 0.60), dark: (0.62, 0.64, 0.99))
    static let onAccent = dynamic(light: (1.0, 1.0, 1.0), dark: (0.118, 0.137, 0.32))

    /// Errors and warnings: a deep amber that belongs to the palette.
    static let warning = dynamic(light: (0.70, 0.33, 0.06), dark: (1.0, 0.70, 0.42))

    /// Marker colour for highlighted sentences.
    static let highlight = amber.opacity(0.45)

    // UIKit equivalents for the LaTeX renderer
    static let inkUI = UIColor(red: 0.118, green: 0.137, blue: 0.32, alpha: 1)
    static let creamUI = UIColor(red: 0.95, green: 0.92, blue: 0.85, alpha: 1)

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func dynamic(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

/// Every cover uses the same four colours; papers differ by pattern, not by hue.
struct CoverPalette {
    let bg: Color, a: Color, b: Color, c: Color
    var ink: Color { a }
    static let brand = CoverPalette(bg: Theme.ink, a: Theme.cream, b: Theme.periwinkle, c: Theme.amber)
}

extension Topic {
    /// Topics share the app's accent colour; they are told apart by icon and cover pattern.
    var color: Color { Theme.accent }
    var fill: Color { Theme.accentFill }
    var palette: CoverPalette { .brand }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
