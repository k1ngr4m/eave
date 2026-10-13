import AppKit
import XCTest
@testable import EaveNetworkStats

final class ProcessorTests: XCTestCase {
    func testOriginalProcessorControlsWidgetsAndReaders() throws {
        _ = NSApplication.shared
        let suite = "app.eave.processor.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        Store.shared = Store(defaults: defaults)
        defer { defaults.removePersistentDomain(forName: suite) }
        let cpu = ProcessorWidgets(module: .CPU)
        let gpu = ProcessorWidgets(module: .GPU)
        for widgets in [cpu, gpu] {
            XCTAssertEqual(widgets.items.count, 7)
            XCTAssertEqual(widgets.active.map(\.type), [.mini])
            let selector = widgets.selector {}
            for item in widgets.items where !item.isActive {
                let control = descendants(selector).first { $0.identifier?.rawValue == item.type.rawValue }!
                XCTAssertTrue(control.accessibilityPerformPress())
            }
            XCTAssertEqual(widgets.active.count, 7)
        }
        let load = CPU_Load(totalUsage: 0.75, usagePerCore: [0.25, 0.5, 0.75, 1],
                            usageECores: 0.375, usagePCores: 0.875, systemLoad: 0.25, userLoad: 0.5, idleLoad: 0.25)
        cpu.receive(load)
        let settings = CPUSettings(.CPU)
        settings.load(widgets: cpu.active.map(\.type))
        var interval = 0
        settings.setInterval = { interval = $0 }
        choose(settings, action: "changeUpdateInterval:", key: "3")
        XCTAssertEqual(interval, 3)
        settings.load(widgets: cpu.active.map(\.type))
        let intervalControl = descendants(settings).compactMap { $0 as? NSPopUpButton }.first { $0.action == NSSelectorFromString("changeUpdateInterval:") }!
        XCTAssertEqual(intervalControl.selectedItem?.representedObject as? String, "3")
        choose(settings, action: "changeNumberOfProcesses:", key: "15")
        XCTAssertEqual(Store.shared.int(key: "CPU_processes", defaultValue: 0), 15)
        let toggle = NSSwitch()
        toggle.state = .on
        settings.toggleSplitValue(toggle)
        drain()
        let bars = cpu.items.first { $0.type == .barChart }!.item as! BarChart
        let split: [[ColorValue]] = field(bars, "_value")
        XCTAssertEqual(split[0].map(\.value), [0.25, 0.5])
        settings.toggleUsagePerCore(toggle)
        drain()
        let perCore: [[ColorValue]] = field(bars, "_value")
        XCTAssertEqual(perCore.map { $0[0].value }, load.usagePerCore)
        XCTAssertFalse(Store.shared.bool(key: "CPU_splitValue", defaultValue: true))
        #if arch(arm64)
        settings.toggleClustersGroup(toggle)
        drain()
        let clusters: [[ColorValue]] = field(bars, "_value")
        XCTAssertEqual(clusters.map { $0[0].value }, [0.375, 0.875])
        XCTAssertFalse(Store.shared.bool(key: "CPU_usagePerCore", defaultValue: true))
        #endif
        let line = cpu.items.first { $0.type == .lineChart }!.item as! LineChart
        let chart: LineChartView = field(line, "chart")
        let points: [DoubleValue?] = field(chart, "points")
        XCTAssertEqual(points.compactMap { $0 }.count, 1, "Settings changes must not append samples")
        XCTAssertEqual(cpu.size.height, 22)
        XCTAssertGreaterThan(cpu.size.width, 0)

        let popup = CPUPopup(.CPU)
        popup.loadCallback(load)
        popup.appear()
        drain()
        let user: NSTextField? = field(popup, "userField")
        XCTAssertEqual(user?.stringValue, "50%")
        var selected = ""
        let gpuSettings = GPUSettings(.GPU)
        gpuSettings.load(widgets: [.text])
        gpuSettings.selectedGPUHandler = { selected = $0 }
        let devices = GPUs()
        var info = GPU_Info(id: "1", type: "i", IOClass: "AGX", model: "GPU One", cores: 10,
                            utilization: 0.75, render: 0.5, tiler: 0.25)
        info.fps = 59.8
        devices.list = [info]
        gpuSettings.setList(devices)
        drain()
        choose(gpuSettings, action: "handleSelection:", key: "GPU One")
        XCTAssertEqual(selected, "GPU One")
        let template = descendants(gpuSettings).first { $0.identifier?.rawValue == "GPUTextTemplate" } as! NSTextField
        template.stringValue = "$usage / $render / $tiler / $fps"
        gpuSettings.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: template))
        gpu.receive(info)
        drain()
        let text = gpu.items.first { $0.type == .text }!.item as! TextWidget
        let displayed: String = field(text, "value")
        XCTAssertEqual(displayed, "75% / 50% / 25% / 60")
        devices.list = [GPU_Info(id: "2", type: "e", IOClass: "AGX", model: "GPU Two", cores: 20, utilization: 0.5)]
        gpuSettings.setList(devices)
        drain()
        choose(gpuSettings, action: "handleSelection:", key: "GPU Two")
        XCTAssertEqual(selected, "GPU Two", "Refresh replacement devices even when count is unchanged")
        cpu.items.first { $0.type == .barChart }!.position = -1
        XCTAssertEqual(ProcessorWidgets(module: .CPU).active.first?.type, .barChart)
        let reader = CPULoadReader(.CPU)
        reader.read()
        Thread.sleep(forTimeInterval: 0.1)
        reader.read()
        let actual = try XCTUnwrap(reader.value)
        XCTAssertTrue((0...1).contains(actual.totalUsage))
        XCTAssertEqual(actual.totalUsage, actual.systemLoad + actual.userLoad)
        XCTAssertFalse(actual.usagePerCore.isEmpty)
    }

    private func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func field<T>(_ object: Any, _ name: String) -> T {
        Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
    }
    private func choose(_ view: NSView, action: String, key: String) {
        let control = descendants(view).compactMap { $0 as? NSPopUpButton }.first { $0.action == NSSelectorFromString(action) }!
        let item = control.itemArray.first { $0.representedObject as? String == key }!
        control.select(item)
        XCTAssertTrue(control.sendAction(control.action!, to: control.target))
    }
}
