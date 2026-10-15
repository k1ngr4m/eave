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

    func colorScheme(for system: ColorScheme) -> ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return system
        }
    }

    static func legacyAppearance(lightMode: Bool) -> Self {
        lightMode ? .light : .dark
    }
}
