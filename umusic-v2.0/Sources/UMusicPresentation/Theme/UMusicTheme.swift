import SwiftUI

public enum UMusicThemePreference: String, CaseIterable, Sendable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }
    public var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
    public var displayName: String { rawValue.capitalized }
}

public enum UMusicAccent: String, CaseIterable, Sendable, Identifiable {
    case violet, blue, orange, green
    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
    public var color: Color {
        switch self {
        case .violet: Color(red: 0.49, green: 0.24, blue: 0.92)
        case .blue: Color(red: 0.05, green: 0.42, blue: 0.85)
        case .orange: Color(red: 0.82, green: 0.31, blue: 0.04)
        case .green: Color(red: 0.03, green: 0.48, blue: 0.27)
        }
    }
}

public enum UMusicTheme {
    public static let themeDefaultsKey = "umusic.v2.appearance.theme"
    public static let accentDefaultsKey = "umusic.v2.appearance.accent"
    public static let accent = UMusicAccent.violet.color
    public static var accentColor: Color { accent }
    public static let miniPlayerHeight: CGFloat = 64
    public static let cornerRadius: CGFloat = 16
    public static let contentSpacing: CGFloat = 16
}
