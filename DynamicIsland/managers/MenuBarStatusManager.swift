import AppKit
import Combine
import Defaults
import EaveStatus

/// Embeds the status panel while keeping Eave's battery and audio control owners.
@MainActor
final class MenuBarStatusManager {
    static let shared = MenuBarStatusManager()

    private let battery = BatteryStatusViewModel.shared
    private let volume = MediaOutputVolumeViewModel()
    private var cancellables = Set<AnyCancellable>()

    lazy var controller = MenuBarStatusController(
        openSettings: { SettingsWindowController.shared.showWindow() },
        restart: { Self.restart() },
        setVolume: { [weak self] value in self?.volume.setVolume(Float(value)) },
        toggleMute: { [weak self] in self?.volume.toggleMute() },
        selectOutputDevice: { deviceID in
            HUDSuppressionCoordinator.shared.suppressVolumeHUD(for: 1.5)
            AudioRouteManager.shared.select(deviceID: deviceID)
        }
    )

    private lazy var dockIcon = StatusDockIconController(status: controller) {
        applySelectedAppIcon(force: true)
    }

    private init() {}

    private func updateDockIcon(_ enabled: Bool) {
        DockActivationPolicy.shared.setDynamicDockEnabled(enabled)
        dockIcon.setEnabled(enabled)
    }

    func start() {
        guard cancellables.isEmpty else { return }

        controller.setVisible(Defaults[.menubarIcon])
        controller.setUsesTrioIcon(Defaults[.menuBarUsesTrioIcon])
        updateBattery()
        BluetoothAudioManager.shared.requestStatusRefresh = { [weak self] in
            self?.controller.refreshBluetooth()
        }
        controller.bluetoothUpdates
            .sink { BluetoothAudioManager.shared.applyStatus($0) }
            .store(in: &cancellables)
        controller.start()
        DirectDisplayVolumeManager.shared.start(panel: controller)
        updateDockIcon(Defaults[.dynamicDockIcon])

        Defaults.publisher(.dynamicDockIcon, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] change in self?.updateDockIcon(change.newValue) }
            .store(in: &cancellables)

        // @Published emits before the property changes; read the completed update.
        battery.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateBattery() }
            .store(in: &cancellables)

        Defaults.publisher(.menubarIcon, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                guard let self else { return }
                self.updateBattery()
                self.controller.setVisible(change.newValue)
            }
            .store(in: &cancellables)

        Defaults.publisher(.menuBarUsesTrioIcon, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] change in self?.controller.setUsesTrioIcon(change.newValue) }
            .store(in: &cancellables)
    }

    func stop() {
        BluetoothAudioManager.shared.requestStatusRefresh = nil
        cancellables.removeAll()
        DirectDisplayVolumeManager.shared.stop()
        dockIcon.stop()
        DockActivationPolicy.shared.setDynamicDockEnabled(false)
        controller.stop()
    }

    private func updateBattery() {
        controller.updateBattery(Self.batteryState(from: BatteryInfo(
            isPluggedIn: battery.isPluggedIn,
            isCharging: battery.isCharging,
            currentCapacity: battery.levelBattery,
            maxCapacity: battery.maxCapacity,
            isInLowPowerMode: battery.isInLowPowerMode,
            timeToFullCharge: battery.timeToFullCharge
        )))
    }

    static func batteryState(from info: BatteryInfo) -> MenuBarBatteryState {
        let isPresent = info.maxCapacity.isFinite && info.maxCapacity > 0
        let percentage: Int? = isPresent && info.currentCapacity.isFinite
            ? Int((max(0, min(1, info.currentCapacity / info.maxCapacity)) * 100).rounded())
            : nil
        return MenuBarBatteryState(
            rawPercentage: percentage,
            isPresent: isPresent,
            isCharging: info.isCharging,
            isCharged: percentage == 100 && !info.isCharging,
            timeToFullChargeMinutes: info.timeToFullCharge > 0 ? info.timeToFullCharge : nil,
            isLowPowerMode: info.isInLowPowerMode,
            isConnectedToPower: info.isPluggedIn
        )
    }

    private static func restart() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            workspace.openApplication(at: appURL, configuration: configuration)
        }
        NSApplication.shared.terminate(nil)
    }
}
