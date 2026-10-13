// Adapted from exelban/stats Modules/{CPU,RAM,GPU,Disk,Net,Sensors} readers.
// Upstream: 0c0e551e199938a92af963c25a15a3ca1aef7764.
// Copyright (c) 2019 Serhiy Mytrovtsiy. MIT; see Resources/Stats-LICENSE.txt.
import Foundation
import IOKit
import IOKit.graphics
import Darwin

// Confined to StatsManager's serial utility queue. No UI, database or menu-bar dependency.
final class MonitoringReader: @unchecked Sendable {
    private let host = mach_host_self()
    private var cpuTicks: [UInt32] = []
    private var coreTicks: [[UInt32]] = []
    private var diskCounter = MonitoringCounter()
    private var diskProcessCounter = MonitoringCounter()
    private var lastDetail: MonitoringModule?
    private var lastModules: Set<MonitoringModule> = []
    private lazy var cpuSensors = CPUSensorCollector()
    private lazy var smc = SMC()

    deinit { mach_port_deallocate(mach_task_self_, host) }

    func reset() {
        cpuTicks = []; coreTicks = []
        diskCounter = MonitoringCounter()
        diskProcessCounter = MonitoringCounter()
        lastDetail = nil; lastModules = []
    }

    func read(modules: Set<MonitoringModule>, detail: MonitoringModule?) -> [MonitoringModule: MonitoringSample] {
        if modules.contains(.cpu), !lastModules.contains(.cpu) {
            cpuTicks = []; coreTicks = []; cpuSensors.resetFrequencySampling()
        }
        if !lastModules.contains(.disk) { diskCounter = MonitoringCounter() }
        if detail != lastDetail {
            diskProcessCounter = MonitoringCounter()
        }
        lastDetail = detail; lastModules = modules
        var result: [MonitoringModule: MonitoringSample] = [:]
        for module in MonitoringModule.allCases where modules.contains(module) {
            switch module {
            case .cpu: result[module] = readCPU(detail: detail == module)
            case .memory: result[module] = readMemory(detail: detail == module)
            case .gpu: result[module] = readGPU()
            case .disk: result[module] = readDisk(detail: detail == module)
            case .network: break // Stats' original network readers run independently.
            case .sensors: break // SensorsMonitor owns sensor sampling.
            }
        }
        return result
    }

    private func readCPU(detail: Bool) -> MonitoringSample {
        var result = MonitoringSample()
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        if status == KERN_SUCCESS {
            let current = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
            if let load = MonitoringParsing.cpuTicks(current, previous: cpuTicks) {
                result.value = load.user + load.system
                result.sections.append(.init(String(localized: "Usage"), rows: [
                    .init(String(localized: "User"), load.user, .percent), .init(String(localized: "System"), load.system, .percent),
                    .init(String(localized: "Idle"), load.idle, .percent)
                ]))
            }
            cpuTicks = current
        }
        var pointer: processor_info_array_t?
        var cores: natural_t = 0
        var size: mach_msg_type_number_t = 0
        if host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cores, &pointer, &size) == KERN_SUCCESS, let pointer {
            defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: pointer), vm_size_t(size) * vm_size_t(MemoryLayout<integer_t>.stride)) }
            let ticks = (0..<Int(cores)).map { core in (0..<4).map { UInt32(bitPattern: pointer[core * 4 + $0]) } }
            if ticks.count == coreTicks.count {
                let rows = ticks.enumerated().map { index, tick -> MonitoringRow in
                    let load = MonitoringParsing.cpuTicks(tick, previous: coreTicks[index])
                    return .init(String(localized: "Core") + " \(index + 1)", load.map { $0.user + $0.system }, .percent)
                }
                result.sections.append(.init(String(localized: "Logical cores"), rows: rows))
            }
            coreTicks = ticks
        }
        let frequency = cpuSensors.readFrequency()
        var averages = [Double](repeating: 0, count: 3)
        let hasAverages = getloadavg(&averages, 3) == 3
        result.sections.insert(.init(String(localized: "Processor"), rows: [
            .init(String(localized: "Model"), text: AppleHardwareInfo.shared.cpuName ?? "—"),
            .init(String(localized: "Temperature"), cpuSensors.readTemperature().celsius, .temperature),
            .init(String(localized: "E-core frequency"), frequency?.eCoreGHz, .frequency),
            .init(String(localized: "P-core frequency"), frequency?.pCoreGHz, .frequency),
            .init(String(localized: "Load 1m / 5m / 15m"), text: hasAverages ? averages.map { String(format: "%.2f", $0) }.joined(separator: " / ") : "—"),
            .init(String(localized: "Uptime"), text: StatsFormatting.abbreviatedDuration(ProcessInfo.processInfo.systemUptime))
        ]), at: 0)
        if detail {
            if let output = command("/bin/ps", ["-Aceo", "pid,pcpu,comm", "-r"]) {
                result.processes = Array(output.split(separator: "\n").compactMap { line -> MonitoringRow? in
                    let parts = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
                    guard parts.count == 3, let pid = Int32(parts[0]), let usage = Double(parts[1]), usage.isFinite else { return nil }
                    return .init(URL(fileURLWithPath: String(parts[2])).lastPathComponent, usage, .percent, id: String(pid))
                }.sorted { ($0.value ?? 0) > ($1.value ?? 0) }.prefix(8))
            } else { result.processStatus = String(localized: "Process data unavailable") }
        }
        return result
    }

    private func readMemory(detail: Bool) -> MonitoringSample {
        var result = MonitoringSample()
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard status == KERN_SUCCESS else { return result }
        let page = Double(vm_kernel_page_size)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let wired = Double(info.wire_count) * page
        let compressed = Double(info.compressor_page_count) * page
        let cache = (Double(info.purgeable_count) + Double(info.external_page_count)) * page
        let used = max(0, min(total, (Double(info.active_count) + Double(info.inactive_count) + Double(info.speculative_count)) * page + wired + compressed - cache))
        result.value = used / total * 100
        var pressure: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let hasPressure = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, nil, 0) == 0
        var swap = xsw_usage()
        size = MemoryLayout<xsw_usage>.size
        let hasSwap = sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0
        result.sections = [.init(String(localized: "Memory"), rows: [
            .init(String(localized: "Memory pressure"), text: hasPressure ? (pressure == 4 ? String(localized: "Critical") : pressure == 2 ? String(localized: "Warning") : String(localized: "Normal")) : "—"),
            .init(String(localized: "Total"), total, .bytes), .init(String(localized: "Used"), used, .bytes),
            .init(String(localized: "Available"), total - used, .bytes),
            .init(String(localized: "App memory"), max(0, used - wired - compressed), .bytes),
            .init(String(localized: "Wired"), wired, .bytes), .init(String(localized: "Compressed"), compressed, .bytes),
            .init(String(localized: "Cached files"), cache, .bytes),
            .init(String(localized: "Swap used"), hasSwap ? Double(swap.xsu_used) : nil, .bytes)
        ])]
        if detail {
            if let output = command("/usr/bin/top", ["-l", "1", "-o", "mem", "-n", "8", "-stats", "pid,command,mem"]) {
                result.processes = output.split(separator: "\n").compactMap { MonitoringParsing.memoryProcess(String($0)) }
            } else { result.processStatus = String(localized: "Process data unavailable") }
        }
        return result
    }

    private func readGPU() -> MonitoringSample {
        var result = MonitoringSample()
        var values: [Double] = []
        for (id, dict) in services(kIOAcceleratorClassName) {
            guard let stats = dict["PerformanceStatistics"] as? [String: Any] else { continue }
            let ioClass = (dict["IOClass"] as? String ?? "GPU").lowercased()
            let vendor = ioClass.contains("agx") ? "Apple GPU" : ioClass.contains("amd") ? "AMD GPU" : ioClass.contains("intel") ? "Intel GPU" : "GPU"
            let model = stats["model"] as? String ?? dict["model"] as? String ?? vendor
            let active = ((dict["AGCInfo"] as? [String: Any])?["poweredOffByAGC"] as? NSNumber)?.intValue != 1
            let usage = (stats["Device Utilization %"] as? NSNumber ?? stats["GPU Activity(%)"] as? NSNumber).map { min(100, max(0, $0.doubleValue)) }
            if active, let usage { values.append(usage) }
            var rows: [MonitoringRow] = [
                .init(String(localized: "Status"), text: active ? String(localized: "Active") : String(localized: "Inactive")),
                .init(String(localized: "Usage"), usage, .percent)
            ]
            for (key, label, unit) in [("Renderer Utilization %", String(localized: "Renderer"), MonitoringUnit.percent),
                                        ("Tiler Utilization %", String(localized: "monitoring_gpu_tiler", defaultValue: "Tiler"), .percent),
                                        ("Temperature(C)", String(localized: "Temperature"), .temperature),
                                        ("Core Clock(MHz)", String(localized: "Frequency"), .frequency)] {
                if let number = stats[key] as? NSNumber {
                    rows.append(.init(label, number.doubleValue / (unit == .frequency ? 1000 : 1), unit))
                }
            }
            result.sections.append(.init(model, rows: rows, id: id))
        }
        result.value = values.max()
        return result
    }

    private func readDisk(detail: Bool) -> MonitoringSample {
        var result = MonitoringSample()
        var counters: [String: (UInt64, UInt64)] = [:]
        for (id, dict) in services("IOBlockStorageDriver") {
            guard let stats = dict["Statistics"] as? [String: Any],
                  let read = stats["Bytes (Read)"] as? NSNumber, let written = stats["Bytes (Write)"] as? NSNumber else { continue }
            counters[id] = (read.uint64Value, written.uint64Value)
        }
        let rates = diskCounter.rates(counters, at: ProcessInfo.processInfo.systemUptime)
        if !rates.isEmpty { result.value = rates.values.reduce(0) { $0 + $1.0 }; result.secondary = rates.values.reduce(0) { $0 + $1.1 } }
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsLocalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: .skipHiddenVolumes) ?? []
        for url in urls where url.path == "/" || url.path.hasPrefix("/Volumes/") {
            guard let values = try? url.resourceValues(forKeys: keys), values.volumeIsLocal != false,
                  let total = values.volumeTotalCapacity, total > 0 else { continue }
            let free = values.volumeAvailableCapacity
            result.sections.append(.init(values.volumeName ?? url.lastPathComponent, rows: [
                .init(String(localized: "Mount point"), text: url.path),
                .init(String(localized: "Total"), Double(total), .bytes),
                .init(String(localized: "Available"), free.map(Double.init), .bytes),
                .init(String(localized: "Used"), free.map { Double(max(0, total - $0)) }, .bytes)
            ], id: url.path))
        }
        if detail {
            guard let output = command("/bin/ps", ["-Aceo", "pid,comm"]) else {
                result.processStatus = String(localized: "Process data unavailable"); return result
            }
            var counters: [String: (UInt64, UInt64)] = [:]
            var names: [String: String] = [:]
            for line in output.split(separator: "\n") {
                let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard fields.count == 2, let pid = Int32(fields[0]) else { continue }
                var info = rusage_info_v2()
                let status = withUnsafeMutablePointer(to: &info) {
                    $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
                }
                guard status == 0 else { continue }
                let id = "\(pid):\(info.ri_proc_start_abstime)"
                counters[id] = (info.ri_diskio_bytesread, info.ri_diskio_byteswritten)
                names[id] = URL(fileURLWithPath: String(fields[1])).lastPathComponent
            }
            let rates = diskProcessCounter.rates(counters, at: ProcessInfo.processInfo.systemUptime)
            result.processes = processRows(rates, names: names)
        }
        return result
    }

    private func services(_ name: String) -> [(String, [String: Any])] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [(String, [String: Any])] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            var id: UInt64 = 0
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS,
                  IORegistryEntryCreateCFProperties(service, &properties, nil, 0) == KERN_SUCCESS,
                  let dict = properties?.takeRetainedValue() as? [String: Any] else { continue }
            result.append((String(id), dict))
        }
        return result
    }

    private func processRows(_ rates: [String: (Double, Double)], names: [String: String]) -> [MonitoringRow] {
        rates.sorted { $0.value.0 + $0.value.1 > $1.value.0 + $1.value.1 }.prefix(8).map { key, rate in
            var row = MonitoringRow(names[key] ?? key, rate.0, .rate, id: key)
            row.text = MonitoringUnit.rate.string(rate.0) + " / " + MonitoringUnit.rate.string(rate.1)
            return row
        }
    }

    private func command(_ path: String, _ arguments: [String]) -> String? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: path); task.arguments = arguments
        task.environment = ["LC_ALL": "C", "NSUnbufferedIO": "YES"]
        task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        defer { try? pipe.fileHandleForReading.close() }
        do { try task.run() } catch { return nil }
        let timeout = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit(); timeout.cancel()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
