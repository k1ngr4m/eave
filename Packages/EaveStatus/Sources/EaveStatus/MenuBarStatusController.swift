import AppKit
import Combine

/// Eave supplies its existing power-source readings; the embedded status panel owns no battery monitor.
public struct MenuBarBatteryState: Equatable, Sendable {
    public let rawPercentage: Int?
    public let isPresent: Bool
    public let isCharging: Bool
    public let isCharged: Bool
    public let timeToFullChargeMinutes: Int?
    public let isLowPowerMode: Bool
    public let isConnectedToPower: Bool

    public init(rawPercentage: Int?, isPresent: Bool, isCharging: Bool, isCharged: Bool = false,
                timeToFullChargeMinutes: Int? = nil, isLowPowerMode: Bool, isConnectedToPower: Bool) {
        self.rawPercentage = rawPercentage
        self.isPresent = isPresent
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.timeToFullChargeMinutes = timeToFullChargeMinutes
        self.isLowPowerMode = isLowPowerMode
        self.isConnectedToPower = isConnectedToPower
    }

    var status: BatteryStatus {
        BatteryStatus(rawPercentage: rawPercentage, isPresent: isPresent, isCharging: isCharging,
                      isCharged: isCharged, timeToFullChargeMinutes: timeToFullChargeMinutes,
                      isLowPowerMode: isLowPowerMode, isConnectedToPower: isConnectedToPower)
    }
}

@MainActor
final class HostBatteryMonitor: BatteryMonitoring {
    let updates: AsyncStream<BatteryStatus>
    private let continuation: AsyncStream<BatteryStatus>.Continuation
    private var current = BatteryStatus.placeholder

    init() { (updates, continuation) = MonitorStream.make(of: BatteryStatus.self) }
    func update(_ state: MenuBarBatteryState) { current = state.status; refresh() }
    func start() { refresh() }
    func refresh() { continuation.yield(current) }
    func recover() { refresh() }
    func stop() { continuation.finish() }
}

/// Output writes always cross this boundary into Eave's existing HUD-aware controls.
@MainActor
final class HostAudioOutputController: AudioOutputControlling {
    private let volume: (Double) -> Void
    private let mute: () -> Void
    private let select: (UInt32) -> Void

    init(setVolume: @escaping (Double) -> Void, toggleMute: @escaping () -> Void,
         selectOutputDevice: @escaping (UInt32) -> Void) {
        volume = setVolume; mute = toggleMute; select = selectOutputDevice
    }

    func setVolume(_ scalar: Double) -> Bool {
        guard scalar.isFinite else { return false }
        volume(min(1, max(0, scalar)))
        return true
    }
    func toggleMute() -> Bool { mute(); return true }
    func selectOutputDevice(_ id: UInt32) -> Bool {
        guard id != 0 else { return false }
        select(id)
        return true
    }
}

@MainActor
public final class MenuBarStatusController {
    let settings: SettingsStore
    let store: SystemStatusStore
    let localization: Localization
    private let battery = HostBatteryMonitor()
    let iconPresentation: IconPresentationViewModel
    private let clock = ChargingEffectClock()
    private let motion = ChargingEffectMotionMonitor()
    private let openSettings: () -> Void
    private let restart: () -> Void
    private var statusBar: StatusBarController?
    private var subscriptions = Set<AnyCancellable>()
    private var isVisible = true
    private var usesTrioIcon = true
    private var stopped = false

    public init(openSettings: @escaping () -> Void, restart: @escaping () -> Void,
                setVolume: @escaping (Double) -> Void, toggleMute: @escaping () -> Void,
                selectOutputDevice: @escaping (UInt32) -> Void) {
        self.openSettings = openSettings
        self.restart = restart
        let defaults = UserDefaults(suiteName: (Bundle.main.bundleIdentifier ?? "Eave") + ".MenuBarStatus")!
        let settings = SettingsStore(defaults: defaults)
        self.settings = settings
        settings.introduceAudioInputSection(defaults: defaults)
        settings.showsNearbyBluetoothBatteryDevices = false
        settings.previewsBluetoothListeningMode = false
        let localization = Localization(defaults: defaults, preferredLanguages: Bundle.main.preferredLocalizations)
        localization.setPreference(.system)
        self.localization = localization
        let store = SystemStatusStore(
            batteryMonitor: battery,
            wifiMonitor: WiFiMonitor(keepsNameAvailable: true),
            connectionMonitor: NetworkConnectionMonitor(),
            vpnMonitor: VPNMonitor(),
            volumeMonitor: VolumeMonitor(outputController: HostAudioOutputController(
                setVolume: setVolume, toggleMute: toggleMute, selectOutputDevice: selectOutputDevice
            )),
            inputMonitor: AudioInputMonitor(),
            volumeFeedback: nil,
            refreshInterval: settings.refreshInterval,
            bluetoothDevices: BluetoothDeviceController(
                accessoryBatteryReader: PmsetAccessoryBatteryWorker(),
                connectedBatteryFallback: ConnectedBluetoothBatteryFallback(),
                connectionEvents: IOBluetoothConnectionEventMonitor(),
                accessoryBatteryEvents: AccessoryPowerNotifyEventMonitor()
            )
        )
        self.store = store
        store.bindInputSettings(settings)
        store.bindMobileBatterySettings(settings)
        let appearance = StatusIconAppearance(settings: settings)
        iconPresentation = IconPresentationViewModel(
            snapshot: store.snapshot,
            settings: IconPresentationSettings(
                configuration: IconPresentationConfiguration(
                    battery: appearance.batteryOptions, connection: appearance.connectionOptions,
                    volume: appearance.volumeOptions, bluetooth: appearance.bluetoothAudioOptions
                ),
                menuBarSize: appearance.iconSize,
                testsChargingEffect: false
            ),
            snapshots: store.$snapshot.eraseToAnyPublisher(),
            preferences: settings.iconPresentationPublisher,
            resolveInputs: { IconPresentationResourceResolver.inputs(snapshot: $0) }
        )
    }

    public func start() {
        guard statusBar == nil, !stopped else { return }
        iconPresentation.start()
        statusBar = StatusBarController(
            store: store, settings: settings, iconPresentation: iconPresentation, localization: localization,
            isVisible: isVisible, openSettings: openSettings,
            quitAction: { NSApplication.shared.terminate(nil) }, restartAction: restart,
            chargingEffectClock: clock
        )
        statusBar?.setUsesTrioIcon(usesTrioIcon)
        motion.onChange = { [weak self] _ in self?.updateChargingEffect() }
        motion.start()
        Publishers.CombineLatest3(store.$snapshot.map(\.battery).removeDuplicates(),
                                  settings.$showsChargingEffect.removeDuplicates(),
                                  store.$isDisplayAsleep.removeDuplicates())
            .sink { [weak self] battery, enabled, asleep in
                guard let self else { return }
                clock.update(battery: battery, enabled: enabled && isVisible && usesTrioIcon, reduceMotion: motion.shouldReduceMotion, displayAsleep: asleep)
            }
            .store(in: &subscriptions)
        store.bluetoothDevices.setHostMonitoringEnabled(true)
        store.start()
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        statusBar?.stop()
        statusBar = nil
        subscriptions.removeAll()
        motion.onChange = nil
        motion.stop()
        clock.stop()
        store.bluetoothDevices.setHostMonitoringEnabled(false)
        store.stop()
        iconPresentation.stop()
    }

    public func updateBattery(_ state: MenuBarBatteryState) { battery.update(state) }

    public var panelVisibilityPublisher: AnyPublisher<Bool, Never> {
        store.$isPopoverVisible.removeDuplicates().eraseToAnyPublisher()
    }

    public var networkPublisher: AnyPublisher<MenuBarNetworkState, Never> {
        store.$networkState.removeDuplicates().eraseToAnyPublisher()
    }

    public var bluetoothUpdates: AnyPublisher<MenuBarBluetoothState, Never> {
        store.bluetoothDevices.hostStatusPublisher
    }

    public func refreshBluetooth() { store.bluetoothDevices.refresh() }

    /// An explicit anchor also works when the menu bar icon is hidden.
    @discardableResult
    public func showPanel(relativeTo view: NSView) -> Bool {
        guard !stopped else { return false }
        return statusBar?.showPopover(relativeTo: view) ?? false
    }

    public func closePanel() { statusBar?.closePopover() }
    public func setVisible(_ visible: Bool) {
        isVisible = visible
        statusBar?.setVisible(visible)
        updateChargingEffect()
    }
    public func setUsesTrioIcon(_ enabled: Bool) {
        usesTrioIcon = enabled
        statusBar?.setUsesTrioIcon(enabled)
        updateChargingEffect()
    }
    public func setLanguage(identifier: String?) {
        localization.setPreference(identifier.map { .language(AppLanguage.resolved(preferredLanguages: [$0])) } ?? .system)
    }

    private func updateChargingEffect() {
        clock.update(battery: store.snapshot.battery, enabled: statusBar != nil && settings.showsChargingEffect && isVisible && usesTrioIcon,
                     reduceMotion: motion.shouldReduceMotion, displayAsleep: store.isDisplayAsleep)
    }
}
