# Stats monitoring integration

Vendored from exelban/stats at `0c0e551e199938a92af963c25a15a3ca1aef7764` (MIT; see LICENSE).
The network popup, settings, notifications, preview, readers, charts, formatting and shared AppKit controls come from the upstream implementation.

Eave owns the host window, enable/sleep lifecycle and overview tile. Shared helper files contain the dependencies needed by the integrated modules. Stats remote telemetry, app updater, system status-item ownership and fan helper are excluded.
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

- `Upstream/Widget{Speed,NetworkChart,Text,Label,Icon,Dot}.swift` ← the corresponding `Kit/Widgets/*.swift` files
- `Upstream/WidgetEditor.swift` ← the selector, draggable previews and settings sections in `Kit/module/window.swift`
- `Upstream/KitContracts.swift` ← the network widget factory, wrapper and preferences from `Kit/module/widget.swift`, plus settings/preview contracts
- `Resources/NetworkWidgets.plist` ← `Modules/Net/config.plist`

## Host adaptations
- `NetworkWidgets` supplies the original six widget views and their original editors. The selector retains click-to-enable and drag-to-order, with keyboard/VoiceOver press support added. Speed and graph samples use the original activation threshold; text substitutions and connection colors come from `Modules/Net/main.swift`. Widget selections, ordering and styles use the isolated defaults suite.
- Widget height is fixed to Eave's 22-point row instead of the system menu-bar height. The original views render a shared dark-appearance vector image for Eave's closed row, so multiple displays can show identical content without reparenting an AppKit view. One/two-row speed styles retain their original layout inside this row. Merge combines widgets with Stats' compact spacing; separate widgets use wider spacing in the same row. The row grows up to 600 points and scales longer content to fit. All-disabled hides the row; clicking opens network details and the context menu opens settings. A live preview is included in the widget editor.
- `NetworkMonitor` routes the original popup/header/settings actions into Eave, runs network readers in the background while enabled, pauses on sleep and exposes the original shortcut through Eave's monitor tab.
- `PopupView` reports its original screen-clamped size to SwiftUI rather than resizing the enclosing Eave window.
- A dedicated CoreWLAN event client avoids sharing the delegate with Eave's existing Wi-Fi controls. Public IP queries use the original endpoint and parsers with bounded subprocess timeouts.
- The upstream location-authorization callback could publish cumulative interface counters as current bandwidth. It now combines changed metadata with the last sampled bandwidth, preventing false graph spikes without changing delta/total calculations. Manual reset likewise persists sampled bandwidth and updates the latest snapshot so a reset followed immediately by quit cannot restore the previous total.
- Settings/snapshots have their own defaults suite; the Stats application's existing configuration is not modified. Original locale resources are preserved.

Validation: `swift test --package-path Packages/EaveNetworkStats`, then a Debug app build and `python3 tests/test_monitoring.py --live --ui` (the UI check temporarily opens its own settings window and captures it).

## RAM and Disk integration

- `Upstream/RAM{Models,Readers,Popup,Settings,Notifications,Preview}.swift` and `Upstream/Disk{Models,Readers,Popup,Settings,Notifications,Preview}.swift` come from the matching `Modules/RAM` and `Modules/Disk` files at the same revision. Module-local types are prefixed to coexist in one Swift package; `WidgetMemory.swift` and both widget configuration plists retain their original controls.
- `MemoryDiskMonitor` connects readers, native popups, the five settings panes, keyboard shortcuts and widget images to Eave. Eave's module visibility, sleep, settings-window and collapsed-widget lifecycle controls sampling; process readers run only while details are visible. The old Eave memory/disk sampling path is excluded from the live manager.
- `CStatsDisk` exposes the upstream NVMe SMART interface and Apple's ATA SMART header. SMART remains subject to device/driver support. The disk overview gets its startup-drive identity from the capacity reader instead of another SystemKit inventory scan.
- Disk callbacks deliver immutable snapshots to the UI; overlapping disk reads are serialized. Activity and process rates use elapsed monotonic time and rebaseline after long pauses, resets and first samples. The disk selector replaces changed mount lists without duplicate items. Popup and reader process counts share the same default.
- Settings use the existing isolated Eave defaults suite. Memory/disk widgets support the same selector, ordering, style controls, preview, combined row and click-to-open behavior as the network/processor widgets. Eave provides Simplified and Traditional Chinese labels for the new entry points.

Validation: `swift test --package-path Packages/EaveNetworkStats`. Set `EAVE_STATS_LIVE=1` to exercise real RAM, capacity, activity, process and SMART readers; optionally set `EAVE_STATS_CAPTURE_DIR` to capture every settings tab and both popups. `MemoryDiskTests` covers real setting callbacks, selected-drive switching, mount-list replacement, rate baselines, all widget rendering and lifecycle shutdown.

## CPU and GPU integration

- `Upstream/CPU{Models,Readers,Popup,Settings,Notifications,Preview}.swift` and `Upstream/GPU{Models,Reader,Popup,Settings,Notifications,Preview}.swift` come from `Modules/CPU` and `Modules/GPU` at the same pinned revision. Models come from each module's `main.swift`; module-local names are prefixed to coexist in this package. `ProcessorSystemKit.swift` contains the original CPU cluster/frequency, GPU inventory and boot-time helpers.
- `Widget{Mini,LineChart,BarChart,PieChart,Tachometer}.swift` and `Resources/{CPU,GPU}Widgets.plist` retain the original widget renderers and settings. `ProcessorWidgets` uses the original `main.swift` value routing: CPU system/user, per-core and cluster values; selected GPU utilization, GPU type and text variables. Editing styles rerenders the latest value without adding artificial history samples.
- `StatsWidgets` and `makeStatsSettingsWindow` share the existing network renderer/editor and native five-tab settings host. Each CPU/GPU module offers all seven original widget types, selection, ordering, merge spacing and persistent styles. Native pop-up controls forward their selected menu item to the original Stats action handlers.
- `ProcessorMonitor` hosts the original readers, popup, preview, notifications and shortcut. CPU/GPU overview values now use these readers; the legacy overview sampler no longer polls them. Eave's visibility, collapsed-widget switch, open settings and sleep state govern sampling. CPU process collection runs only with details open.
- SMC reads reuse Eave's read-only connection via `HardwareAccess`; temperature formatting uses Eave's selected unit. IOReport bindings resolve dynamically, as in Eave's existing sensor integration. No fan control is added.
- GPU setup does not abort IOReport discovery when no PCI service is present on Apple Silicon. GPU reads are serialized. The GPU menu refreshes when device identities change, and the text widget's original variables are editable from its module settings.
- CPU/GPU widgets have individual collapsed-display switches and share the same 22-point row above lyrics, including when no lyrics are present. Each module opens its own native popup on click and settings through its context menu. Configuration stays in the existing Eave defaults suite for compatibility; the package name is retained.

Validation: `ProcessorTests` checks original control actions, system/user/per-core/cluster values, GPU selection and text editing, history semantics, persistence and live CPU sampling. `tests/test_monitoring.py --ui` additionally checks live CPU/GPU readers, all native settings panes, popup visibility, collapsed-widget clicks and sleep/enable lifecycle.

## Sensors integration

The read-only Sensors module and Stack widget are vendored from the same pinned
commit above (`Modules/Sensors/{values,readers,settings,popup,notifications}.swift`,
`config.plist`, and `Kit/Widgets/Stack.swift`). `CStatsSensors` contains the original
HID reader and its header; IOReport uses the existing optional Swift loader.
`SensorsMonitor` serializes discovery, sampling and shutdown, rejects callbacks
from previous sessions, and supplies the original four settings panes and popup.
SMC enumeration, strings and values use Eave's existing read-only connection.
The fan control UI, helper, speed persistence and all hardware writes are excluded.

Sensor selection, popup visibility, thresholds and Stack ordering use the existing
Eave defaults suite. The closed widget is opt-in and shares the 22-point row and
600-point width cap. Temperature units follow Eave. Missing/invalid readings show
an em dash rather than zero or a previous sample; fan percentages have a guarded
maximum-speed divisor, and notification fan thresholds use fractional percentages.
HID discovery and power baselines restart after suspension. Total consumption and
average power describe the current uninterrupted sampling session, excluding sleep.
Changing temperature units rebuilds popup charts so old-unit points are not mixed.

Validation adds `SensorsTests` (fake SMC data, real original controls/renderers,
missing readings, persistence and stop/restart) and sensor coverage in
`tests/test_monitoring.py --live --ui` (actual SMC/HID/IOReport, settings, shared
widget row and simulated workspace sleep/wake notifications).
