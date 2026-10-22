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
    @ObservedObject private var inputSourceController: InputSourceController
    @ObservedObject private var helper = PrivilegedHelperManager.shared

    public init(controller: MenuBarStatusController) {
        self.controller = controller
        _statusStore = ObservedObject(wrappedValue: controller.store)
        _settings = ObservedObject(wrappedValue: controller.settings)
        _localization = ObservedObject(wrappedValue: controller.localization)
        _inputSourceController = ObservedObject(wrappedValue: controller.inputSourceController)
    }

    public var body: some View {
        Form {
            Section(localization.string(.settingsIconSize)) {
                HStack {
                    HStack(spacing: 12) {
                        Label(localization.string(.settingsIconSize), systemImage: "arrow.left.and.right").accessibilityHidden(true)
                        Spacer(minLength: 12)
                        HStack(spacing: 6) {
                            Slider(value: $settings.iconSize, in: SettingsStore.iconSizeRange, step: 1) {
                                Label(localization.string(.settingsIconSize), systemImage: "arrow.left.and.right")
                            }
                            .labelsHidden()
                            Text("\(Int(settings.iconSize)) pt")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                        .padding(.horizontal, 10)
                        .frame(width: 190, height: 34)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }

                }
                HStack(spacing: 12) {
                    Label(localization.string(.settingsRingStrokeStyle), systemImage: "circle.lefthalf.filled").accessibilityHidden(true)
                    Spacer(minLength: 12)
                    Picker(selection: $settings.ringStrokeStyle) {
                        Text(localization.string(.settingsRingStrokeStyleLight)).tag(RingStrokeStyle.light)
                        Text(localization.string(.settingsRingStrokeStyleRegular)).tag(RingStrokeStyle.regular)
                        Text(localization.string(.settingsRingStrokeStyleBold)).tag(RingStrokeStyle.bold)
                    } label: {
                        Label(localization.string(.settingsRingStrokeStyle), systemImage: "circle.lefthalf.filled")
                    }
                        .labelsHidden()
                }
            }
            Section(localization.string(.settingsBatteryTitle)) {
                lowPowerModeSettings
                Toggle(localization.string(.settingsBatteryShowPercentage), systemImage: "battery.100", isOn: $settings.showsBatteryPercentage)
                Toggle(localization.string(.settingsBatteryShowChargingIndicator), systemImage: "battery.100", isOn: $settings.showsChargingIndicator)
                Toggle(localization.string(.settingsBatteryChargingEffect), systemImage: "battery.100", isOn: $settings.showsChargingEffect)
                Toggle(localization.string(.settingsBatteryPercentageWhenConnected), systemImage: "battery.100", isOn: $settings.showsPercentageWhenConnected)
                Toggle(localization.string(.settingsBatteryStatusColors), systemImage: "battery.100", isOn: $settings.usesBatteryStatusColors)
                HStack(spacing: 12) {
                    Label(localization.string(.settingsBatteryCriticalThreshold), systemImage: "battery.25").accessibilityHidden(true)
                    Spacer(minLength: 12)
                    HStack(spacing: 6) {
                        Slider(value: $settings.batteryCriticalThreshold, in: SettingsStore.batteryCriticalThresholdRange, step: 1) {
                            Label(localization.string(.settingsBatteryCriticalThreshold), systemImage: "battery.25")
                        }
                        .labelsHidden()
                        Text("\(Int(settings.batteryCriticalThreshold))%")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .padding(.horizontal, 10)
                    .frame(width: 190, height: 34)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                HStack {
                    HStack(spacing: 12) {
                        Label(localization.string(.settingsBatteryFullThreshold), systemImage: "battery.100").accessibilityHidden(true)
                        Spacer(minLength: 12)
                        HStack(spacing: 6) {
                            Slider(value: $settings.batteryFullThreshold, in: SettingsStore.batteryFullThresholdRange, step: 1) {
                                Label(localization.string(.settingsBatteryFullThreshold), systemImage: "battery.100")
                            }
                            .labelsHidden()
                            Text("\(Int(settings.batteryFullThreshold))%")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                        .padding(.horizontal, 10)
                        .frame(width: 190, height: 34)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }

                }
                Text(localization.string(.settingsBatteryFullThresholdDescription)).font(.caption).foregroundStyle(.secondary)
                if settings.canReadSystemChargeLimit {
                    Button(localization.string(.settingsBatteryFullThresholdUseChargeLimit)) {
                        settings.applySystemChargeLimit()
                    }
                }
            }
            Section(localization.string(.settingsNetworkConnectionIcons)) {
                LocationSettingsPermissionRow(message: "Optional. Allows displaying the current Wi-Fi network name.")
                HStack(spacing: 12) {
                    Label(localization.string(.settingsNetworkCenterSource), systemImage: "wifi").accessibilityHidden(true)
                    Spacer(minLength: 12)
                    Picker(selection: $settings.connectionCenterSource) {
                        Text(localization.string(.settingsNetworkCenterSourceAutomatic)).tag(ConnectionCenterSource.automatic)
                        Text(localization.string(.settingsNetworkCenterSourceInputSource)).tag(ConnectionCenterSource.inputSource)
                    } label: {
                        Label(localization.string(.settingsNetworkCenterSource), systemImage: "wifi")
                    }
                        .labelsHidden()
                }
                if settings.connectionCenterSource == .inputSource {
                    Toggle(localization.string(.settingsNetworkCenterSourceNetworkWarnings), systemImage: "wifi", isOn: $settings.prioritizesNetworkErrorsOverInputSource)
                }
                Toggle(localization.string(.settingsPopupOrderInputSource), systemImage: "slider.horizontal.3", isOn: Binding(
                    get: { settings.enabledPopupSections.contains(.inputSource) },
                    set: { settings.setPopupSection(.inputSource, enabled: $0) }
                ))
                Toggle(localization.string(.settingsNetworkShowLocalIP), systemImage: "wifi", isOn: $settings.showsLocalIPAddress)
                Toggle(localization.string(.settingsNetworkWiFiIconForEthernet), systemImage: "wifi", isOn: $settings.showsWiFiIconForEthernet)
                Toggle(localization.string(.settingsNetworkWiFiIconForHotspot), systemImage: "wifi", isOn: $settings.showsWiFiIconForHotspot)
            }
            BluetoothSettingsSection(controller: controller)
            Section(localization.string(.settingsAudioIndicatorStyleTitle)) {
                HStack(spacing: 12) {
                    Label(localization.string(.settingsAudioIndicatorStyle), systemImage: "speaker.wave.2").accessibilityHidden(true)
                    Spacer(minLength: 12)
                    Picker(selection: $settings.volumeDisplayStyle) {
                        Text(localization.string(.settingsAudioIndicatorStyleDots)).tag(VolumeDisplayStyle.dots)
                        Text(localization.string(.settingsAudioIndicatorStyleArc)).tag(VolumeDisplayStyle.arc)
                    } label: {
                        Label(localization.string(.settingsAudioIndicatorStyle), systemImage: "speaker.wave.2")
                    }
                        .labelsHidden()
                }
                Toggle(localization.string(.settingsAudioShowAll), systemImage: "speaker.wave.2", isOn: $settings.alwaysShowsAllOutputDevices)
                Stepper(value: $settings.maxVisibleOutputDevices, in: SettingsStore.outputDeviceLimitRange) {
                    HStack {
                        Label(localization.string(.settingsAudioMaximumVisible), systemImage: "list.bullet")
                        Spacer()
                        Text("\(settings.maxVisibleOutputDevices)").monospacedDigit()
                    }
                }
                Toggle(localization.string(.settingsPopupVolumeScroll), systemImage: "speaker.wave.2", isOn: $settings.popupScrollAdjustsVolume)
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
            inputs: IconPresentationResourceResolver.inputs(snapshot: statusStore.snapshot, inputSource: inputSourceController.selectedDescriptor),
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

    private var lowPowerModeSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(localization.string(.lowPowerModeControl), systemImage: "slider.horizontal.3", isOn: helper.isEnabledBinding)
                .disabled(!helper.isAvailable)
            Text(localization.string(.lowPowerModeControlDescription))
                .font(.caption).foregroundStyle(.secondary)
            if helper.isAvailable {
                Button(localization.string(helper.requiresApproval && !helper.isReady
                    ? .lowPowerModeRequiresApproval : .lowPowerModeOpenLoginItems)) {
                    helper.openLoginItemsSettings()
                }
                .font(.caption)
                if helper.isEnabled {
                    Text(localization.string(helper.isReady ? .lowPowerModeHelperReady : .lowPowerModeHelperUnavailable))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(localization.string(.lowPowerModeSignedBuildRequired))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = helper.lastErrorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

}
