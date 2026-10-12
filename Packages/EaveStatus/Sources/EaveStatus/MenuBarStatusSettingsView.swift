import SwiftUI

/// Embedded in Eave's settings window; application identity and startup remain host-owned.
@MainActor
public struct MenuBarStatusSettingsView: View {
    private let controller: MenuBarStatusController
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var localization: Localization

    public init(controller: MenuBarStatusController) {
        self.controller = controller
        _settings = ObservedObject(wrappedValue: controller.settings)
        _localization = ObservedObject(wrappedValue: controller.localization)
    }

    public var body: some View {
        Form {
            MobileBatterySettingsSection(controller: controller)
            Section(localization.string(.settingsIconSize)) {
                HStack {
                    Slider(value: $settings.iconSize, in: SettingsStore.iconSizeRange, step: 1) {
                        Text(localization.string(.settingsIconSize))
                    }
                    Text("\(Int(settings.iconSize)) pt").monospacedDigit().frame(width: 44)
                }
                Picker(localization.string(.settingsRingStrokeStyle), selection: $settings.ringStrokeStyle) {
                    Text(localization.string(.settingsRingStrokeStyleLight)).tag(RingStrokeStyle.light)
                    Text(localization.string(.settingsRingStrokeStyleRegular)).tag(RingStrokeStyle.regular)
                    Text(localization.string(.settingsRingStrokeStyleBold)).tag(RingStrokeStyle.bold)
                }
            }
            Section(localization.string(.settingsBatteryTitle)) {
                Toggle(localization.string(.settingsBatteryShowPercentage), isOn: $settings.showsBatteryPercentage)
                Toggle(localization.string(.settingsBatteryShowChargingIndicator), isOn: $settings.showsChargingIndicator)
                Toggle(localization.string(.settingsBatteryChargingEffect), isOn: $settings.showsChargingEffect)
                Toggle(localization.string(.settingsBatteryPercentageWhenConnected), isOn: $settings.showsPercentageWhenConnected)
                Toggle(localization.string(.settingsBatteryStatusColors), isOn: $settings.usesBatteryStatusColors)
                Slider(value: $settings.batteryCriticalThreshold, in: SettingsStore.batteryCriticalThresholdRange, step: 1) {
                    Text(localization.string(.settingsBatteryCriticalThreshold))
                }
            }
            Section(localization.string(.settingsNetworkConnectionIcons)) {
                Toggle(localization.string(.settingsNetworkWiFiIconForEthernet), isOn: $settings.showsWiFiIconForEthernet)
                Toggle(localization.string(.settingsNetworkWiFiIconForHotspot), isOn: $settings.showsWiFiIconForHotspot)
                Toggle(localization.string(.settingsBluetoothReplaceNetworkIcon), isOn: $settings.replacesNetworkIconWithBluetoothAudio)
            }
            Section(localization.string(.settingsAudioIndicatorStyleTitle)) {
                Picker(localization.string(.settingsAudioIndicatorStyle), selection: $settings.volumeDisplayStyle) {
                    Text(localization.string(.settingsAudioIndicatorStyleDots)).tag(VolumeDisplayStyle.dots)
                    Text(localization.string(.settingsAudioIndicatorStyleArc)).tag(VolumeDisplayStyle.arc)
                }
                Toggle(localization.string(.settingsAudioShowAll), isOn: $settings.alwaysShowsAllOutputDevices)
                Stepper(localization.string(.settingsAudioMaximumVisible) + ": \(settings.maxVisibleOutputDevices)",
                        value: $settings.maxVisibleOutputDevices, in: SettingsStore.outputDeviceLimitRange)
                Toggle(localization.string(.settingsPopupVolumeScroll), isOn: $settings.popupScrollAdjustsVolume)
            }
            Section(localization.string(.settingsPopupOrder)) {
                ForEach(sections) { section in
                    HStack {
                        Toggle(localization.string(section.titleKey), isOn: Binding(
                            get: { settings.enabledPopupSections.contains(section) },
                            set: { enabled in
                                settings.setPopupSection(section, enabled: enabled)
                            }
                        ))
                        Button { move(section, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(section == sections.first)
                            .help(localization.string(.settingsMoveUp))
                            .accessibilityLabel(localization.string(.settingsMoveUp))
                        Button { move(section, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(section == sections.last)
                            .help(localization.string(.settingsMoveDown))
                            .accessibilityLabel(localization.string(.settingsMoveDown))
                    }
                }
                Toggle(localization.string(.settingsBluetoothBatteryLevels), isOn: $settings.showsBluetoothBatteryLevels)
            }
        }
        .formStyle(.grouped)
        .environment(\.layoutDirection, localization.resolvedLanguage.layoutDirection)
        .onAppear { controller.store.setSettingsVisible(true) }
        .onDisappear { controller.store.setSettingsVisible(false) }
    }

    private var sections: [PopupSection] { settings.popupSectionOrder }

    private func move(_ section: PopupSection, by offset: Int) {
        guard let current = sections.firstIndex(of: section), sections.indices.contains(current + offset),
              let source = settings.popupSectionOrder.firstIndex(of: section),
              let target = settings.popupSectionOrder.firstIndex(of: sections[current + offset]) else { return }
        settings.movePopupSections(fromOffsets: IndexSet(integer: source), toOffset: offset > 0 ? target + 1 : target)
    }
}
