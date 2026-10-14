"""Run: python3 tests/test_monitoring.py [--live] [--ui].
--ui --modules-only checks module switches without opening detail windows.
--ui also checks the real manager and renders the overview in an isolated defaults suite.
First build the Debug app with -derivedDataPath .build/stats-monitoring for Defaults.o.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
sources = [
    'components/Stats/MonitoringModels.swift', 'components/Stats/MonitoringReader.swift',
    'components/Stats/MonitoringSensorCatalog.swift', 'components/Stats/StatsFormatting.swift',
    'utils/SMC.swift', 'utils/CPUSensorCollector.swift', 'utils/AppleHardwareInfo.swift',
    'utils/IOReportBridging.swift', 'utils/IOKitHelpers.swift',
]
main = r'''
import Foundation
import Darwin

var counter = MonitoringCounter()
assert(counter.rates(["a": (1000, 2000)], at: 10).isEmpty)
let rates = counter.rates(["a": (1400, 2200), "new": (999999, 999999)], at: 12)
assert(rates["a"]!.0 == 200 && rates["a"]!.1 == 100)
assert(rates["new"] == nil)
assert(counter.rates(["a": (1, 2)], at: 13)["a"]!.0 == 0)
assert(counter.rates([:], at: 14).isEmpty)
assert(counter.rates(["a": (9000, 9000)], at: 15).isEmpty)
assert(counter.rates(["a": (9000, 9000)], at: 15).isEmpty)

let load = MonitoringParsing.cpuTicks([10, 20, 60, 10], previous: [0, 0, 0, 0])!
assert(load.user == 20 && load.system == 20 && load.idle == 60)
let rollover = MonitoringParsing.cpuTicks([5, 0, 0, 0], previous: [UInt32.max - 4, 0, 0, 0])!
assert(rollover.user == 100)
assert(MonitoringParsing.cpuTicks([1, 2, 3, 4], previous: []).isNil)
assert(MonitoringParsing.cpuTicks([1, 2, 3, 4], previous: [1, 2, 3, 4]).isNil)

assert(MonitoringParsing.memoryProcess("123* Google Chrome 1.5G+")!.value == 1.5 * 1073741824)
assert(MonitoringParsing.memoryProcess("456 * Process With Spaces 512M-")!.label == "Process With Spaces")
assert(MonitoringParsing.memoryProcess("1 launchd 900K")!.value == 921600)
assert(MonitoringParsing.memoryProcess("PID COMMAND MEM") == nil)
assert(MonitoringParsing.memoryProcess("1 foo NaNG") == nil)
assert(MonitoringParsing.memoryProcess("1 foo -1G") == nil)
assert(MonitoringUnit.temperature.string(0, fahrenheit: true) == "32.0°F")
assert(MonitoringUnit.rate.string(nil) == "—")
assert(MonitoringUnit.percent.string(.nan) == "—")
assert(MonitoringModule.allCases.count == 6)
assert(MonitoringModule.ordered([]) == MonitoringModule.allCases)
assert(MonitoringModule.ordered(["network", "cpu", "network", "removed"]) == [.network, .cpu, .memory, .gpu, .disk, .sensors])
let initialOrder = MonitoringModule.allCases.map(\.rawValue)
let movedRight = MonitoringModule.moving(.cpu, to: .network, in: initialOrder)
assert(movedRight == ["memory", "gpu", "disk", "network", "cpu", "sensors"])
assert(MonitoringModule.moving(.cpu, to: .memory, in: movedRight) == initialOrder)
assert(MonitoringModule.moving(.cpu, to: .cpu, in: initialOrder) == initialOrder)
assert(MonitoringModule.moving(.sensors, to: .cpu, in: []) == ["sensors", "cpu", "memory", "gpu", "disk", "network"])
let reverseOrder = Array(MonitoringModule.allCases.reversed())
assert(MonitoringModule.ordered(reverseOrder.map(\.rawValue)) == reverseOrder)
for enabled in [false, true] {
    for open in [false, true] {
        for selected in [false, true] {
            for stop in [false, true] {
                assert(MonitoringActivity.shouldRun(enabled: enabled, hasModules: true, sleeping: false,
                    notchIsOpen: open, statsSelected: selected, stopWhenClosed: stop) == (enabled && selected && (open || !stop)))
            }
        }
    }
}
assert(!MonitoringActivity.shouldRun(enabled: true, hasModules: false, sleeping: false, notchIsOpen: true, statsSelected: true, stopWhenClosed: false))
assert(!MonitoringActivity.shouldRun(enabled: true, hasModules: true, sleeping: true, notchIsOpen: true, statsSelected: true, stopWhenClosed: false))
assert(monitoringSensorCatalog.contains { $0.key == "Tp09" && $0.supports("m1Pro") })
assert(!monitoringSensorCatalog.first { $0.key == "Tp09" && $0.platforms == "m1Gen" }!.supports("m2"))
print("Monitoring counter, CPU rollover, process parsing, units and lifecycle checks passed.")

if CommandLine.arguments.contains("--live") {
    let reader = MonitoringReader()
    let modules = Set(MonitoringModule.allCases).subtracting([.network, .sensors])
    _ = reader.read(modules: modules, detail: nil)
    Thread.sleep(forTimeInterval: 1)
    let samples = reader.read(modules: modules, detail: nil)
    assert(samples.count == 4)
    assert(samples[.cpu]!.value != nil && (0...100).contains(samples[.cpu]!.value!))
    assert(samples[.memory]!.value != nil && (0...100).contains(samples[.memory]!.value!))
    for module in modules {
        let sample = samples[module]!
        print("\(module.rawValue): \(module.unit.string(sample.value)), sections=\(sample.sections.count), rows=\(sample.sections.reduce(0) { $0 + $1.rows.count })")
        if let value = sample.value { assert(value.isFinite && value >= 0) }
    }
    for module in [MonitoringModule.cpu, .memory, .disk] {
        _ = reader.read(modules: [module], detail: module)
        Thread.sleep(forTimeInterval: 1)
        let value = reader.read(modules: [module], detail: module)[module]!
        print("\(module.rawValue) detail: processes=\(value.processes.count), status=\(value.processStatus ?? "ok")")
        if module == .cpu || module == .memory { assert(!value.processes.isEmpty) }
    }
    assert(reader.read(modules: [], detail: nil).isEmpty)
    print("Live legacy CPU, memory, GPU and disk sampling passed (native sensors are covered by --ui).")
}
extension Optional { var isNil: Bool { self == nil } }
'''
with tempfile.TemporaryDirectory(prefix='eave-monitoring-tests-') as directory:
    directory = Path(directory)
    (directory / 'main.swift').write_text(main)
    subprocess.run(['swiftc', '-o', str(directory / 'checks'), str(directory / 'main.swift'),
                    *[str(root / 'DynamicIsland' / source) for source in sources]], check=True)
    subprocess.run([str(directory / 'checks'), *sys.argv[1:]], check=True)

ui_main = r'''
import AppKit
import SwiftUI
import Defaults
@testable import EaveNetworkStats

setbuf(stdout, nil)
let suiteName = "eave.monitoring.check.\(UUID().uuidString)"
let monitoringTestDefaults = UserDefaults(suiteName: suiteName)!
extension Defaults.Keys {
    static let enableStatsFeature = Key<Bool>("enabled", default: true, suite: monitoringTestDefaults)
    static let statsStopWhenNotchCloses = Key<Bool>("stop", default: true, suite: monitoringTestDefaults)
    static let statsModuleOrder = Key<[String]>("order", default: MonitoringModule.allCases.map(\.rawValue), suite: monitoringTestDefaults)
    static let statsUpdateInterval = Key<Double>("interval", default: 1, suite: monitoringTestDefaults)
    static let showCpuGraph = Key<Bool>("cpu", default: true, suite: monitoringTestDefaults)
    static let showMemoryGraph = Key<Bool>("ram", default: true, suite: monitoringTestDefaults)
    static let showGpuGraph = Key<Bool>("gpu", default: true, suite: monitoringTestDefaults)
    static let showDiskGraph = Key<Bool>("disk", default: true, suite: monitoringTestDefaults)
    static let showNetworkGraph = Key<Bool>("network", default: true, suite: monitoringTestDefaults)
    static let showCPUWidgetWhenClosed = Key<Bool>("closedCPU", default: false, suite: monitoringTestDefaults)
    static let showGPUWidgetWhenClosed = Key<Bool>("closedGPU", default: false, suite: monitoringTestDefaults)
    static let showMemoryWidgetWhenClosed = Key<Bool>("closedMemory", default: false, suite: monitoringTestDefaults)
    static let showDiskWidgetWhenClosed = Key<Bool>("closedDisk", default: false, suite: monitoringTestDefaults)
    static let showNetworkWidgetWhenClosed = Key<Bool>("closedNetwork", default: false, suite: monitoringTestDefaults)
    static let showSensorsWidgetWhenClosed = Key<Bool>("closedSensors", default: false, suite: monitoringTestDefaults)
    static let showSensorsGraph = Key<Bool>("sensors", default: true, suite: monitoringTestDefaults)
    static let cpuTemperatureUnit = Key<LockScreenWeatherTemperatureUnit>("temp", default: .celsius, suite: monitoringTestDefaults)
}
enum LockScreenWeatherTemperatureUnit: String, Defaults.Serializable { case celsius, fahrenheit }
final class DynamicIslandViewModel: ObservableObject {
    enum State { case open, closed }
    @Published var notchState = State.open
    @Published var isStatsPopoverActive = false
}

Task { @MainActor in
    EaveNetworkStats.Store.shared = Store(defaults: monitoringTestDefaults)
    let manager = StatsManager.shared
    let widgetKeys: [Defaults.Key<Bool>] = [.showCPUWidgetWhenClosed, .showMemoryWidgetWhenClosed,
        .showGPUWidgetWhenClosed, .showDiskWidgetWhenClosed, .showNetworkWidgetWhenClosed, .showSensorsWidgetWhenClosed]
    for key in widgetKeys { Defaults[key] = true }
    manager.updateMonitoringState(notchIsOpen: false, currentView: "other")
    try await Task.sleep(for: .seconds(3))
    @MainActor func running(_ module: MonitoringModule) -> Bool {
        switch module {
        case .cpu: return manager.cpu.isEnabled
        case .memory: return manager.memory.isEnabled
        case .gpu: return manager.gpu.isEnabled
        case .disk: return manager.disk.isEnabled
        case .network: return manager.network.isEnabled
        case .sensors: return manager.sensors.isEnabled
        }
    }
    for module in MonitoringModule.allCases {
        assert(running(module))
        assert(ClosedMonitoringWidgets.entries.contains { $0.0 == module })
        Defaults[module.visibilityKey] = false
        try await Task.sleep(for: .milliseconds(100))
        assert(!running(module), "Disabled module must stop sampling: \(module)")
        assert(!manager.enabledModules.contains(module))
        assert(!ClosedMonitoringWidgets.entries.contains { $0.0 == module })
        assert(manager.samples[module] == nil && manager.history[module] == nil)
        assert(widgetKeys.allSatisfy { Defaults[$0] })
        Defaults[module.visibilityKey] = true
        try await Task.sleep(for: .milliseconds(100))
        assert(running(module))
        assert(ClosedMonitoringWidgets.entries.contains { $0.0 == module })
    }
    for module in MonitoringModule.allCases { Defaults[module.visibilityKey] = false }
    try await Task.sleep(for: .milliseconds(100))
    assert(ClosedMonitoringWidgets.entries.isEmpty)
    assert(MonitoringModule.allCases.allSatisfy { !running($0) })
    for key in widgetKeys { Defaults[key] = false }
    for module in MonitoringModule.allCases { Defaults[module.visibilityKey] = true }
    try await Task.sleep(for: .milliseconds(100))
    print("All six module switches gate collapsed widgets and sampling; re-enabling preserves widget preferences.")
    if CommandLine.arguments.contains("--modules-only") {
        Defaults[.enableStatsFeature] = false
        try await Task.sleep(for: .milliseconds(100))
        manager.network.usageReader.terminate()
        manager.network.connectivityReader.terminate()
        monitoringTestDefaults.removePersistentDomain(forName: suiteName)
        exit(0)
    }
    Defaults[.statsModuleOrder] = ["network", "cpu", "network", "removed"]
    try await Task.sleep(for: .milliseconds(100))
    assert(manager.enabledModules == [.network, .cpu, .memory, .gpu, .disk, .sensors])
    Defaults[.showCpuGraph] = false
    try await Task.sleep(for: .milliseconds(100))
    assert(manager.enabledModules == [.network, .memory, .gpu, .disk, .sensors])
    Defaults[.showCpuGraph] = true
    try await Task.sleep(for: .milliseconds(100))
    assert(manager.enabledModules == [.network, .cpu, .memory, .gpu, .disk, .sensors])
    manager.updateMonitoringState(notchIsOpen: true, currentView: "stats")
    try await Task.sleep(for: .seconds(3))
    assert(manager.isMonitoring && manager.samples.count == 6)
    let host = NSHostingView(rootView: NotchStatsView().environmentObject(DynamicIslandViewModel())
        .environment(\.colorScheme, .dark).frame(width: 600, height: 280).background(Color.black))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 280), styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    host.frame = NSRect(x: 0, y: 0, width: 600, height: 280)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .seconds(1))
    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
    @MainActor func saveProcessorView(_ view: NSView, name: String) throws {
        view.layoutSubtreeIfNeeded()

        if let window = view.window, window.isVisible {
            let url = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent(name + ".png")
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
            try capture.run()
            capture.waitUntilExit()
            if capture.terminationStatus == 0 { return }
        }
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let url = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent(name + ".png")
            try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        }
    }
    for monitor in [manager.cpu, manager.gpu] {
        let name = monitor.module.stringValue.lowercased()
        assert(monitor.isEnabled && monitor.utilization != nil)
        let processorHost = NSHostingView(rootView: ProcessorMonitoringDetailView(monitor: monitor)
            .environment(\.colorScheme, .dark).background(Color(nsColor: .windowBackgroundColor)))
        let processorWindow = NSWindow(contentRect: NSRect(origin: .zero, size: monitor.panelSize), styleMask: .borderless, backing: .buffered, defer: false)
        processorWindow.appearance = NSAppearance(named: .darkAqua)
        processorWindow.contentView = processorHost
        processorWindow.orderFront(nil)
        try await Task.sleep(for: .seconds(3))
        if monitor.module == .CPU {
            assert(monitor.loadReader.value?.usagePerCore.isEmpty == false)
            assert(monitor.processReader.active && monitor.processReader.value?.isEmpty == false)
        } else {
            assert(monitor.infoReader.value?.active().isEmpty == false)
            print("Stats GPU: \(monitor.infoReader.value!.active()[0].model)")
        }
        try saveProcessorView(processorHost, name: name)
        monitor.showSettings()
        try await Task.sleep(for: .milliseconds(300))
        let nativeWindow = NSApp.windows.first { $0.isVisible && $0.contentView?.subviews.contains { $0 is NSTabView } == true }!
        let nativeTabs = nativeWindow.contentView!.subviews.first { $0 is NSTabView } as! NSTabView
        assert(nativeTabs.numberOfTabViewItems == 5)
        for item in monitor.widgets.items where !item.isActive {
            let button = descendants(nativeWindow.contentView!).first { $0.identifier?.rawValue == item.type.rawValue }!
            assert(button.accessibilityPerformPress())
        }
        try await Task.sleep(for: .milliseconds(200))
        assert(monitor.widgets.active.count == 7 && monitor.widgets.size.width > 100)
        for index in 0..<5 {
            nativeTabs.selectTabViewItem(at: index)
            nativeWindow.contentView!.layoutSubtreeIfNeeded()
            assert(nativeTabs.frame.width >= 540 && nativeTabs.frame.height > 400)
            if index == 1 {
                let preview = descendants(nativeTabs).first { $0.identifier?.rawValue == monitor.module.stringValue + "WidgetsPreview" }!
                assert(preview.frame.width >= 500)
            }
            try await Task.sleep(for: .milliseconds(150))
            try saveProcessorView(nativeWindow.contentView!, name: name + "-settings-\(index)")
        }
        nativeWindow.close()
        processorWindow.orderOut(nil)
        processorWindow.contentView = nil
        monitor.setVisible(false)
        if monitor.module == .CPU { assert(!monitor.processReader.active) }
    }
    print("Original CPU/GPU live readers, native details, seven widgets and all five settings panes passed.")

    assert(manager.sensors.isEnabled && manager.sensors.hottestTemperature != nil)
    print("Stats hottest sensor: \(manager.sensors.hottestTemperature!)°C")
    let sensorHost = NSHostingView(rootView: SensorsMonitoringDetailView()
        .environment(\.colorScheme, .dark).background(Color(nsColor: .windowBackgroundColor)))
    let sensorWindow = NSWindow(contentRect: NSRect(origin: .zero, size: manager.sensors.panelSize), styleMask: .borderless, backing: .buffered, defer: false)
    sensorWindow.isReleasedWhenClosed = false
    sensorWindow.appearance = NSAppearance(named: .darkAqua)
    sensorWindow.contentView = sensorHost
    sensorWindow.orderFront(nil)
    try await Task.sleep(for: .milliseconds(500))
    try saveProcessorView(sensorHost, name: "sensors-details")
    manager.sensors.showSettings()
    try await Task.sleep(for: .milliseconds(500))
    let sensorSettingsWindow = NSApp.windows.first { $0.isVisible && $0.contentView?.subviews.contains { $0 is NSTabView } == true }!
    let sensorTabs = sensorSettingsWindow.contentView!.subviews.first { $0 is NSTabView } as! NSTabView
    assert(sensorTabs.numberOfTabViewItems == 4)
    for item in manager.sensors.widgets.items where !item.isActive {
        let button = descendants(sensorSettingsWindow.contentView!).first { $0.identifier?.rawValue == item.type.rawValue }!
        assert(button.accessibilityPerformPress())
    }
    // Pick real sensors through their original controls, including a long Stack.
    let switches = descendants(manager.sensors.settings).compactMap { $0 as? NSSwitch }.filter { $0.action == NSSelectorFromString("toggleSensor:") }
    assert(!switches.isEmpty)
    for control in switches.prefix(12) {
        control.state = .on
        assert(control.sendAction(control.action!, to: control.target))
    }
    try await Task.sleep(for: .milliseconds(300))
    assert(manager.sensors.widgets.active.count == 5 && manager.sensors.widgets.size.width > 0)
    for index in 0..<4 {
        sensorTabs.selectTabViewItem(at: index)
        sensorSettingsWindow.contentView!.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        try saveProcessorView(sensorSettingsWindow.contentView!, name: "sensors-settings-\(index)")
    }
    sensorSettingsWindow.close()
    sensorWindow.orderOut(nil)
    sensorWindow.contentView = nil
    manager.sensors.setVisible(false)
    // Real HID reads must also work when opted in, and stop cleanly when opted out.
    if let hid = descendants(manager.sensors.settings).compactMap({ $0 as? NSSwitch }).first(where: { $0.action == NSSelectorFromString("toggleHID:") }) {
        hid.state = .on
        assert(hid.sendAction(hid.action!, to: hid.target))
        try await Task.sleep(for: .seconds(1))
        assert(manager.sensors.hottestTemperature != nil)
        hid.state = .off
        assert(hid.sendAction(hid.action!, to: hid.target))
        try await Task.sleep(for: .seconds(1))
    }
    print("Original sensor settings, real SMC/HID/IOReport data and five widgets passed.")

    manager.detail = .network
    let networkHeight = manager.network.panelSize.height
    let networkHost = NSHostingView(rootView: NetworkMonitoringDetailView().environment(\.colorScheme, .dark).background(Color(nsColor: .windowBackgroundColor)))
    let networkWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: networkHeight), styleMask: .borderless, backing: .buffered, defer: false)
    networkWindow.appearance = NSAppearance(named: .darkAqua)
    networkWindow.contentView = networkHost
    networkWindow.alphaValue = 0
    networkWindow.orderFront(nil)
    networkHost.frame = NSRect(x: 0, y: 0, width: 280, height: networkHeight)
    networkHost.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .seconds(5))
    assert(manager.network.isEnabled && manager.network.usageReader.value?.interface?.BSDName != nil)
    assert(manager.network.processReader.value?.isEmpty == false)
    let totals = manager.network.usageReader.value!.total
    print("Stats interface: \(manager.network.usageReader.value!.interface!.BSDName), totals: \(totals.download)/\(totals.upload)")
    if let bitmap = networkHost.bitmapImageRepForCachingDisplay(in: networkHost.bounds) {
        networkHost.cacheDisplay(in: networkHost.bounds, to: bitmap)
        let url = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent("network.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
    manager.network.showSettings()
    try await Task.sleep(for: .milliseconds(500))
    let settingsWindow = NSApp.windows.first { $0.isVisible && $0.contentView?.subviews.contains { $0 is NSTabView } == true }!
    settingsWindow.appearance = NSAppearance(named: .darkAqua)
    let tabs = settingsWindow.contentView!.subviews.first { $0 is NSTabView } as! NSTabView
    assert(tabs.numberOfTabViewItems == 5)
    @MainActor func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    for type in [widget_t.label, .networkChart, .state, .text, .icon] {
        let button = descendants(settingsWindow.contentView!).first { $0.identifier?.rawValue == type.rawValue }!
        assert(button.accessibilityPerformPress())
    }
    try await Task.sleep(for: .milliseconds(200))
    assert(manager.network.widgets.active.count == 6)
    assert(manager.network.widgets.size.width > 100)

    for (index, name) in ["settings", "widgets", "popup-settings", "notifications", "preview"].enumerated() {
        tabs.selectTabViewItem(at: index)
        settingsWindow.contentView!.layoutSubtreeIfNeeded()
        assert(tabs.frame.width >= 540 && tabs.frame.height > 400)
        if index == 1 {
            let preview = descendants(tabs).first { $0.identifier?.rawValue == "NetworkWidgetsPreview" }!
            assert(preview.frame.width >= 500)
        }
        try await Task.sleep(for: .milliseconds(150))
        let url = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent(name + ".png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(settingsWindow.windowNumber), url.path]
        try capture.run()
        capture.waitUntilExit()
        if capture.terminationStatus != 0 {
            // Offscreen fallback when the login session denies WindowServer screenshots.
            let view = settingsWindow.contentView!
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let context = NSGraphicsContext(bitmapImageRep: bitmap), let layer = view.layer {
                context.cgContext.clear(view.bounds)
                layer.render(in: context.cgContext)
            }
            try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        }
    }
    settingsWindow.close()
    networkWindow.orderOut(nil)
    networkWindow.contentView = nil
    manager.network.setVisible(false)
    manager.detail = .memory
    try await Task.sleep(for: .milliseconds(1200))
    manager.updateMonitoringState(notchIsOpen: false, currentView: "stats")
    assert(!manager.isMonitoring && !manager.memory.isEnabled && !manager.disk.isEnabled)
    manager.clearHistory()
    try await Task.sleep(for: .seconds(6))
    assert(manager.samples[.cpu] == nil && manager.history[.cpu] == nil)
    assert(manager.network.isEnabled && !manager.history[.network, default: []].isEmpty)
    manager.updateMonitoringState(notchIsOpen: true, currentView: "stats")
    for _ in 0..<50 {
        if manager.samples[.cpu]?.value != nil { break }
        try await Task.sleep(for: .milliseconds(300))
    }
    assert(manager.isMonitoring && manager.samples[.cpu]?.value != nil)
    manager.updateMonitoringState(notchIsOpen: true, currentView: "other")
    assert(!manager.isMonitoring)
    Defaults[.enableStatsFeature] = false
    manager.updateMonitoringState(notchIsOpen: true, currentView: "stats")
    assert(!manager.isMonitoring && !manager.network.isEnabled)
    manager.clearHistory()
    try await Task.sleep(for: .seconds(2))
    assert(manager.samples.isEmpty && manager.history.isEmpty)
    Defaults[.enableStatsFeature] = true
    try await Task.sleep(for: .milliseconds(300))
    assert(manager.isMonitoring)
    Defaults[.statsStopWhenNotchCloses] = false
    manager.updateMonitoringState(notchIsOpen: false, currentView: "stats")
    assert(manager.isMonitoring)
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    try await Task.sleep(for: .milliseconds(100))
    assert(!manager.isMonitoring && !manager.network.isEnabled && !manager.memory.isEnabled && !manager.disk.isEnabled)
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    try await Task.sleep(for: .milliseconds(100))
    assert(manager.isMonitoring && manager.network.isEnabled)
    for module in MonitoringModule.allCases { Defaults[module.visibilityKey] = false }
    try await Task.sleep(for: .milliseconds(100))
    assert(!manager.isMonitoring && !manager.network.isEnabled)
    manager.updateMonitoringState(notchIsOpen: false, currentView: "other")
    for module in MonitoringModule.allCases where module != .network { Defaults[module.visibilityKey] = true }
    for key in [Defaults.Keys.showMemoryWidgetWhenClosed, .showDiskWidgetWhenClosed] {
        Defaults[key] = true
        try await Task.sleep(for: .milliseconds(300))
        assert(!manager.isMonitoring)
        assert(key == .showMemoryWidgetWhenClosed ? manager.memory.isEnabled : manager.disk.isEnabled)
        Defaults[key] = false
        try await Task.sleep(for: .milliseconds(300))
        assert(!manager.memory.isEnabled && !manager.disk.isEnabled)
    }

    Defaults[.showSensorsWidgetWhenClosed] = true
    try await Task.sleep(for: .milliseconds(500))
    assert(manager.sensors.isEnabled && !manager.isMonitoring)
    assert(ClosedMonitoringWidgets.entries.contains { $0.0 == .sensors })
    assert(ClosedMonitoringWidgets.minimumWidth <= 600)
    let sensorVM = DynamicIslandViewModel()
    sensorVM.notchState = .closed
    let sensorRowWindows = (0..<2).map { _ -> NSWindow in
        let row = NSHostingView(rootView: ClosedMonitoringWidgets().environmentObject(sensorVM)
            .frame(width: ClosedMonitoringWidgets.minimumWidth).background(Color.black))
        let window = NSWindow(contentRect: NSRect(x: 400, y: 400, width: ClosedMonitoringWidgets.minimumWidth, height: 22), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = row
        window.orderFront(nil)
        return window
    }
    try await Task.sleep(for: .milliseconds(300))
    for (index, window) in sensorRowWindows.enumerated() {
        assert(abs(window.contentView!.fittingSize.height - 22) < 1)
        try saveProcessorView(window.contentView!, name: "closed-sensors-\(index)")
    }
    let sensorRowWindow = sensorRowWindows[0]
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: sensorRowWindow.frame.width / 2, y: 11), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sensorRowWindow.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        sensorRowWindow.sendEvent(event)
    }
    try await Task.sleep(for: .milliseconds(500))
    assert(sensorVM.isStatsPopoverActive)
    for window in sensorRowWindows { window.orderOut(nil); window.contentView = nil }
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    try await Task.sleep(for: .milliseconds(200))
    assert(!manager.sensors.isEnabled && manager.sensors.hottestTemperature == nil)
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    try await Task.sleep(for: .seconds(1))
    assert(manager.sensors.isEnabled && manager.sensors.hottestTemperature != nil)
    Defaults[.showSensorsWidgetWhenClosed] = false
    try await Task.sleep(for: .milliseconds(300))
    assert(!manager.sensors.isEnabled)
    manager.sensors.showSettings()
    try await Task.sleep(for: .milliseconds(300))
    assert(manager.sensors.isEnabled && manager.sensors.settingsVisible)
    NSApp.windows.first { $0.isVisible && $0.contentView?.subviews.contains { $0 is NSTabView } == true }!.close()
    try await Task.sleep(for: .milliseconds(300))
    assert(!manager.sensors.isEnabled)
    print("Closed sensor rows, click details, width cap, settings-only sampling and simulated sleep/wake passed.")

    // Enabled modules can sample while the overview is closed.
    Defaults[.showNetworkGraph] = true
    Defaults[.showNetworkWidgetWhenClosed] = true
    try await Task.sleep(for: .milliseconds(300))
    assert(manager.network.isEnabled && !manager.isMonitoring)
    let widgetVM = DynamicIslandViewModel()
    widgetVM.notchState = .closed
    let widgetHost = NSHostingView(rootView: ClosedMonitoringWidgets().environmentObject(widgetVM)
        .frame(width: ClosedMonitoringWidgets.minimumWidth).background(Color.black))
    let widgetWindow = NSWindow(contentRect: NSRect(x: 500, y: 500, width: ClosedMonitoringWidgets.minimumWidth,
        height: ClosedMonitoringWidgets.height), styleMask: .borderless, backing: .buffered, defer: false)
    widgetWindow.contentView = widgetHost
    widgetWindow.makeKeyAndOrderFront(nil)
    widgetHost.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(500))
    assert(abs(widgetHost.fittingSize.height - ClosedMonitoringWidgets.height) < 1)
    if let bitmap = widgetHost.bitmapImageRepForCachingDisplay(in: widgetHost.bounds) {
        widgetHost.cacheDisplay(in: widgetHost.bounds, to: bitmap)
        let url = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent("closed-network.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 95, y: 11), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: widgetWindow.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        widgetWindow.sendEvent(event)
    }
    try await Task.sleep(for: .milliseconds(600))
    assert(widgetVM.isStatsPopoverActive && widgetVM.notchState == .closed)
    assert(manager.network.panel.window?.isVisible == true && manager.network.processReader.active)
    widgetWindow.orderOut(nil)
    widgetWindow.contentView = nil
    try await Task.sleep(for: .milliseconds(300))
    assert(!widgetVM.isStatsPopoverActive)
    Defaults[.showNetworkWidgetWhenClosed] = false
    Defaults[.showNetworkGraph] = false
    try await Task.sleep(for: .milliseconds(300))
    assert(!manager.network.isEnabled)
    print("Closed network widget: independent sampling, fixed height, click-to-open and dismissal passed.")
    for (monitor, key) in [(manager.cpu, Defaults.Keys.showCPUWidgetWhenClosed), (manager.gpu, Defaults.Keys.showGPUWidgetWhenClosed)] {
        Defaults[key] = true
        try await Task.sleep(for: .milliseconds(300))
        assert(monitor.isEnabled && !manager.isMonitoring)
        assert(!manager.network.isEnabled)
        let vm = DynamicIslandViewModel()
        vm.notchState = .closed
        let width = ClosedMonitoringWidgets.minimumWidth
        let row = NSHostingView(rootView: ClosedMonitoringWidgets().environmentObject(vm).frame(width: width).background(Color.black))
        let rowWindow = NSWindow(contentRect: NSRect(x: 500, y: 500, width: width, height: 22), styleMask: .borderless, backing: .buffered, defer: false)
        rowWindow.contentView = row
        rowWindow.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(300))
        assert(abs(row.fittingSize.height - 22) < 1)
        try saveProcessorView(row, name: "closed-" + monitor.module.stringValue.lowercased())
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: width / 2, y: 11), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: rowWindow.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            rowWindow.sendEvent(event)
        }
        try await Task.sleep(for: .milliseconds(600))
        assert(vm.isStatsPopoverActive && vm.notchState == .closed && monitor.panel.window?.isVisible == true)
        rowWindow.orderOut(nil)
        rowWindow.contentView = nil
        try await Task.sleep(for: .milliseconds(300))
        assert(!vm.isStatsPopoverActive)
        Defaults[key] = false
        try await Task.sleep(for: .milliseconds(300))
        assert(!monitor.isEnabled)
        monitor.showSettings()
        try await Task.sleep(for: .milliseconds(300))
        assert(monitor.isEnabled && monitor.settingsVisible)
        NSApp.windows.first { $0.isVisible && $0.contentView?.subviews.contains { $0 is NSTabView } == true }!.close()
        try await Task.sleep(for: .milliseconds(300))
        assert(!monitor.isEnabled && !monitor.settingsVisible)
    }
    Defaults[.showNetworkGraph] = true
    Defaults[.showCPUWidgetWhenClosed] = true
    Defaults[.showGPUWidgetWhenClosed] = true
    Defaults[.showNetworkWidgetWhenClosed] = true
    try await Task.sleep(for: .milliseconds(300))
    assert(ClosedMonitoringWidgets.entries.map { $0.0 } == [.network, .cpu, .gpu])
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    try await Task.sleep(for: .milliseconds(100))
    assert(!manager.cpu.isEnabled && !manager.gpu.isEnabled && !manager.network.isEnabled)
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    try await Task.sleep(for: .milliseconds(100))
    assert(manager.cpu.isEnabled && manager.gpu.isEnabled && manager.network.isEnabled)
    Defaults[.enableStatsFeature] = false
    try await Task.sleep(for: .milliseconds(100))
    assert(!manager.cpu.isEnabled && !manager.gpu.isEnabled && !manager.network.isEnabled)
    print("Closed CPU/GPU widgets: independent sampling, 22pt row, click details, settings-only sampling and sleep/wake passed.")
    manager.network.usageReader.terminate()
    manager.network.connectivityReader.terminate()
    monitoringTestDefaults.removePersistentDomain(forName: suiteName)
    print("Manager stop, in-flight discard, restart, feature toggle, sleep/wake, module toggles and overview render passed.")
    exit(0)
}
NSApplication.shared.run()
'''

if '--ui' in sys.argv:
    import os
    products = Path(os.environ.get('EAVE_MONITORING_PRODUCTS', root / '.build/stats-monitoring/Build/Products/Debug'))
    module_maps = products.parents[1] / 'Intermediates.noindex/GeneratedModuleMaps'
    c_flags = [flag for path in module_maps.glob('CStats*.modulemap') for flag in ['-Xcc', '-fmodule-map-file=' + str(path)]]
    with tempfile.TemporaryDirectory(prefix='eave-monitoring-ui-') as directory:
        directory = Path(directory)
        (directory / 'main.swift').write_text(ui_main)
        import plistlib
        import shutil
        executable = directory / 'Checks.app/Contents/MacOS/checks'
        executable.parent.mkdir(parents=True)
        (executable.parent.parent / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'app.eave.monitoring-checks', 'CFBundleExecutable': 'checks',
            'CFBundlePackageType': 'APPL', 'NSLocationUsageDescription': 'Network integration checks',
        }))
        subprocess.run(['swiftc', '-profile-generate', '-swift-version', '5', '-I', str(products),
                        *c_flags, '-o', str(executable), str(directory / 'main.swift'),
                        *[str(root / 'DynamicIsland' / source) for source in sources],
                        str(root / 'DynamicIsland/managers/StatsManager.swift'),
                        str(root / 'DynamicIsland/components/Notch/NotchStatsView.swift'),
                        str(root / 'DynamicIsland/components/Notch/NetworkMonitoringDetailView.swift'),
                        str(root / 'DynamicIsland/components/Notch/ClosedMonitoringWidgets.swift'),
                        str(products / 'Defaults.o'), str(products / 'EaveNetworkStats.o'), str(products / 'CStatsDisk.o'), str(products / 'CStatsSensors.o')], check=True)
        resources = executable.parent.parent / 'Resources'
        resources.mkdir()
        shutil.copytree(products / 'EaveNetworkStats_EaveNetworkStats.bundle', resources / 'EaveNetworkStats_EaveNetworkStats.bundle')
        import os
        subprocess.run([str(executable), str(directory / 'overview.png'), *sys.argv[1:]], check=True,
                       env={**os.environ, 'LLVM_PROFILE_FILE': str(directory / 'checks.profraw')}, timeout=180)

        if destination := os.environ.get('EAVE_MONITORING_SNAPSHOT_DIR'):
            import shutil
            Path(destination).mkdir(parents=True, exist_ok=True)
            for name in [p.name for p in directory.glob('*.png')]:
                shutil.copy2(directory / name, Path(destination) / name)
