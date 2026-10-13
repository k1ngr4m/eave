import AppKit
import SwiftUI

@MainActor
struct BluetoothSettingsSection: View {
    @State private var previewIsDark = true
    private let controller: MenuBarStatusController
    @ObservedObject private var store: SettingsStore
    @ObservedObject private var statusStore: SystemStatusStore
    @ObservedObject private var bluetoothDevices: BluetoothDeviceController
    @ObservedObject private var appleDeviceDiscovery: AppleDeviceDiscoveryController
    @ObservedObject private var localization: Localization

    init(controller: MenuBarStatusController) {
        self.controller = controller
        _store = ObservedObject(wrappedValue: controller.settings)
        _statusStore = ObservedObject(wrappedValue: controller.store)
        _bluetoothDevices = ObservedObject(wrappedValue: controller.store.bluetoothDevices)
        _appleDeviceDiscovery = ObservedObject(wrappedValue: controller.store.appleDeviceDiscovery)
        _localization = ObservedObject(wrappedValue: controller.localization)
    }

    var body: some View {
        Group {
            bluetoothPermissionBanner
            iconSettings
                .onAppear { claimDeviceSurface() }
                .task(id: bluetoothDevices.authorization == .allowed) {
                    if bluetoothDevices.authorization == .allowed { claimDeviceSurface() }
                    else { bluetoothDevices.releaseVisibleSurface(Self.orderSurfaceToken) }
                }
                .onDisappear { bluetoothDevices.releaseVisibleSurface(Self.orderSurfaceToken) }
            MobileBatterySettingsSection(controller: controller)
            previewSettings
            Section(localization.string(.settingsBluetoothDeviceListGroup)) {
                Toggle(localization.string(.settingsBluetoothShowDeviceList), isOn: $store.showsBluetoothDeviceList)
                    .help(localization.string(.settingsBluetoothShowDeviceListDescription))
                if store.showsBluetoothDeviceList {
                    Stepper(value: $store.maxVisibleBluetoothDevices, in: SettingsStore.bluetoothDeviceLimitRange) {
                        HStack {
                            Text(localization.string(.settingsBluetoothMaximumVisible))
                            Spacer()
                            Text("\(store.maxVisibleBluetoothDevices)").monospacedDigit()
                        }
                    }
                }
            }
            deviceOrderGroup
        }
    }

    private static let orderSurfaceToken = "bluetooth.settings.order.surface"

    private var iconSettings: some View {
        Section(localization.string(.settingsBluetoothTitle)) {
            iconPreview
            Toggle(localization.string(.settingsBluetoothShowInStatusPanel), isOn: showInStatusPanelBinding)
                .help(localization.string(.settingsBluetoothShowInStatusPanelDescription))
            HStack {
                Slider(value: $store.bluetoothSymbolScale, in: SettingsStore.bluetoothSymbolScaleRange, step: 0.05) {
                    Text(localization.string(.settingsBluetoothSymbolScale))
                }
                Text("\(Int(round(store.bluetoothSymbolScale * 100)))%")
                    .monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Toggle(localization.string(.settingsBluetoothReplaceNetworkIcon), isOn: $store.replacesNetworkIconWithBluetoothAudio)
                .help(localization.string(.settingsBluetoothReplaceNetworkIconDescription))
            if store.replacesNetworkIconWithBluetoothAudio {
                Picker(localization.string(.settingsBluetoothNetworkIconSourceGroup), selection: networkIconSourceBinding) {
                    ForEach(sourceOptions) { option in
                        Label(option.title ?? localization.string(.settingsBluetoothNetworkIconSourceAudio), systemImage: option.symbolName)
                            .tag(option.source)
                    }
                }
                .accessibilityIdentifier("bluetooth.networkIconSource")
                if BluetoothNetworkIconSource.shouldShowAudioIconChoice(
                    replacingNetworkIcon: store.replacesNetworkIconWithBluetoothAudio, selectedSource: selectedOption.source
                ) {
                    Picker(localization.string(.settingsBluetoothIconChoice), selection: Binding(
                        get: { store.bluetoothAudioIconChoice }, set: { store.bluetoothAudioIconChoice = $0 }
                    )) {
                        ForEach(IconPresentationResourceResolver.availableBluetoothAudioIconChoices) { choice in
                            Label(choice.displayName(using: localization), systemImage: choice.symbolName ?? "arrow.clockwise")
                                .tag(choice)
                        }
                    }
                    .accessibilityIdentifier("bluetooth.audioIconChoice")
                }
                if !sourceOptionsOffersDevices {
                    Text(localization.string(.settingsBluetoothNetworkIconSourceDevicesEmpty))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle(localization.string(.settingsBluetoothVolumeColor), isOn: $store.usesBluetoothAudioVolumeColor)
                .help(localization.string(.settingsBluetoothVolumeColorDescription))
            Toggle(localization.string(.settingsBluetoothNetworkErrorPriority), isOn: $store.prioritizesNetworkErrorsOverBluetoothAudio)
                .help(localization.string(.settingsBluetoothNetworkErrorPriorityDescription))
            Toggle(localization.string(.settingsBluetoothBatteryLevels), isOn: $store.showsBluetoothBatteryLevels)
                .help(localization.string(.settingsBluetoothBatteryLevelsDescription))
        }
    }

    private var iconPreview: some View {
        let scene = IconPresentationMapper.scene(
            inputs: IconPresentationResourceResolver.inputs(snapshot: statusStore.snapshot),
            configuration: IconPresentationConfiguration(
                battery: store.batteryIconOptions, connection: store.connectionIconOptions,
                volume: store.volumeIconOptions, bluetooth: store.bluetoothAudioIconOptions
            )
        )
        return HStack {
            Text(localization.string(.settingsPreviewHint)).font(.caption)
            Spacer()
            if let image = StatusIconRenderer.image(
                scene: scene, size: store.iconSize, scale: NSScreen.main?.backingScaleFactor ?? 2,
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

    private var previewSettings: some View {
        Section(localization.string(.settingsBluetoothListeningModePreview)) {
            Toggle(localization.string(.settingsBluetoothListeningModePreview), isOn: $store.previewsBluetoothListeningMode)
                .help(localization.string(.settingsBluetoothListeningModePreviewDescription))
            if store.previewsBluetoothListeningMode {
                TextField(localization.string(.settingsBluetoothListeningModePreviewDeviceName), text: $store.bluetoothListeningModePreviewDeviceName)
                Stepper(value: $store.bluetoothListeningModePreviewDeviceCount, in: SettingsStore.bluetoothListeningModePreviewDeviceCountRange) {
                    HStack {
                        Text(localization.string(.settingsBluetoothListeningModePreviewDeviceCount))
                        Spacer()
                        Text("\(store.bluetoothListeningModePreviewDeviceCount)").monospacedDigit()
                    }
                }
                Picker(localization.string(.settingsBluetoothListeningModePreviewLanguage), selection: $store.bluetoothListeningModePreviewLanguage) {
                    Text(localization.string(.settingsLanguageFollowSystem)).tag("")
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeName).tag(language.rawValue)
                    }
                }
            }
        }
    }

    private var networkIconSourceBinding: Binding<BluetoothNetworkIconSource> {
        Binding(
            get: { selectedOption.source },
            set: { source in
                switch source {
                case .audioDevices:
                    store.setBluetoothNetworkIconDevice(address: nil, symbolName: nil)
                case let .device(address):
                    guard let option = sourceOptions.first(where: { $0.source == source }) else {
                        return
                    }
                    store.setBluetoothNetworkIconDevice(
                        address: address,
                        symbolName: option.symbolName
                    )
                }
            }
        )
    }

    /// The menu's contents, and the row's own glyph with them.
    private var sourceOptions: [BluetoothNetworkIconSourceOption] {
        BluetoothNetworkIconSourceOption.options(
            devices: bluetoothDevices.devices,
            order: store.bluetoothDeviceOrder
        )
    }

    /// Whether the menu has anything to offer besides the audio entry. When it
    /// does not, the pane says why — a grant that has not been given yet and a
    /// Mac with nothing paired both leave the menu with one row, and without
    /// the hint that reads as a broken menu.
    private var sourceOptionsOffersDevices: Bool {
        BluetoothNetworkIconSourceOption.listsDevices(devices: bluetoothDevices.devices)
    }

    /// The choice the menu shows as selected. A saved address whose device is
    /// gone from the paired list falls back to the audio entry, which is the
    /// only entry the menu still offers.
    private var selectedOption: BluetoothNetworkIconSourceOption {
        let options = sourceOptions
        guard let address = store.bluetoothNetworkIconDeviceAddress,
              let picked = options.first(where: { $0.source == .device(address: address) })
        else {
            return options[0]
        }
        return picked
    }

    /// The pane shows paired devices, so it needs the same monitor the popover
    /// uses — otherwise a fresh launch that opens Settings shows "No paired
    /// devices available" while devices are paired, and drag-to-reorder is
    /// unreachable. Only an app that already holds the grant may activate the
    /// monitor, because starting it is what raises the system prompt; the gate
    /// keeps this pane from ever prompting on its own. The claim stops the
    /// safety-net poll when the pane goes away, but it never turns the enabled
    /// flag off: the panel toggle and the popover own that.
    private func claimDeviceSurface() {
        guard BluetoothPanelActivation.shouldActivate(
            authorization: bluetoothDevices.authorization
        ) else { return }
        bluetoothDevices.activate()
        bluetoothDevices.holdVisibleSurface(Self.orderSurfaceToken)
    }

    private var deviceOrderGroup: some View {
        Section {
            Group {
                if orderedBluetoothDevices.isEmpty {
                    Label(
                        localization.string(.settingsBluetoothOrderEmpty),
                        systemImage: "questionmark.circle"
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                } else {
                    List {
                        ForEach(orderedBluetoothDisplayRows, id: \.device.id) { displayRow in
                            let device = displayRow.device
                            let isHidden = displayRow.sourceIDs.allSatisfy {
                                store.hiddenBluetoothDeviceAddresses.contains(BluetoothDeviceIdentity.preferenceKey($0))
                            }
                            HStack(spacing: 10) {
                                Image(systemName: BluetoothDeviceRowIcon.symbolName(for: device))
                                    .foregroundStyle(device.isConnected ? Color.accentColor : Color.secondary)
                                    .frame(width: 18)

                                Text(device.name)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    for sourceID in displayRow.sourceIDs {
                                        store.setBluetoothDeviceHidden(sourceID, hidden: !isHidden)
                                    }
                                } label: {
                                    Image(systemName: isHidden ? "eye.slash" : "eye")
                                        .font(.system(size: 13))
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                                .help(isHidden
                                      ? localization.string(.settingsBluetoothShowDevice)
                                      : localization.string(.settingsBluetoothHideDevice))
                                .accessibilityLabel(isHidden
                                      ? localization.string(.settingsBluetoothShowDevice)
                                      : localization.string(.settingsBluetoothHideDevice))
                                .frame(width: 26)

                                Image(systemName: "line.3.horizontal")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                                    .frame(width: 18)
                            }
                            .frame(height: 30)
                            .opacity(isHidden ? 0.45 : 1)
                        }
                        .onMove { source, destination in
                            store.moveBluetoothDevices(
                                fromOffsets: source,
                                toOffset: destination,
                                in: orderedBluetoothDisplayRows.map(\.device)
                            )
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .frame(height: orderListHeight)
                }
            }
        } header: {
            Text(localization.string(.settingsBluetoothOrderTitle))
        } footer: {
            Text(localization.string(.settingsBluetoothOrderFootnote))
        }
    }

    /// Shown at the top of the pane whenever Bluetooth access is not granted, so
    /// the user sees why the device list is empty and can resolve it from here
    /// instead of hunting for a prompt. `.notDetermined` offers to raise the
    /// system prompt; `.denied`/`.restricted` send the user to the pane that
    /// gives a refused grant back. Hidden once `.allowed`.
    @ViewBuilder
    private var bluetoothPermissionBanner: some View {
        switch bluetoothDevices.authorization {
        case .allowed:
            EmptyView()
        case .notDetermined:
            permissionNotice(
                description: .settingsBluetoothPermissionNotDeterminedDescription,
                buttonKey: .bluetoothActionRequestAuthorization,
                action: { statusStore.requestBluetoothAuthorization() }
            )
        case .denied, .restricted:
            permissionNotice(
                description: .settingsBluetoothPermissionDeniedDescription,
                buttonKey: .bluetoothActionOpenPermissionSettings,
                action: { statusStore.openBluetoothPermissionSettings() }
            )
        }
    }

    private func permissionNotice(
        description: LocalizationKey,
        buttonKey: LocalizationKey,
        action: @escaping () -> Void
    ) -> some View {
        Section {
            LabeledContent {
                Button(localization.string(buttonKey), action: action)
            } label: {
                Label(localization.string(.settingsBluetoothPermissionRequired), systemImage: "exclamationmark.triangle.fill")
                Text(localization.string(description)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The order list shows the same sequence the panel renders, so dragging in
    /// Settings moves the row the user is looking at. Read from the observed
    /// controller, not the store, so a read that lands later repaints it.
    private var sourceBluetoothDevices: [BluetoothDevice] {
        let trustedDevices = store.showsAppleDevicesAndBattery
            ? AppleDeviceCatalog.candidates(trusted: store.trustedAppleDeviceMetadata + appleDeviceDiscovery.candidates)
                .map { candidate in
                    BluetoothDevice(
                        id: candidate.id.rowID,
                        name: candidate.name,
                        kind: BluetoothMobileDeviceModel.kind(forModel: candidate.model) ?? .unknown,
                        isConnected: false,
                        appleMobileModel: candidate.model,
                        isReadOverTheAir: true
                    )
                }
            : []
        let bleDevices = nearbySettingsCandidates.map { candidate in
            let selection = store.nearbyBLESelections.first { $0.id == candidate.id }
            return BluetoothDevice(
                id: BluetoothDeviceIdentity.bleRowID(candidate.id),
                name: candidate.name,
                kind: BluetoothMobileDeviceModel.kind(forModel: selection?.model) ?? .unknown,
                isConnected: false,
                appleMobileModel: selection?.model,
                isReadOverTheAir: true
            )
        }
        return bluetoothDevices.devices.filter { !$0.isUnpairedGhost } + trustedDevices + bleDevices
    }

    private var orderedBluetoothDevices: [BluetoothDevice] {
        orderedBluetoothDisplayRows.map(\.device)
    }

    private var orderedBluetoothDisplayRows: [BluetoothDisplayRow] {
        BluetoothDeviceListPresentation.settingsDisplayRows(
            sourceBluetoothDevices,
            order: store.bluetoothDeviceOrder,
            options: store.bluetoothDeviceListOptions
        )
    }

    private var nearbySettingsCandidates: [NearbyBLEDeviceCandidate] {
        guard store.showsAppleDevicesAndBattery, bluetoothDevices.authorization == .allowed else { return [] }
        return NearbyBLEDeviceCatalog.settingsCandidates(selections: store.nearbyBLESelections)
    }

    /// Sized for every row so no device is clipped; the enclosing Form scrolls
    /// when the paired list is long.
    private var orderListHeight: CGFloat {
        max(CGFloat(orderedBluetoothDevices.count) * 32 + 12, 48)
    }

    private var showInStatusPanelBinding: Binding<Bool> {
        Binding(
            get: { store.enabledPopupSections.contains(.bluetooth) },
            set: { enabled in
                let wasEnabled = store.enabledPopupSections.contains(.bluetooth)
                store.setPopupSection(.bluetooth, enabled: enabled)

                guard enabled != wasEnabled else { return }
                if enabled {
                    NSApp.activate(ignoringOtherApps: true)
                }
                statusStore.setBluetoothEnabled(enabled)
            }
        )
    }
}
