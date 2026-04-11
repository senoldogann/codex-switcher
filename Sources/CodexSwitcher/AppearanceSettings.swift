import SwiftUI

enum AppearanceTextScale: String, Codable, CaseIterable {
    case small
    case medium
    case large

    var title: String {
        switch self {
        case .small: return L("Küçük", "Small")
        case .medium: return L("Orta", "Medium")
        case .large: return L("Büyük", "Large")
        }
    }

    var multiplier: CGFloat {
        switch self {
        case .small: return 0.9
        case .medium: return 1
        case .large: return 1.12
        }
    }
}

enum AppearanceFontFamily: String, Codable, CaseIterable {
    case system
    case rounded
    case monospaced

    var title: String {
        switch self {
        case .system: return L("System", "System")
        case .rounded: return L("Rounded", "Rounded")
        case .monospaced: return L("Mono", "Mono")
        }
    }

    var design: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        }
    }
}

enum AppearanceThemePreset: String, Codable, CaseIterable {
    case emerald
    case ocean
    case amber
    case rose
    case graphite

    var title: String {
        switch self {
        case .emerald: return L("Emerald", "Emerald")
        case .ocean: return L("Ocean", "Ocean")
        case .amber: return L("Amber", "Amber")
        case .rose: return L("Rose", "Rose")
        case .graphite: return L("Graphite", "Graphite")
        }
    }

    var accentColor: Color {
        switch self {
        case .emerald: return Color(red: 0.35, green: 0.86, blue: 0.45)
        case .ocean: return Color(red: 0.31, green: 0.72, blue: 0.95)
        case .amber: return Color(red: 0.96, green: 0.72, blue: 0.28)
        case .rose: return Color(red: 0.92, green: 0.46, blue: 0.67)
        case .graphite: return Color(red: 0.70, green: 0.72, blue: 0.78)
        }
    }

    var accentSecondaryColor: Color {
        switch self {
        case .emerald: return Color(red: 0.26, green: 0.62, blue: 0.72)
        case .ocean: return Color(red: 0.28, green: 0.57, blue: 0.88)
        case .amber: return Color(red: 0.88, green: 0.52, blue: 0.24)
        case .rose: return Color(red: 0.83, green: 0.39, blue: 0.53)
        case .graphite: return Color(red: 0.54, green: 0.58, blue: 0.65)
        }
    }
}

struct AppAppearance: Equatable {
    let isDarkMode: Bool
    let textScale: AppearanceTextScale
    let fontFamily: AppearanceFontFamily
    let themePreset: AppearanceThemePreset

    var colorScheme: ColorScheme {
        isDarkMode ? .dark : .light
    }

    var foregroundColor: Color {
        isDarkMode ? .white : .black
    }

    var accentColor: Color {
        themePreset.accentColor
    }

    var accentSecondaryColor: Color {
        themePreset.accentSecondaryColor
    }

    var selectionFill: Color {
        accentColor.opacity(isDarkMode ? 0.18 : 0.12)
    }

    var subtleFill: Color {
        accentColor.opacity(isDarkMode ? 0.08 : 0.06)
    }

    func scaled(_ size: CGFloat) -> CGFloat {
        size * textScale.multiplier
    }

    func font(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design? = nil) -> Font {
        .system(
            size: scaled(size),
            weight: weight,
            design: design ?? fontFamily.design
        )
    }

    func monospacedFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(
            size: scaled(size),
            weight: weight,
            design: .monospaced
        )
    }
}
