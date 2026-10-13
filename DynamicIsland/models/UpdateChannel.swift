/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Defaults

/// Distribution channel, independent of Debug/Release compiler settings.
enum UpdateChannel: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case dev
    case release

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// A color used for the channel badge in the UI.
    var badgeColor: NSColor {
        switch self {
        case .dev: return .systemYellow
        case .release: return .systemGreen
        }
    }

    /// An SF Symbol icon for the channel badge.
    var badgeIcon: String {
        switch self {
        case .dev: return "hammer.fill"
        case .release: return "checkmark.seal.fill"
        }
    }

    /// Stamped into the bundle by the app's version build phase.
    static var buildChannel: UpdateChannel {
        UpdateChannel(rawValue: Bundle.main.object(forInfoDictionaryKey: "EaveBuildChannel") as? String ?? "") ?? .dev
    }

}
