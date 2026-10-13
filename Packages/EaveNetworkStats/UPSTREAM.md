# Stats network integration

Vendored from exelban/stats at `0c0e551e199938a92af963c25a15a3ca1aef7764` (MIT; see LICENSE).
The network popup, settings, notifications, preview, readers, charts, formatting and shared AppKit controls come from the upstream implementation.

Eave owns the host window, enable/sleep lifecycle and overview tile. Shared helper files are restricted to network dependencies. Stats remote telemetry, app updater, menu-bar widgets and fan helper are not part of this network-detail integration.
Settings and last reader snapshots are isolated in Eave's `app.eave.network-monitoring` defaults suite. Latest snapshots use native Codable/UserDefaults storage instead of adding Stats' LevelDB binary. The network readers do not request the database's time-series feature; popup histories retain their original buffers.
Localization resolves through the package resource bundle.

## Source mapping
- `Upstream/KitConstants.swift` ← `Kit/constants.swift`
- `Upstream/KitTypes.swift` ← `Kit/types.swift`
- `Upstream/KitExtensions.swift` ← `Kit/extensions.swift`
- `Upstream/KitProcesses.swift` ← `Kit/process.swift`
- `Upstream/KitPopup.swift` ← `Kit/module/popup.swift`
- `Upstream/KitReader.swift` ← `Kit/module/reader.swift`
- `Upstream/KitNotifications.swift` ← `Kit/module/notifications.swift`
- `Upstream/KitCharts.swift` ← `Kit/plugins/Charts.swift`
- `Upstream/KitLogger.swift` ← `Kit/plugins/Logger.swift`
- `Upstream/KitReachability.swift` ← `Kit/plugins/Reachability.swift`
- `Upstream/KitRepeater.swift` ← `Kit/plugins/Repeater.swift`
- `Upstream/NetPopup.swift` ← `Modules/Net/popup.swift`
- `Upstream/NetReaders.swift` ← `Modules/Net/readers.swift`
- `Upstream/NetSettings.swift` ← `Modules/Net/settings.swift`
- `Upstream/NetNotifications.swift` ← `Modules/Net/notifications.swift`
- `Upstream/NetPreview.swift` ← `Modules/Net/preview.swift`

## Host adaptations
- `NetworkMonitor` routes the original popup/header/settings actions into Eave, runs network readers in the background while enabled, pauses on sleep and exposes the original shortcut through Eave's monitor tab.
- `PopupView` reports its original screen-clamped size to SwiftUI rather than resizing the enclosing Eave window.
- A dedicated CoreWLAN event client avoids sharing the delegate with Eave's existing Wi-Fi controls. Public IP queries use the original endpoint and parsers with bounded subprocess timeouts.
- The upstream location-authorization callback could publish cumulative interface counters as current bandwidth. It now combines changed metadata with the last sampled bandwidth, preventing false graph spikes without changing delta/total calculations. Manual reset likewise persists sampled bandwidth and updates the latest snapshot so a reset followed immediately by quit cannot restore the previous total.
- Settings/snapshots have their own defaults suite; the Stats application's existing configuration is not modified. Original locale resources are preserved.

Validation: `swift test --package-path Packages/EaveNetworkStats`, then a Debug app build and `python3 tests/test_monitoring.py --live --ui` (the UI check temporarily opens its own settings window and captures it).
