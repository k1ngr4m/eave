import AppKit
import CoreLocation
import XCTest
@testable import EaveNetworkStats

final class NetworkTests: XCTestCase {
    func testOriginalNetworkSemanticsAndSettings() throws {
        let suite = "app.eave.network.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        Store.shared = Store(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = NSApplication.shared
        XCTAssertEqual(Units(bytes: 1_000_000).getReadableTuple(base: .byte).1, "MB/s")
        XCTAssertEqual(Units(bytes: 125_000).getReadableTuple(base: .bit).1, "Mb/s")
        XCTAssertEqual(SizeUnit.GB.toBytes(1), 1_000_000_000)

        // Exercise the actual popup buffers and averaging, including hidden-panel replay.
        let popup = Popup(.network)
        for value in 1...100 {
            popup.connectivityCallback(Network_Connectivity(status: true, latency: Double(value), jitter: Double(value) / 2))
            popup.usageCallback(Network_Usage(bandwidth: Bandwidth(upload: Int64(value), download: Int64(value * 2))))
        }
        drain()
        popup.appear()
        let latencies: [Double] = field(popup, "latency")
        XCTAssertEqual(latencies.count, 90)
        XCTAssertEqual(latencies.first, 11)
        let latency: ValueField? = field(popup, "latencyField")
        let jitter: ValueField? = field(popup, "jitterField")
        XCTAssertEqual(latency?.stringValue, "55.5 ms")
        XCTAssertEqual(jitter?.stringValue, "27.75 ms")
        let chart: NetworkChartView? = field(popup, "chart")
        let input: LineChartView = field(chart!, "inChart")
        let points: [DoubleValue?] = field(input, "points")
        XCTAssertEqual(points.count, 180)
        let grid: GridChartView? = field(popup, "connectivityChart")
        let cells: [ColorValue?] = field(grid!, "values")
        XCTAssertEqual(cells.count, 90)
        XCTAssertTrue(cells.allSatisfy { $0 != nil })

        // Drive the original controls instead of merely checking stored keys.
        let popupSettings = popup.settings()!
        choose(popupSettings, action: "togglechartHistory:", key: "60")
        drain()
        let resized: [DoubleValue?] = field(input, "points")
        XCTAssertEqual(resized.count, 60)
        XCTAssertEqual(Store.shared.int(key: "Network_chartHistory", defaultValue: 0), 60)
        let settings = Settings(.network)
        settings.load(widgets: [.networkChart, .speed])
        var processUpdates = 0
        settings.callbackWhenUpdateNumberOfProcesses = { processUpdates += 1 }
        choose(settings, action: "changeNumberOfProcesses:", key: "15")
        XCTAssertEqual(processUpdates, 1)
        XCTAssertEqual(Store.shared.int(key: "Network_processes", defaultValue: 0), 15)
        choose(settings, action: "toggleBase:", key: "bit")
        choose(settings, action: "toggleSpeedUnit:", key: "MB")
        XCTAssertEqual(Store.shared.string(key: "Network_base", defaultValue: ""), "bit")
        XCTAssertEqual(Store.shared.string(key: "Network_speedUnit", defaultValue: ""), "MB")
        var interval = 0
        settings.setInterval = { interval = $0 }
        choose(settings, action: "changeICMPUpdateInterval:", key: "5")
        XCTAssertEqual(interval, 5)
        choose(settings, action: "changeConnectivityMode:", key: "http")
        XCTAssertEqual(Store.shared.string(key: "Network_connectivityMode", defaultValue: ""), "http")

        // Latest totals survive reader recreation; reset persists immediately and schedules a calendar boundary.
        var usage = Network_Usage(total: Bandwidth(upload: 123_000_000, download: 456_000_000))
        DB.shared.insert(key: "Network@UsageReader", value: usage, force: true)
        let reader = UsageReader(.network)
        defer { reader.stop(); reader.terminate() }
        XCTAssertEqual(reader.usage.total.download, usage.total.download)
        let permissionUpdate = expectation(description: "Permission metadata preserves sampled bandwidth")
        reader.usage.bandwidth = Bandwidth(upload: 3_000_000_000, download: 4_000_000_000)
        reader.value = Network_Usage(bandwidth: Bandwidth(upload: 50, download: 100))
        reader.callbackHandler = { value in
            XCTAssertEqual(value?.bandwidth.upload, 50)
            XCTAssertEqual(value?.bandwidth.download, 100)
            permissionUpdate.fulfill()
        }
        reader.active = true
        reader.locationManagerDidChangeAuthorization(CLLocationManager())
        wait(for: [permissionUpdate], timeout: 2)
        reader.active = false
        reader.callbackHandler = { _ in }
        Store.shared.set(key: "Network_usageReset", value: "Once per day")
        reader.resetTotalNetworkUsage()
        let saved = try JSONDecoder().decode(Network_Usage.self, from: XCTUnwrap(defaults.data(forKey: "snapshot.Network@UsageReader")))
        XCTAssertEqual(saved.total.upload, 0)
        XCTAssertEqual(saved.total.download, 0)
        XCTAssertEqual(saved.bandwidth.download, 100)
        XCTAssertEqual(reader.value?.total.download, 0)
        let next = Date(timeIntervalSince1970: Double(Store.shared.int(key: "Network_usageReset_next", defaultValue: 0)))
        XCTAssertEqual(next, Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())))
        usage.total.download = 789
        DB.shared.insert(key: "Network@UsageReader", value: usage, force: true)
        Store.shared.set(key: "Network_usageReset_next", value: Int(Date().timeIntervalSince1970) - 1)
        let overdue = UsageReader(.network)
        defer { overdue.stop(); overdue.terminate() }
        XCTAssertEqual(overdue.usage.total.download, 0)
    }

    private func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    private func field<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    private func choose(_ view: NSView, action: String, key: String) {
        let controls = descendants(view).compactMap { $0 as? NSPopUpButton }
        guard let control = controls.first(where: { $0.action == NSSelectorFromString(action) }),
              let item = control.itemArray.first(where: { $0.representedObject as? String == key }) else {
            XCTFail("Missing original control: \(action) \(key)"); return
        }
        control.select(item)
        XCTAssertTrue(NSApp.sendAction(control.action!, to: control.target, from: item))
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
