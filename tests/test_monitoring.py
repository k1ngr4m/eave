"""Run: python3 tests/test_monitoring.py [--live] [--ui].
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
let net = MonitoringParsing.networkProcesses(",bytes_in,bytes_out,\ncom.test.app.42,123,456,\ninvalid,1,2,\napp.0,4,5,")
assert(net.count == 1 && net["42"]!.name == "com.test.app" && net["42"]!.sent == 456)
assert(MonitoringUnit.temperature.string(0, fahrenheit: true) == "32.0°F")
assert(MonitoringUnit.rate.string(nil) == "—")
assert(MonitoringUnit.percent.string(.nan) == "—")
assert(MonitoringModule.allCases.count == 6)
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
    let modules = Set(MonitoringModule.allCases)
    _ = reader.read(modules: modules, detail: nil)
    Thread.sleep(forTimeInterval: 1)
    let samples = reader.read(modules: modules, detail: nil)
    assert(samples.count == 6)
    assert(samples[.cpu]!.value != nil && (0...100).contains(samples[.cpu]!.value!))
    assert(samples[.memory]!.value != nil && (0...100).contains(samples[.memory]!.value!))
    for module in MonitoringModule.allCases {
        let sample = samples[module]!
        print("\(module.rawValue): \(module.unit.string(sample.value)), sections=\(sample.sections.count), rows=\(sample.sections.reduce(0) { $0 + $1.rows.count })")
        if let value = sample.value { assert(value.isFinite && value >= 0) }
    }
    for module in [MonitoringModule.cpu, .memory, .disk, .network] {
        _ = reader.read(modules: [module], detail: module)
        Thread.sleep(forTimeInterval: 1)
        let value = reader.read(modules: [module], detail: module)[module]!
        print("\(module.rawValue) detail: processes=\(value.processes.count), status=\(value.processStatus ?? "ok")")
        if module == .cpu || module == .memory { assert(!value.processes.isEmpty) }
    }
    assert(reader.read(modules: [], detail: nil).isEmpty)
    print("Live six-module sampling passed.")
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

setbuf(stdout, nil)
let suiteName = "eave.monitoring.check.\(UUID().uuidString)"
let monitoringTestDefaults = UserDefaults(suiteName: suiteName)!
extension Defaults.Keys {
    static let enableStatsFeature = Key<Bool>("enabled", default: true, suite: monitoringTestDefaults)
    static let statsStopWhenNotchCloses = Key<Bool>("stop", default: true, suite: monitoringTestDefaults)
    static let statsUpdateInterval = Key<Double>("interval", default: 1, suite: monitoringTestDefaults)
    static let showCpuGraph = Key<Bool>("cpu", default: true, suite: monitoringTestDefaults)
    static let showMemoryGraph = Key<Bool>("ram", default: true, suite: monitoringTestDefaults)
    static let showGpuGraph = Key<Bool>("gpu", default: true, suite: monitoringTestDefaults)
    static let showDiskGraph = Key<Bool>("disk", default: true, suite: monitoringTestDefaults)
    static let showNetworkGraph = Key<Bool>("network", default: true, suite: monitoringTestDefaults)
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
    let manager = StatsManager.shared
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
    manager.detail = .memory
    try await Task.sleep(for: .milliseconds(1200))
    manager.updateMonitoringState(notchIsOpen: false, currentView: "stats")
    assert(!manager.isMonitoring)
    manager.clearHistory()
    try await Task.sleep(for: .seconds(6))
    assert(manager.samples.isEmpty && manager.history.isEmpty && manager.lastUpdated == nil)
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
    assert(!manager.isMonitoring)
    Defaults[.enableStatsFeature] = true
    try await Task.sleep(for: .milliseconds(300))
    assert(manager.isMonitoring)
    Defaults[.statsStopWhenNotchCloses] = false
    manager.updateMonitoringState(notchIsOpen: false, currentView: "stats")
    assert(manager.isMonitoring)
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
    try await Task.sleep(for: .milliseconds(100))
    assert(!manager.isMonitoring)
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    try await Task.sleep(for: .milliseconds(100))
    assert(manager.isMonitoring)
    for module in MonitoringModule.allCases { Defaults[module.visibilityKey] = false }
    try await Task.sleep(for: .milliseconds(100))
    assert(!manager.isMonitoring)
    monitoringTestDefaults.removePersistentDomain(forName: suiteName)
    print("Manager stop, in-flight discard, restart, feature toggle, sleep/wake, module toggles and overview render passed.")
    exit(0)
}
NSApplication.shared.run()
'''

if '--ui' in sys.argv:
    products = root / '.build/stats-monitoring/Build/Products/Debug'
    with tempfile.TemporaryDirectory(prefix='eave-monitoring-ui-') as directory:
        directory = Path(directory)
        (directory / 'main.swift').write_text(ui_main)
        subprocess.run(['swiftc', '-profile-generate', '-swift-version', '5', '-I', str(products),
                        '-o', str(directory / 'checks'), str(directory / 'main.swift'),
                        *[str(root / 'DynamicIsland' / source) for source in sources],
                        str(root / 'DynamicIsland/managers/StatsManager.swift'),
                        str(root / 'DynamicIsland/components/Notch/NotchStatsView.swift'),
                        str(products / 'Defaults.o')], check=True)
        import os
        subprocess.run([str(directory / 'checks'), str(directory / 'overview.png')], check=True,
                       env={**os.environ, 'LLVM_PROFILE_FILE': str(directory / 'checks.profraw')}, timeout=90)
