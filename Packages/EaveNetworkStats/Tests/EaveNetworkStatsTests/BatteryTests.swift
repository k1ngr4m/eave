import AppKit
import XCTest
@testable import EaveNetworkStats

final class BatteryTests: XCTestCase {
    func testPowerSourceTransitionsAndReaderLifecycle() throws {
        _ = NSApplication.shared
        let monitor = BatteryMonitor()
        var value = Battery_Usage()
        value.level = 1
        value.isCharged = true
        value.powerSource = "AC Power"
        value.maxCapacity = 5151
        value.designedCapacity = 6075
        value.health = 85
        value.cycles = 151
        value.voltage = 12.54
        value.batteryPower = 0.62
        value.ACwatts = 65
        value.adapterPower = 20.97
        value.adapterVoltage = 20
        value.temperature = 33
        monitor.popup.usageCallback(value)
        drain()
        monitor.popup.appear()
        let pluggedHeight = monitor.panelSize.height
        XCTAssertTrue(text(in: monitor.panel).contains("5151 mAh"))
        XCTAssertTrue(text(in: monitor.panel).contains("85%"))
        XCTAssertTrue(text(in: monitor.panel).contains("20.97 W / 65 W"))
        XCTAssertTrue(text(in: monitor.panel).contains(localizedString("Fully charged")))

        if let directory = ProcessInfo.processInfo.environment["EAVE_STATS_CAPTURE_DIR"] {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: monitor.panelSize),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = monitor.panel
            window.orderFront(nil)
            monitor.panel.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(monitor.panel.bitmapImageRepForCachingDisplay(in: monitor.panel.bounds))
            monitor.panel.cacheDisplay(in: monitor.panel.bounds, to: bitmap)
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent("battery.png"))
            window.orderOut(nil)
        }

        value.isBatteryPowered = true
        value.isCharged = false
        value.powerSource = "Battery Power"
        value.level = 0.8
        value.timeToEmpty = 120
        monitor.popup.usageCallback(value)
        drain()
        monitor.popup.appear()
        XCTAssertLessThan(monitor.panelSize.height, pluggedHeight)
        XCTAssertFalse(text(in: monitor.panel).contains("20.97 W / 65 W"))
        XCTAssertTrue(text(in: monitor.panel).contains(localizedString("Battery Power")))

        value.isBatteryPowered = false
        value.isCharging = true
        value.powerSource = "AC Power"
        value.timeToCharge = 30
        monitor.popup.usageCallback(value)
        drain()
        monitor.popup.appear()
        XCTAssertEqual(monitor.panelSize.height, pluggedHeight)
        XCTAssertTrue(text(in: monitor.panel).contains(localizedString("Charging")))

        var openedSettings = false
        monitor.openSettings = { openedSettings = true }
        NotificationCenter.default.post(name: .toggleSettings, object: nil, userInfo: ["module": "Battery"])
        XCTAssertTrue(openedSettings)
        monitor.setVisible(true)
        XCTAssertTrue(monitor.usageReader.active)
        XCTAssertTrue(monitor.processReader.active)
        monitor.setVisible(false)
        XCTAssertFalse(monitor.usageReader.active)
        XCTAssertFalse(monitor.processReader.active)
    }

    private func text(in view: NSView) -> [String] {
        (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap { text(in: $0) }
    }

    private func drain() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }
}
