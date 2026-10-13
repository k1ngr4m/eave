import AppKit
import XCTest
@testable import EaveNetworkStats

final class MemoryDiskTests: XCTestCase {
    func testOriginalMemoryDiskControlsRenderingAndReaders() throws {
        _ = NSApplication.shared
        let suite = "app.eave.memory-disk.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        Store.shared = Store(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(diskRate(1_500, previous: 1_000, elapsed: 2), 250)
        XCTAssertEqual(diskRate(10, previous: 1_000, elapsed: 1), 0)
        XCTAssertEqual(diskRate(1_500, previous: 1_000, elapsed: 0), 0)
        XCTAssertEqual(diskRate(1_500, previous: 1_000, elapsed: 60), 0)

        let memory = MemoryDiskMonitor(module: .RAM)
        let disk = MemoryDiskMonitor(module: .disk)
        defer { memory.setEnabled(false); disk.setEnabled(false) }
        let value = RAM_Usage(total: 16e9, used: 10e9, free: 6e9, active: 5e9,
                              inactive: 1e9, wired: 2e9, compressed: 3e9, app: 5e9, cache: 1e9,
                              swap: Swap(total: 2e9, used: 1e9, free: 1e9),
                              pressure: Pressure(level: 2, value: .warning), swapins: 5, swapouts: 10)
        memory.receive(value)
        let disks = Disks()
        var root = drive(uuid: "root", mediaName: "Main", BSDName: "disk3s1", root: true, size: 1_000, free: 600)
        root.activity = stats(read: 1_000_000, write: 2_000_000)
        let external = drive(uuid: "external", mediaName: "External", BSDName: "disk4", removable: true, size: 2_000, free: 500)
        disks.array = [root, external]
        disk.receiveCapacity(disks)
        disk.receiveActivity(disks)
        drain()
        XCTAssertEqual(memory.utilization, 0.625)
        XCTAssertEqual(disk.utilization, 0.4)
        XCTAssertEqual(disk.rates.read, 1_000_000)

        let ramSettings = try XCTUnwrap(memory.settings as? RAMSettings)
        let diskSettings = try XCTUnwrap(disk.settings as? DiskSettings)
        ramSettings.load(widgets: [.barChart, .text])
        diskSettings.load(widgets: [.speed, .text])
        choose(ramSettings, action: "changeUpdateInterval:", key: "5")
        choose(ramSettings, action: "changeUpdateTopInterval:", key: "3")
        XCTAssertEqual(memory.usageReader.interval, 5)
        XCTAssertEqual(memory.memoryProcessReader.interval, 3)
        choose(diskSettings, action: "changeUpdateInterval:", key: "10")
        choose(diskSettings, action: "changeSMARTUpdateInterval:", key: "30")
        XCTAssertEqual(disk.capacityReader.interval, 10)
        XCTAssertEqual(disk.smartReader.interval, 30)
        choose(diskSettings, action: "toggleBase:", key: "bit")
        XCTAssertTrue(disk.formattedSpeed(125_000).contains("Mb/s"))
        diskSettings.setList(disks)
        drain()
        let picker = try XCTUnwrap(descendants(diskSettings).compactMap { $0 as? NSPopUpButton }
            .first { $0.action == NSSelectorFromString("handleSelection:") })
        picker.selectItem(withTitle: "External")
        XCTAssertTrue(picker.sendAction(picker.action!, to: picker.target))
        XCTAssertEqual(disk.utilization, 0.75)
        // Replacing a same-sized mount list must replace, not append, selector items.
        disks.array = [root, drive(uuid: "new", mediaName: "New", BSDName: "disk5")]
        diskSettings.setList(disks)
        drain()
        XCTAssertEqual(picker.itemTitles, ["Main", "New"])
        XCTAssertEqual(picker.titleOfSelectedItem, "Main")

        for monitor in [memory, disk] {
            XCTAssertTrue(monitor.widgets.items.contains { $0.type == .memory })
            for widget in monitor.widgets.items { widget.isActive = true }
            if monitor.module == .RAM { monitor.receive(value) }
            else { monitor.receiveCapacity(disks); monitor.receiveActivity(disks) }
            drain()
            XCTAssertGreaterThan(monitor.widgets.size.width, 30)
            XCTAssertEqual(monitor.widgets.size.height, 22)
            XCTAssertNotNil(monitor.widgets.image.tiffRepresentation)
            monitor.showSettings()
            drain()
            let window = try XCTUnwrap(NSApp.windows.first { $0.title == localizedString(monitor.module.stringValue) + " — " + localizedString("Settings") })
            window.appearance = NSAppearance(named: .darkAqua)
            let tabs = try XCTUnwrap(descendants(window.contentView!).compactMap { $0 as? NSTabView }.first)
            XCTAssertEqual(tabs.numberOfTabViewItems, 5)
            if let directory = ProcessInfo.processInfo.environment["EAVE_STATS_CAPTURE_DIR"] {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                for tab in tabs.tabViewItems {
                    tabs.selectTabViewItem(tab)
                    window.contentView!.layoutSubtreeIfNeeded()
                    drain()
                    try capture(window.contentView!, to: "\(directory)/\(monitor.module.stringValue)-\(tab.identifier!).png")
                }
            }
            window.close()
            for widget in monitor.widgets.items { widget.isActive = false }
            monitor.widgets.scheduleRender()
            drain()
            XCTAssertEqual(monitor.widgets.size, .zero)
        }

        if ProcessInfo.processInfo.environment["EAVE_STATS_LIVE"] == "1" {
            memory.setEnabled(true); disk.setEnabled(true)
            memory.setVisible(true); disk.setVisible(true)
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline && (memory.memoryProcessReader.value?.isEmpty != false || disk.capacityReader.value?.count ?? 0 == 0) { drain() }
            let sampleDeadline = Date().addingTimeInterval(2.5)
            while Date() < sampleDeadline { drain() }
            print("Disk live rates: \(disk.rates), SMART drives: \(disk.smartReader.value?.count ?? 0), processes: \(disk.diskProcessReader.value?.count ?? 0)")
            XCTAssertNotNil(disk.diskProcessReader.value)
            XCTAssertGreaterThan(memory.usageReader.value?.total ?? 0, 0)
            XCTAssertFalse(memory.memoryProcessReader.value?.isEmpty ?? true)
            XCTAssertGreaterThan(disk.capacityReader.value?.count ?? 0, 0)
            for monitor in [memory, disk] {
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: monitor.panelSize), styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .darkAqua)
                window.contentView = monitor.panel
                window.orderFront(nil)
                monitor.setVisible(true)
                drain()
                if let directory = ProcessInfo.processInfo.environment["EAVE_STATS_CAPTURE_DIR"] {
                    try capture(monitor.panel, to: "\(directory)/\(monitor.module.stringValue)-Popup.png")
                }
                monitor.setVisible(false)
                window.orderOut(nil)
            }
            XCTAssertFalse(memory.memoryProcessReader.active)
            XCTAssertFalse(disk.diskProcessReader.active)
            memory.setEnabled(false); disk.setEnabled(false)
            XCTAssertFalse(memory.usageReader.active)
            XCTAssertFalse(disk.activityReader.active)
        }
    }

    private func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func choose(_ view: NSView, action: String, key: String) {
        guard let control = descendants(view).compactMap({ $0 as? NSPopUpButton }).first(where: { $0.action == NSSelectorFromString(action) }),
              let item = control.itemArray.first(where: { $0.representedObject as? String == key }) else {
            XCTFail("Missing control \(action) / \(key)"); return
        }
        control.select(item)
        XCTAssertTrue(control.sendAction(control.action!, to: control.target))
    }
    private func capture(_ view: NSView, to path: String) throws {
        if let window = view.window {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try capture.run()
            capture.waitUntilExit()
            if capture.terminationStatus == 0 { return }
        }
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
