import Combine
import EaveStatus
import XCTest
@testable import Eave

final class SharedNetworkHUDTests: XCTestCase {
    @MainActor
    func testSharedReadingsPreserveInitialSuppressionReconnectAndDismissal() {
        let readings = PassthroughSubject<MenuBarNetworkState, Never>()
        let manager = NetworkConnectivityManager()
        manager.startMonitoring(updates: readings.eraseToAnyPublisher())
        readings.send(MenuBarNetworkState(connection: .unknown))
        XCTAssertEqual(manager.hudState, .hidden)
        readings.send(MenuBarNetworkState(connection: .wifi))
        readings.send(MenuBarNetworkState(connection: .wifi, wifiName: "Home"))
        XCTAssertEqual(manager.hudState, .hidden, "Do not announce the initial connection")
        readings.send(MenuBarNetworkState(connection: .wifi, wifiName: "Office"))
        XCTAssertEqual(manager.hudState, .wifi(name: "Office"))
        readings.send(MenuBarNetworkState(connection: .offline))
        XCTAssertEqual(manager.hudState, .noConnection)
        manager.dismissNoConnection()
        readings.send(MenuBarNetworkState(connection: .offline, isConstrained: true))
        XCTAssertEqual(manager.hudState, .hidden, "Do not reopen a dismissed offline HUD")
        readings.send(MenuBarNetworkState(connection: .wifi, wifiName: "Phone", isHotspot: true))
        XCTAssertEqual(manager.hudState, .hotspot(name: "Phone"))
        readings.send(MenuBarNetworkState(connection: .ethernet))
        XCTAssertEqual(manager.hudState, .hidden)
        manager.stopMonitoring()
        readings.send(MenuBarNetworkState(connection: .offline))
        XCTAssertEqual(manager.hudState, .hidden, "Stopping must detach from the shared source")
        manager.startMonitoring(updates: readings.eraseToAnyPublisher())
        readings.send(MenuBarNetworkState(connection: .wifi, wifiName: "Home"))
        XCTAssertEqual(manager.hudState, .hidden, "A restart treats the next reading as initial")
        manager.stopMonitoring()
    }
}
