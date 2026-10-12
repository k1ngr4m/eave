import AppKit
import CoreAudio
import XCTest
@testable import EaveStatus

@MainActor
final class PhaseTwoAudioTests: XCTestCase {
    func testInputMigrationOffersSectionOnceAndPreservesLaterChoice() {
        let suite = "EaveStatusTests.Audio.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.setPopupSection(.audioInput, enabled: false)
        settings.setPopupSection(.vpn, enabled: false)

        settings.introduceAudioInputSection(defaults: defaults)
        XCTAssertTrue(settings.visiblePopupSections.contains(.audioInput))
        XCTAssertFalse(settings.enabledPopupSections.contains(.vpn))

        settings.setPopupSection(.audioInput, enabled: false)
        let relaunched = SettingsStore(defaults: defaults)
        relaunched.introduceAudioInputSection(defaults: defaults)
        XCTAssertFalse(relaunched.visiblePopupSections.contains(.audioInput))
    }

    func testInputCommandsValidateIdentityAndNeverInvokeOutputCommands() {
        let device = AudioInputDevice(id: 7, uid: "microphone", name: "Microphone")
        var selected: [UInt32] = []
        var scalars: [Double] = []
        var mutes = 0
        let actions = StatusPanelActions(
            inputDevices: { [device] }, selectInput: { selected.append($0.id) },
            setVolume: { _ in XCTFail("Input must not write output volume") },
            toggleMute: { XCTFail("Input must not mute output") },
            setInputScalar: { scalars.append($0) }, toggleInputMute: { mutes += 1 }
        )
        actions.selectInput(PanelAudioDeviceID(id: 7, uid: "stale"))
        actions.selectInput(PanelAudioDeviceID(id: 7, uid: "microphone"))
        actions.setInputScalar(.nan)
        actions.setInputScalar(2)
        actions.toggleInputMute()
        XCTAssertEqual(selected, [7])
        XCTAssertEqual(scalars, [1])
        XCTAssertEqual(mutes, 1)
    }

    func testInputHardwareRejectsUnavailablePropertiesAndStaleDefault() throws {
        let client = InputPropertyFixture()
        let hardware = CoreAudioInputHardware(client: client)
        let reading = try hardware.read(includeDevices: true)
        XCTAssertEqual(reading.devices?.map(\.id), [7])
        XCTAssertEqual(reading.scalar, 0.5)
        XCTAssertTrue(reading.canSetVolume)
        XCTAssertTrue(reading.canSetMute)
        try hardware.setScalar(2, on: 7)
        try hardware.setMuted(true, on: 7)
        XCTAssertEqual(client.scalars, [1])
        XCTAssertEqual(client.mutes, [true])

        client.current = 8
        XCTAssertThrowsError(try hardware.setMuted(false, on: 7))
        XCTAssertEqual(client.mutes, [true], "Stale controls cannot mutate the previous default")
        client.current = 7
        client.writable = false
        XCTAssertFalse(try hardware.read(includeDevices: false).canSetMute)
        XCTAssertThrowsError(try hardware.setScalar(0.2, on: 7))
        XCTAssertThrowsError(try hardware.setScalar(.infinity, on: 7))
        XCTAssertEqual(client.scalars, [1])
    }

    func testListeningModeActionsRejectDisconnectedOrUnsupportedDevices() {
        let address = "AA:BB:CC:DD:EE:FF"
        let normalized = BluetoothBatteryReader.normalizedAddress(address)
        var connected = true
        var writes: [BluetoothListeningMode] = []
        let actions = StatusPanelActions(
            bluetoothDevices: {
                [BluetoothDevice(id: address, name: "AirPods Pro", kind: .audio, isConnected: connected)]
            },
            setListeningMode: { mode, target in
                XCTAssertEqual(target, normalized)
                writes.append(mode)
            },
            listeningModePresentations: {
                [normalized: BluetoothListeningModePresentation(
                    availableModes: [.noiseCancellation, .transparency], selectedMode: .noiseCancellation
                )]
            }
        )
        actions.setListeningMode(address: address, mode: .adaptive)
        actions.setListeningMode(address: address, mode: .transparency)
        connected = false
        actions.setListeningMode(address: address, mode: .noiseCancellation)
        XCTAssertEqual(writes, [.transparency])
    }

    func testInputScrollRegionIsRemovedWithItsView() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 330, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let view = NSView(frame: NSRect(x: 10, y: 10, width: 310, height: 100))
        window.contentView?.addSubview(view)
        let targets = PopoverScrollTargets()
        targets.registerAudioInput(view)
        XCTAssertTrue(targets.containsAudioInput(at: NSPoint(x: 30, y: 30), in: window))
        XCTAssertFalse(targets.containsAudioInput(at: NSPoint(x: 30, y: 150), in: window))
        XCTAssertFalse(targets.containsVolumeControl(at: NSPoint(x: 30, y: 30), in: window))
        targets.unregisterAudioInput(view)
        XCTAssertFalse(targets.containsAudioInput(at: NSPoint(x: 30, y: 30), in: window))
    }

    func testListeningEndpointFallbackRequiresNoConflictingAddress() {
        let capability = BluetoothListeningModeCapability(
            audioDeviceID: 7, availableModes: [.noiseCancellation, .transparency],
            currentMode: .noiseCancellation, canSet: true
        )
        func resolve(_ address: String?, count: Int = 1) -> AudioDeviceID? {
            BluetoothListeningModeEndpointMapper.endpointID(
                forNormalizedAddress: "AA:BB:CC:DD:EE:FF", connectedEligibleAirPodsCount: count,
                in: [BluetoothListeningModeEndpoint(
                    audioDeviceID: 7, capability: capability, isDefaultOutput: true, bluetoothAddress: address
                )]
            )
        }
        XCTAssertEqual(resolve(nil), 7)
        XCTAssertNil(resolve(nil, count: 2))
        XCTAssertNil(resolve("11:22:33:44:55:66"))
        XCTAssertEqual(resolve("AA:BB:CC:DD:EE:FF"), 7)
    }

    func testInputDraftDropsPendingDragWhenDeviceChanges() {
        var draft = AudioInputVolumeDraft()
        draft.receiveSystemState(deviceIdentity: PanelAudioInputIdentity(rawValue: 7), scalar: 0.5)
        draft.setEditing(true)
        var writes: [Double] = []
        draft.setSliderValue(0.7, systemScalar: 0.5) { writes.append($0) }
        draft.receiveSystemState(deviceIdentity: PanelAudioInputIdentity(rawValue: 8), scalar: 0.2)
        draft.setSliderValue(0.9, systemScalar: 0.2) { writes.append($0) }
        XCTAssertFalse(draft.isEditing)
        XCTAssertEqual(draft.value, 0.2)
        XCTAssertEqual(writes, [0.7])
    }
}

/// Used synchronously on the test's main actor; production HAL access remains on its worker queue.
private final class InputPropertyFixture: AudioInputPropertyClient, @unchecked Sendable {
    var current: AudioDeviceID = 7
    var writable = true
    var scalars: [Float32] = []
    var mutes: [Bool] = []
    func devices() throws -> [AudioDeviceID] { [7, 0, 99] }
    func defaultInput() throws -> AudioDeviceID? { current }
    func isDevice(_ id: AudioDeviceID) -> Bool { id == 7 || id == 8 }
    func isAlive(_ id: AudioDeviceID) -> Bool? { true }
    func isHidden(_ id: AudioDeviceID) -> Bool? { false }
    func canBeDefaultInput(_ id: AudioDeviceID) -> Bool? { true }
    func inputChannels(_ id: AudioDeviceID) -> Int { 1 }
    func name(_ id: AudioDeviceID) -> String? { "Microphone" }
    func uid(_ id: AudioDeviceID) -> String? { "microphone" }
    func hasProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> Bool { element == kAudioObjectPropertyElementMain }
    func isSettable(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> Bool { writable }
    func activeInputProcessUsage() -> AudioInputProcessDeviceUsage? { nil }
    func readScalar(_ id: AudioDeviceID, _ element: AudioObjectPropertyElement) -> Float32? { 0.5 }
    func readMute(_ id: AudioDeviceID, _ element: AudioObjectPropertyElement) -> Bool? { false }
    func writeScalar(_ value: Float32, on id: AudioDeviceID, element: AudioObjectPropertyElement) throws { scalars.append(value) }
    func writeMute(_ value: Bool, on id: AudioDeviceID, element: AudioObjectPropertyElement) throws { mutes.append(value) }
    func writeDefaultInput(_ id: AudioDeviceID) throws { current = id }
}
