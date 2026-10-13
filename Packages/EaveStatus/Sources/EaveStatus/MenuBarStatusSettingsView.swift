import AppKit
import SwiftUI

/// Embedded in Eave's settings window; application identity and startup remain host-owned.
@MainActor
public struct MenuBarStatusSettingsView: View {
    @State private var previewIsDark = true
    @ObservedObject private var statusStore: SystemStatusStore
    private let controller: MenuBarStatusController
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var localization: Localization

    public init(controller: MenuBarStatusController) {
        self.controller = controller
        _statusStore = ObservedObject(wrappedValue: controller.store)
        _settings = ObservedObject(wrappedValue: controller.settings)
        _localization = ObservedObject(wrappedValue: controller.localization)
    }

    public var body: some View {
        Form {
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
            }
            BluetoothSettingsSection(controller: controller)
            Section(localization.string(.settingsAudioIndicatorStyleTitle)) {
                Picker(localization.string(.settingsAudioIndicatorStyle), selection: $settings.volumeDisplayStyle) {
                    Text(localization.string(.settingsAudioIndicatorStyleDots)).tag(VolumeDisplayStyle.dots)
                    Text(localization.string(.settingsAudioIndicatorStyleArc)).tag(VolumeDisplayStyle.arc)
                }
                Toggle(localization.string(.settingsAudioShowAll), isOn: $settings.alwaysShowsAllOutputDevices)
                Stepper(value: $settings.maxVisibleOutputDevices, in: SettingsStore.outputDeviceLimitRange) {
                    HStack {
                        Text(localization.string(.settingsAudioMaximumVisible))
                        Spacer()
                        Text("\(settings.maxVisibleOutputDevices)").monospacedDigit()
                    }
                }
                Toggle(localization.string(.settingsPopupVolumeScroll), isOn: $settings.popupScrollAdjustsVolume)
            }
            Section(localization.string(.settingsPopupOrder)) {
                List {
                    ForEach(settings.popupSectionOrder) { section in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { settings.enabledPopupSections.contains(section) },
                                set: { settings.setPopupSection(section, enabled: $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .accessibilityLabel(localization.string(section.titleKey))

                            Group {
                                if section == .bluetooth {
                                    BluetoothIcon(size: 16)
                                } else {
                                    Image(systemName: section.systemImage)
                                        .font(.system(size: 13))
                                }
                            }
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                            .accessibilityHidden(true)

                            Text(localization.string(section.titleKey))
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 3)
                    }
                    .onMove { source, destination in
                        settings.movePopupSections(fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .frame(height: CGFloat(settings.popupSectionOrder.count) * 32 + 12)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            iconPreview
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .environment(\.layoutDirection, localization.resolvedLanguage.layoutDirection)
        .onAppear { controller.store.setSettingsVisible(true) }
        .onDisappear { controller.store.setSettingsVisible(false) }
    }

    private var iconPreview: some View {
        let scene = IconPresentationMapper.scene(
            inputs: IconPresentationResourceResolver.inputs(snapshot: statusStore.snapshot),
            configuration: IconPresentationConfiguration(
                battery: settings.batteryIconOptions, connection: settings.connectionIconOptions,
                volume: settings.volumeIconOptions, bluetooth: settings.bluetoothAudioIconOptions
            )
        )
        return HStack {
            Text(localization.string(.settingsPreviewHint)).font(.caption)
            Spacer()
            if let image = StatusIconRenderer.image(
                scene: scene, size: settings.iconSize, scale: NSScreen.main?.backingScaleFactor ?? 2,
                appearance: NSAppearance(named: previewIsDark ? .darkAqua : .aqua)
            ) {
                Image(nsImage: image).accessibilityHidden(true)
            }
            Button {
                previewIsDark.toggle()
            } label: {
                Label(localization.string(previewIsDark ? .settingsPreviewDark : .settingsPreviewLight),
                      systemImage: previewIsDark ? "moon.fill" : "sun.max.fill")
            }
            .buttonStyle(.plain)
            .help(localization.string(.settingsPreviewToggleHelp))
        }
        .padding(12)
        .foregroundStyle(previewIsDark ? Color.white : Color.black)
        .background(previewIsDark ? Color.black.opacity(0.8) : Color.white, in: RoundedRectangle(cornerRadius: 8))
    }

}
