import Combine
import XCTest
@testable import EaveStatus

@MainActor
final class SharedBluetoothStatusTests: XCTestCase {
    private let device = BluetoothDevice(id: "AA:BB:CC:DD:EE:FF", name: "Renamed headphones", kind: .audio,
                                         isConnected: true, vendorID: 0x05AC, productID: 0x2014)

    func testSharedReadingKeepsIdentityAndEachBatteryChannel() {
        let battery = BluetoothBatteryLevel(deviceAddress: device.id, main: nil, left: 40, right: 60, caseLevel: 80)
        let state = MenuBarBluetoothState(devices: [device], batteryLevels: ["AABBCCDDEEFF": battery],
                                         availability: .available, hasReadDevices: true)
        XCTAssertTrue(state.isAuthoritative)
        XCTAssertEqual(state.devices.first?.id, "AABBCCDDEEFF")
        XCTAssertEqual(state.devices.first?.productID, 0x2014)
        XCTAssertEqual(state.devices.first?.batteryLeft, 40)
        XCTAssertEqual(state.devices.first?.batteryRight, 60)
        XCTAssertEqual(state.devices.first?.batteryCase, 80)
        XCTAssertEqual(state.devices.first?.batteryPercentage, 80, "Keep the existing HUD aggregation")
        XCTAssertTrue(state.devices.first?.isAudio == true)
    }

    func testOnlySuccessfulReadOrDefinitiveUnavailableStateCanChangeConnections() {
        for availability in [BluetoothAvailability.idle, .initializing, .failed, .authorizationNotDetermined] {
            XCTAssertFalse(MenuBarBluetoothState(devices: [device], batteryLevels: [:], availability: availability,
                                                  hasReadDevices: true).isAuthoritative)
        }
        XCTAssertFalse(MenuBarBluetoothState(devices: [device], batteryLevels: [:], availability: .available,
                                              hasReadDevices: false).isAuthoritative)
        for availability in [BluetoothAvailability.poweredOff, .authorizationDenied, .authorizationRestricted, .unavailable] {
            let state = MenuBarBluetoothState(devices: [device], batteryLevels: [:], availability: availability, hasReadDevices: true)
            XCTAssertTrue(state.isAuthoritative)
            XCTAssertTrue(state.devices.isEmpty)
        }
    }

    func testHostMonitoringSurvivesPanelCloseAndDiscardsPreSleepRead() async {
        let worker = SharedPairedReader()
        let monitor = SharedBluetoothStateMonitor()
        let events = SharedConnectionEvents()
        let controller = BluetoothDeviceController(worker: worker, stateMonitor: monitor,
            batteryReader: SharedBatteryReader(), connectionEvents: events)
        var snapshots: [MenuBarBluetoothState] = []
        let subscription = controller.hostStatusPublisher.sink { snapshots.append($0) }
        defer { subscription.cancel(); controller.setHostMonitoringEnabled(false) }
        controller.setHostMonitoringEnabled(true)
        XCTAssertEqual(worker.count, 1)
        worker.complete(.success([device]))
        await settle { snapshots.last?.isAuthoritative == true }
        XCTAssertEqual(snapshots.last?.devices.count, 1)
        controller.holdVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.releaseVisibleSurface(BluetoothDeviceController.popoverSurfaceToken)
        controller.deactivate()
        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(controller.isSafetyNetPolling)
        XCTAssertTrue(controller.isMonitoringConnectionEvents)
        XCTAssertTrue(controller.isBatteryLevelsRequested)

        controller.refresh()
        controller.setSystemSleeping(true)
        XCTAssertFalse(controller.isSafetyNetPolling)
        XCTAssertFalse(controller.isMonitoringConnectionEvents)
        XCTAssertFalse(snapshots.last?.isAuthoritative ?? true)
        worker.complete(.success([])) // The completion belongs to the retired pre-sleep request.
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(controller.devices.count, 1)
        controller.setSystemSleeping(false)
        XCTAssertTrue(controller.isMonitoringConnectionEvents)
        XCTAssertFalse(snapshots.last?.isAuthoritative ?? true, "Wake must not replay a stale successful snapshot")
        worker.complete(.success([]))
        await settle { snapshots.last?.isAuthoritative == true }
        XCTAssertTrue(snapshots.last?.devices.isEmpty == true)
        controller.setHostMonitoringEnabled(false)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.isSafetyNetPolling)
        XCTAssertFalse(controller.isMonitoringConnectionEvents)
        XCTAssertFalse(controller.isBatteryLevelsRequested)
    }

    func testHostRefreshesCoalesceAndRecoverAfterReadFailure() async {
        let worker = SharedPairedReader()
        let controller = BluetoothDeviceController(worker: worker, stateMonitor: SharedBluetoothStateMonitor(),
            batteryReader: SharedBatteryReader(), safetyNetInterval: .milliseconds(20))
        defer { controller.setHostMonitoringEnabled(false) }
        controller.setHostMonitoringEnabled(true)
        controller.refresh()
        controller.refresh()
        XCTAssertEqual(worker.count, 1)
        worker.complete(.success([device]))
        await settle { worker.count == 2 }
        worker.complete(.failed)
        await settle { controller.availability == .failed }
        XCTAssertTrue(controller.isSafetyNetPolling, "The HUD must recover without reopening the panel")
        try? await Task.sleep(for: .milliseconds(30))
        await settle { worker.count >= 3 }
        worker.complete(.success([device]))
        await settle { controller.availability == .available }
    }

    func testConnectedFallbackPreservesCacheChannelsAndRejectsAnotherDevicesName() {
        let otherAddress = "11:22:33:44:55:66"
        let uuid = UUID()
        let conflicting: ConnectedBluetoothBatteryFallback.Cache = (
            [otherAddress: ["Name": device.name, "BatteryPercent": 99]],
            [uuid.uuidString: ["Name": device.name, "DeviceAddress": otherAddress]], [])
        XCTAssertNil(ConnectedBluetoothBatteryFallback.cachedLevel(for: device, cache: conflicting))
        XCTAssertNil(ConnectedBluetoothBatteryFallback.peripheralID(for: device, cache: conflicting.identifiers))
        let matching: ConnectedBluetoothBatteryFallback.Cache = (
            [device.id: ["BatteryPercentLeft": 24, "BatteryPercentRight": 42, "BatteryPercentCase": 80]],
            [uuid.uuidString: ["Name": "Old name", "DeviceAddress": device.id]], [])
        let level = ConnectedBluetoothBatteryFallback.cachedLevel(for: device, cache: matching)
        XCTAssertEqual(level?.left, 24)
        XCTAssertEqual(level?.right, 42)
        XCTAssertEqual(level?.caseLevel, 80)
        XCTAssertEqual(ConnectedBluetoothBatteryFallback.peripheralID(for: device, cache: matching.identifiers), uuid)
    }

    func testConnectedFallbackReadsOnlyMissingPairedDeviceAndRejectsLateCompletion() {
        let uuid = UUID()
        let scanner = SharedBatteryScanner()
        let reader = ConnectedBluetoothBatteryFallback(scanner: scanner) {
            ([:], [uuid.uuidString: ["DeviceAddress": self.device.id]], [])
        }
        var latest: [String: BluetoothBatteryLevel] = [:]
        reader.read(devices: [device], levels: [:]) { latest = $0 }
        XCTAssertEqual(scanner.allowed, [uuid])
        XCTAssertTrue(scanner.isRunning)
        let oldCompletion = scanner.onDevicesChanged
        let reading = NearbyBluetoothBatteryDevice(id: uuid, name: device.name, batteryLevel: 37, lastUpdated: Date())
        oldCompletion?([reading])
        XCTAssertEqual(latest["AABBCCDDEEFF"]?.main, 37)
        reader.stop()
        latest = [:]
        oldCompletion?([reading])
        XCTAssertTrue(latest.isEmpty, "A pre-sleep/pre-refresh callback must not republish")
        XCTAssertTrue(scanner.allowed.isEmpty)
        XCTAssertFalse(scanner.isRunning)
        let primary = BluetoothBatteryLevel(deviceAddress: device.id, main: 55, left: nil, right: nil, caseLevel: nil)
        reader.read(devices: [device], levels: ["AABBCCDDEEFF": primary]) { latest = $0 }
        XCTAssertFalse(scanner.isRunning, "A valid primary reading never starts fallback GATT")
        oldCompletion?([reading])
        XCTAssertTrue(latest.isEmpty)
    }

    func testConnectedFallbackDoesNotGuessBetweenTwoSameNameDevices() {
        let uuid = UUID()
        let scanner = SharedBatteryScanner()
        let second = BluetoothDevice(id: "11:22:33:44:55:66", name: device.name, kind: .audio, isConnected: true)
        let reader = ConnectedBluetoothBatteryFallback(scanner: scanner) {
            (["unknown": ["Name": self.device.name, "BatteryPercent": 90]], [uuid.uuidString: ["Name": self.device.name]], [])
        }
        var latest: [String: BluetoothBatteryLevel] = [:]
        reader.read(devices: [device, second], levels: [:]) { latest = $0 }
        XCTAssertTrue(latest.isEmpty)
        XCTAssertTrue(scanner.allowed.isEmpty)
        XCTAssertFalse(scanner.isRunning)
    }

    private func settle(_ predicate: () -> Bool) async {
        for _ in 0..<1_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTAssertTrue(predicate(), "Asynchronous controller update did not arrive")
    }
}

private final class SharedPairedReader: BluetoothPairedDeviceReading {
    var count = 0
    private var completions: [@Sendable (BluetoothWorkerResult) -> Void] = []
    func read(completion: @escaping @Sendable (BluetoothWorkerResult) -> Void) {
        count += 1
        completions.append(completion)
    }
    func complete(_ result: BluetoothWorkerResult) {
        guard !completions.isEmpty else { XCTFail("No device read was requested"); return }
        completions.removeFirst()(result)
    }
}

@MainActor
private final class SharedBluetoothStateMonitor: BluetoothStateMonitoring {
    var onStateChange: ((BluetoothAuthorizationStatus, BluetoothManagerState) -> Void)?
    let authorization = BluetoothAuthorizationStatus.allowed
    func start() { onStateChange?(.allowed, .poweredOn) }
    func stop() {}
}

private final class SharedBatteryReader: BluetoothBatteryReading {
    func read(completion: @escaping @Sendable ([String: BluetoothBatteryLevel]?) -> Void) { completion([:]) }
}

private final class SharedConnectionEvents: BluetoothConnectionEventMonitoring {
    func start(handler: @escaping @Sendable () -> Void) -> Bool { true }
    func stop() {}
}

@MainActor
private final class SharedBatteryScanner: BluetoothLEBatteryScanning {
    var onDevicesChanged: (([NearbyBluetoothBatteryDevice]) -> Void)?
    var onCandidatesChanged: (([NearbyBLEDeviceCandidate]) -> Void)?
    var onReadFailures: ((Set<UUID>) -> Void)?
    var onIsScanningChanged: ((Bool) -> Void)?
    var isRunning = false
    var isScanning = false
    var allowed: Set<UUID> = []
    func setAllowedReadDeviceIDs(_ ids: Set<UUID>) { allowed = ids }
    func start() { isRunning = true }
    func refresh() {}
    func stop() { isRunning = false }
}
