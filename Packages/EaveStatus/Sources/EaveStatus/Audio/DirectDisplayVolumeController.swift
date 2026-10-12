import Combine
import CoreAudio
import Foundation

/// A verified display reading; nil is unavailable, never an invented volume.
public struct DirectDisplayVolumeState: Equatable, Sendable {
    public let outputID: UInt32
    public let uid: String
    public let scalar: Double?
    public let canMute: Bool

    public init(outputID: UInt32, uid: String, scalar: Double?, canMute: Bool = false) {
        self.outputID = outputID
        self.uid = uid
        self.scalar = scalar.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
        self.canMute = self.scalar != nil && canMute
    }
}

/// Eave's single volume owner supplies routing policy; this object only handles DDC.
@MainActor
public final class DirectDisplayVolumeController {
    @Published public private(set) var state: DirectDisplayVolumeState?
    private let transport: any DDCVolumeTransport
    private lazy var coordinator = DDCVolumeCoordinator(transport: transport) { [weak self] in
        self?.receive($0)
    }
    private var lastNonzeroVolume: Double?
    private var pendingCommand: UInt64?
    private var pendingVolume: Double?

    public convenience init() { self.init(transport: DDCDisplayTransport()) }
    init(transport: any DDCVolumeTransport) { self.transport = transport }

    public static func shouldUseDirectControl(enabled: Bool, coreAudioWritable: Bool,
                                              externalVolumeOwnerActive: Bool,
                                              transport: UInt32, uid: String?) -> Bool {
        enabled && !coreAudioWritable && !externalVolumeOwnerActive &&
        (transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort) &&
        !(uid?.isEmpty ?? true)
    }

    public func select(outputID: UInt32, uid: String?) {
        guard state?.outputID != outputID || state?.uid != uid else { return }
        pendingCommand = nil
        pendingVolume = nil
        lastNonzeroVolume = nil
        state = uid.map { DirectDisplayVolumeState(outputID: outputID, uid: $0, scalar: nil) }
        coordinator.select(outputID: outputID, uid: uid)
    }

    @discardableResult
    public func setVolume(_ scalar: Double) -> Bool {
        guard scalar.isFinite, state?.scalar != nil else { return false }
        pendingCommand = coordinator.setVolume(scalar)
        pendingVolume = pendingCommand == nil ? nil : min(1, max(0, scalar))
        return pendingCommand != nil
    }

    public func adjust(by delta: Double) {
        guard delta.isFinite, let scalar = pendingVolume ?? state?.scalar else { return }
        _ = setVolume(scalar + delta)
    }

    /// DDC VCP 0x62 exposes level only. Mute is zero with a remembered restore level.
    @discardableResult
    public func setMuted(_ muted: Bool) -> Bool {
        guard let scalar = state?.scalar else { return false }
        if muted {
            if scalar > 0 { lastNonzeroVolume = scalar }
            return setVolume(0)
        }
        guard scalar == 0, let lastNonzeroVolume else { return false }
        return setVolume(lastNonzeroVolume)
    }

    public func setDetailsVisible(_ visible: Bool) { coordinator.setDetailsVisible(visible) }
    public func setDisplayAsleep(_ asleep: Bool) {
        if asleep { invalidateReading() }
        coordinator.setDisplayAsleep(asleep)
    }
    public func topologyChanged() {
        invalidateReading()
        coordinator.topologyChanged()
    }
    public func stop() { coordinator.stop(); state = nil; pendingCommand = nil; pendingVolume = nil }

    private func invalidateReading() {
        pendingCommand = nil
        pendingVolume = nil
        if let state {
            self.state = DirectDisplayVolumeState(outputID: state.outputID, uid: state.uid, scalar: nil)
        }
    }

    private func receive(_ update: DDCVolumeUpdate) {
        guard let state, update.outputID == state.outputID, update.uid == state.uid,
              update.generation == coordinator.generation else { return }
        if let pendingCommand {
            guard update.commandID == pendingCommand else { return }
            self.pendingCommand = nil
            pendingVolume = nil
        }
        if let scalar = update.scalar, scalar > 0 { lastNonzeroVolume = scalar }
        self.state = DirectDisplayVolumeState(outputID: update.outputID, uid: update.uid,
                                             scalar: update.scalar,
                                             canMute: (update.scalar ?? 0) > 0 || lastNonzeroVolume != nil)
    }
}

extension MenuBarStatusController {
    public func updateDirectDisplayVolume(_ state: DirectDisplayVolumeState?) {
        store.updateDirectDisplayVolume(state)
    }
}
