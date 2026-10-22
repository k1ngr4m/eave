import SwiftUI
import Defaults

enum NotchAppearance: String, CaseIterable, Defaults.Serializable, Identifiable {
    case light, dark, system

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        case .system: return String(localized: "Follow System")
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    func colorScheme(for system: ColorScheme) -> ColorScheme {
        preferredColorScheme ?? system
    }

    static func legacyAppearance(lightMode: Bool) -> Self {
        lightMode ? .light : .dark
    }
}
