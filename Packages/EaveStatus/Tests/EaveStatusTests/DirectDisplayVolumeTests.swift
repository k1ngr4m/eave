import CoreAudio
import Foundation
import XCTest
@testable import EaveStatus

@MainActor
final class DirectDisplayVolumeTests: XCTestCase {
    func testDirectControlIsExplicitAndYieldsToExistingOwners() {
        func allowed(enabled: Bool = true, writable: Bool = false, external: Bool = false,
                     transport: UInt32 = kAudioDeviceTransportTypeHDMI, uid: String? = "display") -> Bool {
            DirectDisplayVolumeController.shouldUseDirectControl(
                enabled: enabled, coreAudioWritable: writable, externalVolumeOwnerActive: external,
                transport: transport, uid: uid)
        }
        XCTAssertTrue(allowed())
        XCTAssertTrue(allowed(transport: kAudioDeviceTransportTypeDisplayPort))
        XCTAssertFalse(allowed(enabled: false))
        XCTAssertFalse(allowed(writable: true))
        XCTAssertFalse(allowed(external: true))
        XCTAssertFalse(allowed(transport: kAudioDeviceTransportTypeBuiltIn))
        XCTAssertFalse(allowed(transport: kAudioDeviceTransportTypeBluetooth))
        XCTAssertFalse(allowed(uid: nil))
        XCTAssertFalse(allowed(uid: ""))
    }

    func testPanelUsesOnlyConfirmedReadingForTheSameRoute() {
        let device = AudioOutputDevice(id: 7, name: "Display", uid: "display", isCurrent: true)
        let status = VolumeStatus(scalar: nil, isMuted: false, deviceName: device.name,
                                  currentDevice: device, outputDevices: [device],
                                  canSetVolume: false, canMute: false)
        let valid = DirectDisplayVolumeState(outputID: 7, uid: "display", scalar: 0.45, canMute: true)
        let merged = VolumeMonitor.mergingDirectDisplayVolume(valid, into: status)
        XCTAssertEqual(merged.scalar, 0.45)
        XCTAssertEqual(merged.currentDevice?.volume, 0.45)
        XCTAssertEqual(merged.outputDevices.first?.volume, 0.45)
        XCTAssertTrue(merged.canSetVolume)
        XCTAssertTrue(merged.canMute)
        for state in [DirectDisplayVolumeState(outputID: 8, uid: "display", scalar: 0.8),
                      DirectDisplayVolumeState(outputID: 7, uid: "old-display", scalar: 0.8)] {
            XCTAssertEqual(VolumeMonitor.mergingDirectDisplayVolume(state, into: status), status)
        }
        let unavailable = DirectDisplayVolumeState(outputID: 7, uid: "display", scalar: nil, canMute: true)
        let disabled = VolumeMonitor.mergingDirectDisplayVolume(unavailable, into: status)
        XCTAssertNil(disabled.scalar)
        XCTAssertFalse(disabled.canSetVolume)
        XCTAssertFalse(disabled.canMute)
        let coreAudio = VolumeStatus(scalar: 0.2, isMuted: false, deviceName: device.name,
                                     currentDevice: device, canSetVolume: true)
        XCTAssertEqual(VolumeMonitor.mergingDirectDisplayVolume(valid, into: coreAudio), coreAudio)
    }

    func testLateDuplicateRouteEventKeepsHostReadingForSameIdentity() async {
        let device = AudioOutputDevice(id: 7, name: "Display", uid: "display", isCurrent: true)
        let reader = DirectDisplayStatusReader(device: device)
        let events = DirectDisplayEventMonitor()
        let monitor = VolumeMonitor(statusReader: reader, eventMonitor: events,
                                    refreshDebounceInterval: .zero)
        var values: [VolumeStatus] = []
        let consume = Task { for await value in monitor.updates { values.append(value) } }
        defer { monitor.stop(); consume.cancel() }
        monitor.start()
        monitor.updateDirectDisplayVolume(DirectDisplayVolumeState(outputID: 7, uid: "display", scalar: 0.4))
        await waitFor { values.last?.scalar == 0.4 }
        events.routeChanged?()
        await waitFor { reader.reads >= 2 && values.last?.scalar == 0.4 }
        XCTAssertTrue(values.last?.canSetVolume == true)
        reader.device = AudioOutputDevice(id: 7, name: "Other", uid: "other", isCurrent: true)
        events.routeChanged?()
        await waitFor { reader.reads >= 3 && values.last?.currentDevice?.uid == "other" }
        XCTAssertNil(values.last?.scalar)
        XCTAssertFalse(values.last?.canSetVolume ?? true)
    }

    func testRepeatedKeysAccumulateAndMuteRestoresReadLevel() async {
        let transport = ReadbackDDCTransport()
        let control = DirectDisplayVolumeController(transport: transport)
        defer { control.stop() }
        control.select(outputID: 7, uid: "display")
        XCTAssertFalse(control.setVolume(0.9), "Cannot write before the display answers")
        await waitFor { control.state?.scalar == 0.5 }
        control.adjust(by: 0.1)
        control.adjust(by: 0.1)
        await waitFor { control.state?.scalar == 0.7 }
        XCTAssertEqual(transport.writes, [70], "Key repeats coalesce without losing their delta")
        XCTAssertTrue(control.setMuted(true))
        await waitFor { control.state?.scalar == 0 }
        XCTAssertTrue(control.state?.canMute == true)
        XCTAssertTrue(control.setMuted(false))
        await waitFor { control.state?.scalar == 0.7 }
        XCTAssertEqual(transport.writes, [70, 0, 70])
    }

    func testSleepCancelsPendingWriteAndRequiresFreshReading() async {
        let transport = ReadbackDDCTransport()
        let control = DirectDisplayVolumeController(transport: transport)
        defer { control.stop() }
        control.select(outputID: 7, uid: "display")
        await waitFor { control.state?.scalar != nil }
        XCTAssertTrue(control.setVolume(0.8))
        control.setDisplayAsleep(true)
        XCTAssertNil(control.state?.scalar)
        XCTAssertFalse(control.setVolume(0.9))
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(transport.writes.isEmpty)
        control.setDisplayAsleep(false)
        await waitFor { control.state?.scalar == 0.5 }
    }

    private func waitFor(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("DDC state did not settle", file: file, line: line)
    }
}

private final class ReadbackDDCTransport: DDCVolumeTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt16 = 50
    private var recordedWrites: [UInt16] = []
    var writes: [UInt16] { lock.withLock { recordedWrites } }
    func resolve(uid: String) -> DDCDisplayTarget? { DDCDisplayTarget(uid: uid, service: nil) }
    func read(_ target: DDCDisplayTarget) -> DDCVolumeReadResult {
        lock.withLock { .reply(DDCVolumeReply(current: value, maximum: 100)) }
    }
    func write(_ target: DDCDisplayTarget, value: UInt16) -> Bool {
        lock.withLock { self.value = value; recordedWrites.append(value) }
        return true
    }
}

@MainActor
private final class DirectDisplayStatusReader: AudioStatusReadingProviding {
    var device: AudioOutputDevice
    var reads = 0
    init(device: AudioOutputDevice) { self.device = device }
    func read(includeOutputDevices: Bool, completion: @escaping @MainActor @Sendable (AudioStatusReading) -> Void) {
        reads += 1
        completion(AudioStatusReading(volume: VolumeReading(scalar: nil, isMuted: false,
                                                            deviceName: device.name, currentDevice: device,
                                                            canSetVolume: false, canMute: false),
                                      outputDevices: includeOutputDevices ? [device] : nil))
    }
}

@MainActor
private final class DirectDisplayEventMonitor: VolumeEventMonitoring {
    var routeChanged: (@MainActor @Sendable () -> Void)?
    func start(onDefaultDeviceChange: @escaping @MainActor @Sendable () -> Void,
               onVolumeChange: @escaping @MainActor @Sendable () -> Void) {
        routeChanged = onDefaultDeviceChange
    }
    func reconcile() {}
    func recover() {}
    func stop() { routeChanged = nil }
}
