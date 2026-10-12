import Combine
import CoreWLAN
import XCTest
@testable import EaveStatus

final class SharedNetworkStateTests: XCTestCase {
    func testPathDeterminesConnectivityAndHotspotWithoutWaitingForWiFiDetails() {
        XCTAssertEqual(MenuBarNetworkState(path: nil, wifi: .placeholder).connection, .unknown)
        let wifi = WiFiStatus(state: .connected, rssi: -45, ssid: "Home", nameAccess: .authorized)
        let hotspot = NetworkPathSnapshot(connected: true, wired: false, wireless: true, expensive: true)
        XCTAssertTrue(MenuBarNetworkState(path: hotspot, wifi: .placeholder).isHotspot)
        XCTAssertEqual(MenuBarNetworkState(path: hotspot, wifi: wifi).wifiName, "Home")
        let constrained = NetworkPathSnapshot(connected: true, wired: false, wireless: true,
                                              expensive: true, constrained: true)
        XCTAssertFalse(MenuBarNetworkState(path: constrained, wifi: wifi).isHotspot)
        let offline = NetworkPathSnapshot(connected: false, wired: false, wireless: true)
        XCTAssertFalse(MenuBarNetworkState(path: offline, wifi: wifi).isConnected)
        XCTAssertNil(MenuBarNetworkState(path: offline, wifi: wifi).wifiName)
        let wired = NetworkPathSnapshot(connected: true, wired: true, wireless: true)
        XCTAssertEqual(MenuBarNetworkState(path: wired, wifi: wifi).connection, .ethernet)
        XCTAssertNil(MenuBarNetworkState(path: wired, wifi: wifi).wifiName)
    }

    @MainActor
    func testNotchRetainsAuthorizedNameWhenPopoverClosesAndHonorsRevocation() async {
        let reader = SharedWiFiReader()
        let access = SharedWiFiAccess()
        let monitor = WiFiMonitor(statusReader: reader, nameAuthorizer: access,
                                  eventMonitor: SharedWiFiEvents(),
                                  keepsNameAvailable: true)
        monitor.setDetailsVisible(false)
        monitor.start()
        var readings = monitor.updates.makeAsyncIterator()
        let initial = await readings.next()
        XCTAssertEqual(initial?.ssid, "Home")
        XCTAssertEqual(reader.requestedSSID, true)
        access.access = .denied
        access.onAccessChange?()
        let revoked = await readings.next()
        XCTAssertNil(revoked?.ssid)
        XCTAssertEqual(revoked?.nameAccess, .denied)
        monitor.stop()
    }

    @MainActor
    func testStoreFeedsTheSamePathToWiFiClassificationAndHostPublisher() async {
        let paths = SharedNetworkPathSource()
        let wifi = WiFiMonitor(statusReader: SharedWiFiReader(), nameAuthorizer: SharedWiFiAccess(),
                               eventMonitor: SharedWiFiEvents(), keepsNameAvailable: true,
                               refreshDebounceInterval: .zero, refreshDebounceSleep: { _ in })
        let store = SystemStatusStore(batteryMonitor: HostBatteryMonitor(), wifiMonitor: wifi,
                                      connectionMonitor: paths, volumeMonitor: SharedNetworkVolume(),
                                      volumeFeedback: nil, wakeNotificationCenter: NotificationCenter())
        let classified = expectation(description: "Shared path classifies the menu bar as hotspot")
        let published = expectation(description: "The host receives the same hotspot path")
        let wifiSubscription = store.$snapshot.first { $0.wifi.state == .hotspot }.sink { _ in classified.fulfill() }
        let hostSubscription = store.$networkState.first { $0.isHotspot && $0.wifiName == "Home" }
            .sink { _ in published.fulfill() }
        store.start()
        paths.continuation.yield(NetworkPathSnapshot(connected: true, wired: false, wireless: true, expensive: true))
        let result = await XCTWaiter.fulfillment(of: [classified, published], timeout: 2)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(store.networkState.connection, .wifi)
        store.stop()
        wifiSubscription.cancel()
        hostSubscription.cancel()
    }
}

@MainActor
private final class SharedWiFiReader: WiFiStatusReadingProviding {
    var requestedSSID = false
    func read(includeSSID: Bool, completion: @escaping @MainActor @Sendable (WiFiStatusReading) -> Void) {
        requestedSSID = includeSSID
        completion(WiFiStatusReading(interface: WiFiSystemReading(powerOn: true, serviceActive: true,
                                                                mode: .station, rssi: -45, ssid: "Home"),
                                     sharingActive: false))
    }
}

@MainActor
private final class SharedWiFiAccess: WiFiNameAuthorizing {
    var access: WiFiNameAccess = .authorized
    var onAccessChange: (() -> Void)?
    func requestAccess() -> WiFiNameAccessRequestResult { .notNeeded }
}

private final class SharedWiFiEvents: WiFiEventMonitoring {
    func start(delegate: any CWEventDelegate, events: [CWEventType]) {}
    func restart(delegate: any CWEventDelegate, events: [CWEventType]) {}
    func stop() {}
}

@MainActor
private final class SharedNetworkPathSource: NetworkConnectionMonitoring {
    let updates: AsyncStream<NetworkPathSnapshot>
    let continuation: AsyncStream<NetworkPathSnapshot>.Continuation
    init() { (updates, continuation) = AsyncStream.makeStream() }
    func start() {}
    func stop() { continuation.finish() }
    func recover() {}
}

@MainActor
private final class SharedNetworkVolume: VolumeMonitoring {
    let updates = AsyncStream<VolumeStatus> { $0.finish() }
    func start() {}
    func stop() {}
    func refresh() {}
    func recover() {}
}
