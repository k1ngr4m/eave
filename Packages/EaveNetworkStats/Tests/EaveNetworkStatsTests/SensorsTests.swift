import AppKit
import XCTest
@testable import EaveNetworkStats

final class SensorsTests: XCTestCase {
    func testReadOnlySensorsSettingsWidgetsAndLifecycle() throws {
        _ = NSApplication.shared
        let suite = "app.eave.sensors.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        Store.shared = Store(defaults: defaults)
        let oldKeys = HardwareAccess.smcKeys
        let oldValue = HardwareAccess.smcValue
        let oldString = HardwareAccess.smcString
        let lock = NSLock()
        var readings: [String: Double] = ["TA0P": 42, "TZZZ": 99, "PSTR": 20, "FNum": 1, "F0Ac": 1500, "F0Mn": 1000, "F0Mx": 6000]
        var calls = 0
        HardwareAccess.smcKeys = { ["TA0P", "TZZZ", "PSTR", "F0Ac"] }
        HardwareAccess.smcString = { _ in "Test fan" }
        HardwareAccess.smcValue = { key in lock.withLock { calls += 1; return readings[key] } }
        Store.shared.set(key: "Sensors_hid", value: false)
        Store.shared.set(key: "Sensors_sensor", value: "TA0P")
        Store.shared.set(key: "sensor_TA0P", value: true)
        Store.shared.set(key: "sensor_F0Ac", value: true)
        HardwareAccess.temperatureUnit = "celsius"
        let monitor = SensorsMonitor()
        defer {
            monitor.setEnabled(false)
            drain()
            HardwareAccess.smcKeys = oldKeys
            HardwareAccess.smcValue = oldValue
            HardwareAccess.smcString = oldString
            defaults.removePersistentDomain(forName: suite)
        }
        monitor.setEnabled(true)
        wait { monitor.hottestTemperature != nil }
        XCTAssertEqual(monitor.hottestTemperature, 42)
        XCTAssertEqual(monitor.widgets.items.count, 5)
        XCTAssertEqual(monitor.widgets.active.map(\.type), [.mini])
        let mini = monitor.widgets.items.first { $0.type == .mini }!.item as! Mini
        XCTAssertEqual(field(mini, "_value") as Double, 0.42)

        monitor.settings.load(widgets: [.mini, .stack])
        choose(monitor.settings, action: "changeUpdateInterval:", key: "1")
        XCTAssertEqual(Store.shared.int(key: "Sensors_updateInterval", defaultValue: 0), 1)
        toggle(monitor.settings, action: "toggleuUnknownSensors:", on: true)
        wait { monitor.hottestTemperature == 99 }
        XCTAssertNotNil(descendants(monitor.settings).first { $0.identifier?.rawValue == "TZZZ" })
        toggle(monitor.settings, action: "toggleuUnknownSensors:", on: false)
        wait { monitor.hottestTemperature == 42 }
        XCTAssertNil(descendants(monitor.settings).first { $0.identifier?.rawValue == "TZZZ" })
        #if arch(arm64)
        toggle(monitor.settings, action: "toggleHID:", on: true)
        XCTAssertTrue(Store.shared.bool(key: "Sensors_hid", defaultValue: false))
        drain()
        toggle(monitor.settings, action: "toggleHID:", on: false)
        wait { monitor.isEnabled && monitor.hottestTemperature == 42 }
        #endif

        choose(monitor.settings, action: "handleSelection:", key: "F0Ac")
        choose(monitor.settings, action: "toggleFanValue:", key: "percentage")
        drain()
        XCTAssertEqual(field(mini, "_value") as Double, 0.25)
        XCTAssertEqual(field(mini, "_suffix") as String, "%")
        choose(monitor.settings, action: "toggleFanValue:", key: "rpm")
        drain()
        XCTAssertEqual(field(mini, "_value") as Double, 15)
        choose(monitor.settings, action: "handleSelection:", key: "TA0P")
        HardwareAccess.temperatureUnit = "fahrenheit"
        drain()
        XCTAssertEqual(field(mini, "_value") as Double, 1.076, accuracy: 0.0001)
        XCTAssertTrue(monitor.sensorDescription.contains("107.6"))

        let selector = monitor.widgets.selector {}
        for item in monitor.widgets.items where !item.isActive {
            XCTAssertTrue(descendants(selector).first { $0.identifier?.rawValue == item.type.rawValue }!.accessibilityPerformPress())
        }
        drain()
        let stack = monitor.widgets.items.first { $0.type == .stack }!.item as! StackWidget
        var values: [Stack_t] = field(stack, "values")
        XCTAssertEqual(Set(values.map(\.key)), ["TA0P", "F0Ac"])
        Store.shared.set(key: "stack_F0Ac_index", value: -2)
        drain()
        values = field(stack, "values")
        XCTAssertEqual(values.first?.key, "F0Ac")
        XCTAssertGreaterThan(monitor.widgets.size.width, 50)
        XCTAssertEqual(monitor.widgets.size.height, 22)
        let recreated = SensorsWidgets()
        recreated.receive([Sensor(key: "TA0P", name: "Ambient", value: 42, group: .sensor, type: .temperature, platforms: Platform.all)])
        drain()
        XCTAssertEqual(recreated.active.count, 5)
        XCTAssertEqual(Store.shared.string(key: "Sensors_sensor", defaultValue: ""), "TA0P")

        let popupSettings = monitor.popup.settings()!
        let popupToggle = descendants(popupSettings).compactMap { $0 as? NSSwitch }.first { $0.identifier?.rawValue == "TA0P" }!
        popupToggle.state = .off
        XCTAssertTrue(popupToggle.sendAction(popupToggle.action!, to: popupToggle.target))
        XCTAssertFalse(Store.shared.bool(key: "sensor_TA0P_popup", defaultValue: true))
        let popupRows: [String: NSView] = field(monitor.popup, "list")
        XCTAssertNil(popupRows["TA0P"])

        lock.withLock { readings["TA0P"] = nil; readings["F0Ac"] = .nan }
        wait { monitor.hottestTemperature == nil }
        drain()
        XCTAssertTrue((field(mini, "_value") as Double).isNaN)
        values = field(stack, "values")
        XCTAssertTrue(values.allSatisfy { $0.value == "—" })
        XCTAssertTrue(SensorsReader.validValue(.infinity, type: .fan).isNaN)
        XCTAssertTrue(SensorsReader.validValue(-1, type: .temperature).isNaN)
        XCTAssertTrue(SensorsReader.validValue(200, type: .temperature).isNaN)
        XCTAssertTrue(SensorsReader.validValue(6, type: .temperature, group: .CPU).isNaN)
        XCTAssertEqual(SensorsReader.appleSiliconPower(currentEnergy: 12, previousEnergy: 6, elapsed: 2), 3)
        XCTAssertTrue(SensorsReader.appleSiliconPower(currentEnergy: 1, previousEnergy: 6, elapsed: 2).isNaN)
        XCTAssertTrue(SensorsReader.appleSiliconPower(currentEnergy: 12, previousEnergy: 6, elapsed: 0).isNaN)
        let fan = Fan(id: 0, key: "F0Ac", name: "Fan", minSpeed: 1000, maxSpeed: 0, value: 1500)
        XCTAssertEqual(fan.percentage, 0)

        // Fan notification thresholds are fractions of maximum RPM, not raw RPM.
        var runningFan = fan
        runningFan.maxSpeed = 6000
        let notices = SensorsNotifications(.sensors)
        Store.shared.set(key: "sensor_F0Ac_notification", value: "0.9")
        notices.setup([runningFan])
        notices.usageCallback([runningFan])
        let streaks = Mirror(reflecting: notices).superclassMirror!.children.first { $0.label == "streak" }!.value as! [String: Int]
        XCTAssertEqual(streaks["Stats_Sensors_F0Ac"], 0)
        Store.shared.set(key: "sensor_F0Ac_notification", value: "")

        monitor.setEnabled(false)
        drain()
        monitor.popup.appear()
        XCTAssertTrue(descendants(monitor.popup).compactMap { $0 as? ValueField }.allSatisfy { $0.stringValue == "—" }, "Reopening a stopped popup must not replay old readings")
        let stoppedCalls = lock.withLock { calls }
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        XCTAssertEqual(lock.withLock { calls }, stoppedCalls)
        lock.withLock { readings["TA0P"] = 45; readings["FNum"] = 0 }
        monitor.setEnabled(true)
        wait { monitor.hottestTemperature == 45 }
        XCTAssertTrue(descendants(monitor.settings).first { $0.identifier?.rawValue == "fanPreferences" }!.isHidden)
        monitor.setEnabled(false)
        drain()
        monitor.showSettings()
        XCTAssertTrue(monitor.settingsVisible)
        let window = try XCTUnwrap(field(monitor, "settingsWindow") as NSWindow?)
        let tabs = window.contentView!.subviews.first { $0 is NSTabView } as! NSTabView
        XCTAssertEqual(tabs.numberOfTabViewItems, 4)
        for index in 0..<4 {
            tabs.selectTabViewItem(at: index)
            window.contentView!.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(tabs.frame.width, 500)
        }
        window.close()
        XCTAssertFalse(monitor.settingsVisible)
        for item in monitor.widgets.active { item.toggle(false) }
        drain()
        XCTAssertEqual(monitor.widgets.size, .zero)

        // An empty machine has no fan controls and a readable empty-state panel.
        monitor.receive([])
        XCTAssertNil(monitor.hottestTemperature)
        XCTAssertTrue(descendants(monitor.popup).compactMap { $0 as? NSTextField }.contains { $0.stringValue == localizedString("No readable data on this Mac.") })
    }

    private func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    private func wait(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { drain() }
        XCTAssertTrue(condition())
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func field<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    private func choose(_ view: NSView, action: String, key: String) {
        let control = descendants(view).compactMap { $0 as? NSPopUpButton }.first { $0.action == NSSelectorFromString(action) }!
        control.select(control.itemArray.first { $0.representedObject as? String == key }!)
        XCTAssertTrue(control.sendAction(control.action!, to: control.target))
    }
    private func toggle(_ view: NSView, action: String, on: Bool) {
        let control = descendants(view).compactMap { $0 as? NSSwitch }.first { $0.action == NSSelectorFromString(action) }!
        control.state = on ? .on : .off
        XCTAssertTrue(control.sendAction(control.action!, to: control.target))
    }
}
