import SwiftUI

struct BatteryStatusView: View {
    @EnvironmentObject private var localization: Localization
    let state: PanelSummaryState
    var cautionColor: Color = .yellow
    let onOpenBatteryDetails: () -> Void
    let onOpenBatterySettings: () -> Void

    private var hasDetails: Bool { state.intent == .batteryDetails }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenBatteryDetails) {
                HStack(spacing: 10) {
                    PanelSymbolView(source: state.symbol)
                        .foregroundStyle(state.tint.color(caution: cautionColor))
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title)
                            .font(.headline)
                            .monospacedDigit()
                        Text(state.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    if let measurements = state.measurements {
                        Text(measurements)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .fixedSize()
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.25), value: measurements)
                            .help(state.accessibilityValue)
                    }

                    if hasDetails {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .disabled(!hasDetails)
            .accessibilityLabel(state.accessibilityLabel)
            .accessibilityValue(state.accessibilityValue)

            if state.showsSettings {
                Button(
                    localization.string(.batteryActionOpenSettings),
                    systemImage: "gearshape",
                    action: onOpenBatterySettings
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(localization.string(.batteryActionOpenSettings))
                .frame(width: 24, height: 24)
            }
        }
    }

    var showsDetailAffordance: Bool { hasDetails }
}
