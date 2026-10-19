import SwiftUI

struct BatteryDetailsView: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelDetailState
    let onBack: () -> Void
    let onOpenBatterySettings: () -> Void
    let onCopyValue: (String) -> Void
    let onAppear: () -> Void
    /// The Low Power Mode write path, injected by the popover. Nil in previews
    /// and layout tests, where the read-only row stands in for it.
    private let lowPowerMode: LowPowerModeController?
    private let showsLowPowerControl: Bool

    init(
        state: PanelDetailState,
        onBack: @escaping () -> Void,
        onOpenBatterySettings: @escaping () -> Void,
        onCopyValue: @escaping (String) -> Void,
        onAppear: @escaping () -> Void,
        lowPowerMode: LowPowerModeController? = nil,
        showsLowPowerControl: Bool = false
    ) {
        self.state = state
        self.onBack = onBack
        self.onOpenBatterySettings = onOpenBatterySettings
        self.onCopyValue = onCopyValue
        self.onAppear = onAppear
        self.lowPowerMode = lowPowerMode
        self.showsLowPowerControl = showsLowPowerControl
    }

    private var detailRows: [PanelDetailRow] { state.rows }

    private static let rowIcons: [String: (symbol: String, color: Color)] = [
        LocalizationKey.batteryDetailsSystemPower.rawValue: ("bolt.fill", .orange),
        LocalizationKey.batteryDetailsDischarging.rawValue: ("bolt.fill", .orange),
        LocalizationKey.batteryDetailsSystemReadAt.rawValue: ("clock", .secondary),
        LocalizationKey.batteryDetailsSampled.rawValue: ("clock", .secondary),
        LocalizationKey.batteryDetailsCharging.rawValue: ("battery.100.bolt", .green),
        LocalizationKey.batteryDetailsVoltage.rawValue: ("bolt.horizontal.fill", .orange),
        LocalizationKey.batteryDetailsCurrent.rawValue: ("waveform.path", .orange),
        LocalizationKey.batteryDetailsAdapter.rawValue: ("powerplug.fill", .blue),
        LocalizationKey.batteryDetailsRemaining.rawValue: ("hourglass", .secondary),
        LocalizationKey.batteryDetailsCycles.rawValue: ("heart.fill", .pink),
        LocalizationKey.batteryDetailsLowPower.rawValue: ("leaf.fill", .green)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationBackRow(
                accessibilityLabel: localization.string(.commonBack),
                title: state.title,
                action: onBack
            )

            VStack(alignment: .leading, spacing: 6) {
                if state.isLoading {
                    Text(localization.string(.batteryDetailsLoading))
                        .foregroundStyle(.secondary)
                }
                PanelDetailRowsView(detailRows: detailRows, icons: Self.rowIcons, onCopyValue: onCopyValue)
                if let explanation = state.explanation {
                    Text(explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .font(.caption)
            .monospacedDigit()

            if showsLowPowerControl, let lowPowerMode {
                Divider()
                LowPowerModeControlRow(controller: lowPowerMode)
            }

            Divider()
            Button(localization.string(.batteryActionOpenSettings), action: onOpenBatterySettings)
                .buttonStyle(.plain)
        }
        .task(id: state.lifecycleIdentity) { onAppear() }
    }

}

private struct LowPowerModeControlRow: View {
    @ObservedObject var controller: LowPowerModeController
    @EnvironmentObject private var localization: Localization

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                localization.string(.lowPowerModeToggle),
                isOn: Binding(
                    get: { controller.isLowPowerMode },
                    set: { controller.setLowPowerMode($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(controller.isApplying)
            .help(localization.string(.lowPowerModeToggleDescription))

            if let error = controller.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
