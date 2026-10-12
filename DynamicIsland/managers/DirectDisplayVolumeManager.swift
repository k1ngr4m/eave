import AppKit
import Combine
import Defaults
import EaveStatus

/// One fallback behind Eave's existing volume controller, shared by keys, HUDs and panels.
@MainActor
final class DirectDisplayVolumeManager {
    static let shared = DirectDisplayVolumeManager()
    private let display = DirectDisplayVolumeController()
    private let volume = SystemVolumeController.shared
    private weak var panel: MenuBarStatusController?
    private var subscriptions = Set<AnyCancellable>()
    private var externalOwnerActive: Bool {
        guard Defaults[.enableThirdPartyDDCIntegration], Defaults[.enableExternalVolumeControlListener] else { return false }
        switch Defaults[.thirdPartyDDCProvider] {
        case .betterDisplay: return BetterDisplayManager.checkRunning()
        case .lunar: return LunarManager.checkRunning()
        }
    }

    func start(panel: MenuBarStatusController) {
        guard subscriptions.isEmpty else { return }
        self.panel = panel
        display.$state.sink { [weak self] state in
            guard let self else { return }
            self.panel?.updateDirectDisplayVolume(state)
            volume.updateDirectDisplayVolume(
                deviceID: state?.outputID, scalar: state?.scalar.map(Float.init), canMute: state?.canMute ?? false,
                setVolume: { [weak self] value in
                    Task { @MainActor in
                        guard let self, self.isCurrent(state) else { return }
                        self.display.setVolume(Double(value))
                    }
                },
                adjust: { [weak self] delta in
                    Task { @MainActor in
                        guard let self, self.isCurrent(state) else { return }
                        self.display.adjust(by: Double(delta))
                    }
                },
                setMuted: { [weak self] muted in
                    Task { @MainActor in
                        guard let self, self.isCurrent(state) else { return }
                        self.display.setMuted(muted)
                    }
                }
            )
        }.store(in: &subscriptions)
        panel.panelVisibilityPublisher.sink { [weak self] in self?.display.setDetailsVisible($0) }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .systemAudioRouteDidChange)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.reconcile() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                self?.reconcile()
                self?.display.topologyChanged()
            }.store(in: &subscriptions)
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name)
                .receive(on: RunLoop.main).sink { [weak self] notification in
                    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          [BetterDisplayManager.bundleID, LunarManager.bundleID].contains(app.bundleIdentifier ?? "") else { return }
                    self?.reconcile()
                }.store(in: &subscriptions)
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name)
                .receive(on: RunLoop.main).sink { [weak self] _ in self?.display.setDisplayAsleep(true) }
                .store(in: &subscriptions)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name)
                .receive(on: RunLoop.main).sink { [weak self] _ in
                    self?.reconcile()
                    self?.display.setDisplayAsleep(false)
                    self?.display.topologyChanged()
                }.store(in: &subscriptions)
        }
        Defaults.publisher(.enableDirectDisplayVolumeControl, options: []).sink { [weak self] _ in
            self?.reconcile()
        }.store(in: &subscriptions)
        Defaults.publisher(.enableThirdPartyDDCIntegration, options: []).sink { [weak self] _ in
            self?.reconcile()
        }.store(in: &subscriptions)
        Defaults.publisher(.enableExternalVolumeControlListener, options: []).sink { [weak self] _ in
            self?.reconcile()
        }.store(in: &subscriptions)
        Defaults.publisher(.thirdPartyDDCProvider, options: []).sink { [weak self] _ in
            self?.reconcile()
        }.store(in: &subscriptions)
        reconcile()
    }

    func stop() {
        subscriptions.removeAll()
        display.stop()
        panel?.updateDirectDisplayVolume(nil)
        panel = nil
        volume.updateDirectDisplayVolume(deviceID: nil, scalar: nil, setVolume: { _ in }, adjust: { _ in }, setMuted: { _ in })
    }

    private func reconcile() {
        let route = volume.directDisplayRoute()
        let enabled = DirectDisplayVolumeController.shouldUseDirectControl(
            enabled: Defaults[.enableDirectDisplayVolumeControl], coreAudioWritable: route.coreAudioWritable,
            externalVolumeOwnerActive: externalOwnerActive, transport: route.transport, uid: route.uid
        )
        display.select(outputID: route.id, uid: enabled ? route.uid : nil)
    }

    private func isCurrent(_ state: DirectDisplayVolumeState?) -> Bool {
        guard let state else { return false }
        let route = volume.directDisplayRoute()
        return state.outputID == route.id && state.uid == route.uid &&
            DirectDisplayVolumeController.shouldUseDirectControl(
                enabled: Defaults[.enableDirectDisplayVolumeControl], coreAudioWritable: route.coreAudioWritable,
                externalVolumeOwnerActive: externalOwnerActive, transport: route.transport, uid: route.uid
            )
    }
}
