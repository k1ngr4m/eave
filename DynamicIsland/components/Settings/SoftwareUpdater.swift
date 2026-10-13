/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import SwiftUI
import Sparkle

/// One updater for the app lifetime; development builds never contact the feed.
@MainActor
final class EaveUpdater: ObservableObject {
    static let shared = EaveUpdater()
    let updater: SPUUpdater?
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = true {
        didSet { updater?.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }
    private var startupError: Error?

    private init() {
        guard UpdateChannel.buildChannel == .release else {
            updater = nil
            return
        }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main,
                                 userDriver: EaveUserDriver(), delegate: nil)
        self.updater = updater
        do {
            try updater.start()
            automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
            updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        } catch {
            startupError = error
            canCheckForUpdates = true // Allow the button to explain configuration errors.
        }
    }

    func checkForUpdates() {
        if let startupError {
            NSAlert(error: startupError).runModal()
        } else {
            updater?.checkForUpdates()
        }
    }
}
