import SwiftUI

/// Uses the same visibility preferences as the status panel. Hidden devices are
/// also revoked from foreground and background battery reads by SystemStatusStore.
@MainActor
struct MobileBatterySettingsSection: View {
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var discovery: AppleDeviceDiscoveryController
    @ObservedObject private var localization: Localization

    init(controller: MenuBarStatusController) {
        _settings = ObservedObject(wrappedValue: controller.settings)
        _discovery = ObservedObject(wrappedValue: controller.store.appleDeviceDiscovery)
        _localization = ObservedObject(wrappedValue: controller.localization)
    }

    var body: some View {
        Section {
            Toggle(localization.string(.settingsAppleDevicesAndBattery), systemImage: "battery.100", isOn: $settings.showsAppleDevicesAndBattery)
            if settings.showsAppleDevicesAndBattery {
                Toggle(localization.string(.settingsAppleBackgroundRefresh), systemImage: "headphones", isOn: $settings.refreshesAppleBatteriesInBackground)
                if settings.refreshesAppleBatteriesInBackground {
                    Stepper(value: $settings.appleBatteryRefreshIntervalMinutes,
                            in: SettingsStore.appleBatteryRefreshIntervalMinutesRange) {
                        Text(localization.string(.settingsAppleBackgroundRefreshInterval) + ": " + localization.format(
                            .settingsAppleBackgroundRefreshIntervalValue, settings.appleBatteryRefreshIntervalMinutes))
                    }
                }
                ForEach(candidates) { candidate in
                    Toggle(isOn: Binding(
                        get: { !settings.hiddenBluetoothDeviceAddresses.contains(BluetoothDeviceIdentity.preferenceKey(candidate.id.rowID)) },
                        set: { settings.setBluetoothDeviceHidden(candidate.id.rowID, hidden: !$0) }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.name)
                            if let model = candidate.model { Text(model).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                HStack {
                    Button(localization.string(.bluetoothRefresh)) { discovery.refresh() }
                        .disabled(discovery.isDiscovering)
                    if discovery.isDiscovering { ProgressView().controlSize(.small) }
                }
            }
        } header: {
            Text(localization.string(.settingsAppleDevicesAndBattery))
        } footer: {
            Text(localization.string(.settingsAppleDeviceConnectionHelp))
        }
        .onAppear { discovery.request("eave.settings.mobile-battery") }
        .onDisappear { discovery.release("eave.settings.mobile-battery") }
    }

    private var candidates: [AppleDeviceCandidate] {
        AppleDeviceCatalog.candidates(trusted: settings.trustedAppleDeviceMetadata + discovery.candidates)
    }
}
