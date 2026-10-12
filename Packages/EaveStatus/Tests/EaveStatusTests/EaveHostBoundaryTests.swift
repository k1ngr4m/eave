import CoreAudio
import XCTest
@testable import EaveStatus

@MainActor
final class EaveHostBoundaryTests: XCTestCase {
    func testPanelActionsUseHostAudioCommandsAndValidateValues() {
        var volumes: [Double] = []
        var mutes = 0
        var selected: [UInt32] = []
        let host = HostAudioOutputController(setVolume: { volumes.append($0) },
                                             toggleMute: { mutes += 1 },
                                             selectOutputDevice: { selected.append($0) })
        let monitor = VolumeMonitor(statusReader: FixedAudioReader(), eventMonitor: SilentAudioEvents(),
                                    outputController: host)
        monitor.refresh()
        let device = AudioOutputDevice(id: 42, name: "Speakers", uid: "speaker", isCurrent: true)
        let initial = StatusSnapshot(battery: .placeholder, wifi: .placeholder, connection: .unknown,
                                     volume: VolumeStatus(scalar: 0.5, isMuted: false, deviceName: "Speakers",
                                                          currentDevice: device, outputDevices: [device]))
        let store = SystemStatusStore(batteryMonitor: HostBatteryMonitor(), wifiMonitor: SilentWiFiMonitor(),
                                      volumeMonitor: monitor, volumeFeedback: nil, initialSnapshot: initial)
        let defaults = UserDefaults(suiteName: "EaveStatusTests.\(UUID())")!
        let actions = StatusPanelActions(store: store, settings: SettingsStore(defaults: defaults))
        actions.setVolume(2)
        actions.setVolume(.nan)
        actions.toggleMute()
        actions.selectOutput(PanelAudioDeviceID(id: 42, uid: "speaker"))
        actions.selectOutput(PanelAudioDeviceID(id: 42, uid: "stale"))
        XCTAssertEqual(volumes, [1])
        XCTAssertEqual(mutes, 1)
        XCTAssertEqual(selected, [42])
        store.stop()
        actions.setVolume(0.2)
        XCTAssertEqual(volumes, [1], "Stopped panel must not write to the host")
    }

    func testBatteryReceivesHostStateBeforeMonitoringStarts() async {
        let monitor = HostBatteryMonitor()
        let hostState = MenuBarBatteryState(rawPercentage: 72, isPresent: true, isCharging: true,
                                           timeToFullChargeMinutes: 31, isLowPowerMode: false, isConnectedToPower: true)
        monitor.update(hostState)
        monitor.start()
        var readings = monitor.updates.makeAsyncIterator()
        let reading = await readings.next()
        XCTAssertEqual(reading, hostState.status)
        monitor.stop()
    }

    func testNewlyDiscoveredDevicesJoinBackgroundReadsAndHiddenDevicesAreRevoked() async throws {
        let suiteName = "EaveStatusTests.Mobile.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)
        settings.showsAppleDevicesAndBattery = true
        settings.showsBluetoothBatteryLevels = true
        settings.showsBluetoothDeviceList = true
        settings.refreshesAppleBatteriesInBackground = true
        let reader = DiscoveredMobileReader()
        let mobile = MobileBatteryController(reader: reader)
        let store = SystemStatusStore(
            batteryMonitor: HostBatteryMonitor(), wifiMonitor: SilentWiFiMonitor(),
            volumeMonitor: VolumeMonitor(statusReader: FixedAudioReader(), eventMonitor: SilentAudioEvents()),
            volumeFeedback: nil, mobileBattery: mobile,
            appleDeviceDiscovery: AppleDeviceDiscoveryController(reader: reader)
        )
        defer { store.stop() }
        store.bindMobileBatterySettings(settings)
        for _ in 0..<100 {
            if await reader.lastReadIDs == [.trustedDevice("phone")] { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let readIDs = await reader.lastReadIDs
        XCTAssertEqual(readIDs, [.trustedDevice("phone")], "fresh discovery must enable reading without reopening the panel")
        settings.setBluetoothDeviceHidden(AppleDeviceID.trustedDevice("phone").rowID, hidden: true)
        for _ in 0..<100 where !mobile.backgroundReadDeviceIDs.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(mobile.backgroundReadDeviceIDs.isEmpty)
    }

    func testVirtualMainVolumeIsReadableAndObservedWithoutScalarProperty() throws {
        let client = VirtualVolumeClient()
        let reading = try XCTUnwrap(CoreAudioVolumeReader(client: client).read())
        XCTAssertEqual(try XCTUnwrap(reading.scalar), 0.625, accuracy: 0.0001)
        XCTAssertTrue(reading.canSetVolume)
        let events = CoreAudioVolumeEventMonitor(client: client)
        events.start(onDefaultDeviceChange: {}, onVolumeChange: {})
        XCTAssertTrue(client.listeners.contains(CoreAudioVolumeReader.virtualMainVolume))
        events.stop()
        XCTAssertTrue(client.listeners.isEmpty)
    }
}

@MainActor
private final class FixedAudioReader: AudioStatusReadingProviding {
    func read(includeOutputDevices: Bool, completion: @escaping @MainActor @Sendable (AudioStatusReading) -> Void) {
        completion(AudioStatusReading(volume: VolumeReading(scalar: 0.5, isMuted: false, deviceName: "Speakers"), outputDevices: nil))
    }
}

@MainActor
private final class SilentAudioEvents: VolumeEventMonitoring {
    func start(onDefaultDeviceChange: @escaping @MainActor @Sendable () -> Void,
               onVolumeChange: @escaping @MainActor @Sendable () -> Void) {}
    func reconcile() {}
    func recover() {}
    func stop() {}
}

@MainActor
private final class SilentWiFiMonitor: WiFiMonitoring {
    let updates = AsyncStream<WiFiStatus> { _ in }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
    func requestNameAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

private final class VirtualVolumeClient: CoreAudioClient {
    var listeners: Set<AudioObjectPropertySelector> = []
    func defaultOutputDevice() -> AudioDeviceID? { 42 }
    func outputChannelElements(deviceID: AudioDeviceID) -> [AudioObjectPropertyElement] { [] }
    func deviceClass(of deviceID: AudioDeviceID) -> AudioClassID? { kAudioDeviceClassID }
    func isDeviceAlive(_ deviceID: AudioDeviceID) -> Bool { true }
    func readUInt32(objectID: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> UInt32? { nil }
    func readFloat32(objectID: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Float32? {
        selector == CoreAudioVolumeReader.virtualMainVolume ? 0.625 : nil
    }
    func readString(objectID: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> String? { nil }
    func readURL(objectID: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> URL? { nil }
    func hasProperty(objectID: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Bool {
        selector == CoreAudioVolumeReader.virtualMainVolume
    }
    func isPropertySettable(objectID: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Bool {
        selector == CoreAudioVolumeReader.virtualMainVolume
    }
    func addListener(objectID: AudioObjectID, address: AudioObjectPropertyAddress, queue: DispatchQueue?, block: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
        listeners.insert(address.mSelector); return noErr
    }
    func removeListener(objectID: AudioObjectID, address: AudioObjectPropertyAddress, queue: DispatchQueue?, block: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
        listeners.remove(address.mSelector); return noErr
    }
}

private actor DiscoveredMobileReader: MobileBatteryReading {
    private(set) var lastReadIDs: Set<AppleDeviceID> = []
    func discover() async throws -> [AppleDeviceCandidate] {
        [.init(id: .trustedDevice("phone"), name: "Phone", model: "iPhone18,1",
               transports: [.usb], trustRequired: false, evidence: .verifiedAppleModel)]
    }
    func read(selectedIDs: Set<AppleDeviceID>) async throws -> MobileBatteryReadResult {
        lastReadIDs = selectedIDs
        return .init()
    }
}
