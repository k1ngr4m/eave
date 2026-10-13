//
//  SystemKit.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 13/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import IOKit

public enum Platform: String, Codable {
    case intel

    case m1
    case m1Pro
    case m1Max
    case m1Ultra

    case m2
    case m2Pro
    case m2Max
    case m2Ultra

    case m3
    case m3Pro
    case m3Max
    case m3Ultra

    case m4
    case m4Pro
    case m4Max

    case m5
    case m5Pro
    case m5Max
    case m5Ultra

    case m6
    case m6Pro
    case m6Max

    case a18Pro

    public static var apple: [Platform] {
        return [
            .m1, .m1Pro, .m1Max, .m1Ultra,
            .m2, .m2Pro, .m2Max, .m2Ultra,
            .m3, .m3Pro, .m3Max, .m3Ultra,
            .m4, .m4Pro, .m4Max,
            .m5, .m5Pro, .m5Max, .m5Ultra,
            .m6, .m6Pro, .m6Max,
            .a18Pro
        ]
    }

    public var generation: Int {
        switch self {
        case .intel, .a18Pro: return 0
        case .m1, .m1Pro, .m1Max, .m1Ultra: return 1
        case .m2, .m2Pro, .m2Max, .m2Ultra: return 2
        case .m3, .m3Pro, .m3Max, .m3Ultra: return 3
        case .m4, .m4Pro, .m4Max: return 4
        case .m5, .m5Pro, .m5Max, .m5Ultra: return 5
        case .m6, .m6Pro, .m6Max: return 6
        }
    }

    public func isNewerThan(_ other: Platform) -> Bool {
        return self.generation > other.generation
    }

    public func isNewerThanOrEqual(_ other: Platform) -> Bool {
        return self.generation >= other.generation
    }

    public static var m1Gen: [Platform] {
        return [.m1, .m1Pro, .m1Max, .m1Ultra]
    }
    public static var m2Gen: [Platform] {
        return [.m2, .m2Pro, .m2Max, .m2Ultra]
    }
    public static var m3Gen: [Platform] {
        return [.m3, .m3Pro, .m3Max, .m3Ultra]
    }
    public static var m4Gen: [Platform] {
        return [.m4, .m4Pro, .m4Max]
    }
    public static var m5Gen: [Platform] {
        return [.m5, .m5Pro, .m5Max, .m5Ultra]
    }
    public static var m6Gen: [Platform] {
        return [.m6, .m6Pro, .m6Max]
    }

    public static var all: [Platform] {
        return apple + [.intel]
    }
}

public enum coreType: Int, Codable {
    case unknown = -1
    case efficiency = 1
    case performance = 2
    case `super` = 3
}

public struct core_s: Codable {
    public var id: Int32
    public var type: coreType
}

public struct cpu_s: Codable {
    public var name: String? = nil
    public var physicalCores: Int8? = nil
    public var logicalCores: Int8? = nil
    public var eCores: Int32? = nil
    public var pCores: Int32? = nil
    public var sCores: Int32? = nil
    public var cores: [core_s]? = nil
    public var eCoreFrequencies: [Int32]? = nil
    public var pCoreFrequencies: [Int32]? = nil
    public var sCoreFrequencies: [Int32]? = nil
}

public struct gpu_s: Codable {
    public var id: String? = nil
    public var name: String? = nil
    public var vendor: String? = nil
    public var vram: String? = nil
    public var cores: Int? = nil
    public var frequencies: [Int32]? = nil
}


struct ProcessorDeviceInfo { var cpu: cpu_s?; var gpu: [gpu_s]? }
struct ProcessorDevice { var info = ProcessorDeviceInfo(); var platform: Platform?; var bootDate: Date? }
final class SystemKit {
    static let shared = SystemKit()
    var device = ProcessorDevice()
    init() {
        device.bootDate = bootDate()
        (device.info.cpu, device.platform) = getCPUInfo()
        device.info.gpu = getGPUInfo()
    }
    func bootDate() -> Date? {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var bootTimeSize = MemoryLayout<timeval>.size

        let result = sysctl(&mib, UInt32(mib.count), &bootTime, &bootTimeSize, nil, 0)
        if result == KERN_SUCCESS {
            return Date(timeIntervalSince1970: Double(bootTime.tv_sec) + Double(bootTime.tv_usec) / 1_000_000.0)
        }

        error("error get boot time: \(String(cString: mach_error_string(result), encoding: String.Encoding.ascii) ?? "unknown error")")
        return nil
    }

    private func getCPUInfo() -> (cpu_s?, Platform?) {
        var cpu = cpu_s()

        var sizeOfName = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &sizeOfName, nil, 0)
        var nameChars = [CChar](repeating: 0, count: sizeOfName)
        sysctlbyname("machdep.cpu.brand_string", &nameChars, &sizeOfName, nil, 0)
        var name = String(cString: nameChars)
        if name != "" {
            name = name.replacingOccurrences(of: "(TM)", with: "")
            name = name.replacingOccurrences(of: "(R)", with: "")
            name = name.replacingOccurrences(of: "CPU", with: "")
            name = name.replacingOccurrences(of: "@", with: "")

            cpu.name = name.condenseWhitespace()
        }

        let platform = self.getPlatform(cpuName: cpu.name)

        var size = UInt32(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let hostInfo = host_basic_info_t.allocate(capacity: 1)
        defer {
            hostInfo.deallocate()
        }

        let result = hostInfo.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
            host_info(machHostPort, HOST_BASIC_INFO, $0, &size)
        }

        if result != KERN_SUCCESS {
            error("read cores number: \(String(cString: mach_error_string(result), encoding: String.Encoding.ascii) ?? "unknown error")")
            return (cpu, platform)
        }

        let data = hostInfo.move()
        cpu.physicalCores = Int8(data.physical_cpu)
        cpu.logicalCores = Int8(data.logical_cpu)

        if let cores = self.getCPUCores(for: platform) {
            cpu.eCores = cores.0
            cpu.pCores = cores.1
            cpu.sCores = cores.2
            cpu.cores = cores.3
        }
        if let freq = self.getFrequencies(for: platform) {
            cpu.eCoreFrequencies = freq.0
            cpu.pCoreFrequencies = freq.1
            cpu.sCoreFrequencies = freq.2
        }

        return (cpu, platform)
    }

    func getCPUCores(for platform: Platform?) -> (Int32?, Int32?, Int32?, [core_s])? {
        var iterator: io_iterator_t = io_iterator_t()
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMPE"), &iterator)
        if result != kIOReturnSuccess {
            print("Error find AppleARMPE: " + (String(cString: mach_error_string(result), encoding: String.Encoding.ascii) ?? "unknown error"))
            return nil
        }

        var service: io_registry_entry_t = 1
        var list: [core_s] = []
        var pCores: Int32? = nil
        var eCores: Int32? = nil
        var sCores: Int32? = nil
        let isM5GenOrNewer = platform?.isNewerThanOrEqual(.m5) ?? false

        while service != 0 {
            service = IOIteratorNext(iterator)
            guard service != 0 else { break }

            var entry: io_iterator_t = io_iterator_t()
            if IORegistryEntryGetChildIterator(service, kIOServicePlane, &entry) != kIOReturnSuccess {
                IOObjectRelease(service)
                continue
            }
            var child: io_registry_entry_t = 1
            while child != 0 {
                child = IOIteratorNext(entry)
                guard child != 0 else {
                    continue
                }

                guard let name = getIOName(child),
                      let props = getIOProperties(child) else { continue }

                if name.matches("^cpu\\d") {
                    var type: coreType = .unknown
                    if let rawType = props.object(forKey: "cluster-type") as? Data,
                       let typ = String(data: rawType, encoding: .utf8)?.trimmed {
                        if isM5GenOrNewer {
                            switch typ {
                            case "E":
                                type = .efficiency
                            case "M":
                                type = .performance
                            case "P":
                                type = .super
                            default:
                                type = .unknown
                            }
                        } else {
                            switch typ {
                            case "E":
                                type = .efficiency
                            case "P":
                                type = .performance
                            default:
                                type = .unknown
                            }
                        }
                    }

                    list.append(core_s(id: Int32(name.trimmed.dropFirst(3)) ?? -1, type: type))
                } else if name.trimmed == "cpus" {
                    if isM5GenOrNewer {
                        eCores = (props.object(forKey: "e-core-count") as? Data)?.withUnsafeBytes { pointer in
                            return pointer.load(as: Int32.self)
                        }
                        pCores = (props.object(forKey: "m-core-count") as? Data)?.withUnsafeBytes { pointer in
                            return pointer.load(as: Int32.self)
                        }
                        sCores = (props.object(forKey: "p-core-count") as? Data)?.withUnsafeBytes { pointer in
                            return pointer.load(as: Int32.self)
                        }
                    } else {
                        eCores = (props.object(forKey: "e-core-count") as? Data)?.withUnsafeBytes { pointer in
                            return pointer.load(as: Int32.self)
                        }
                        pCores = (props.object(forKey: "p-core-count") as? Data)?.withUnsafeBytes { pointer in
                            return pointer.load(as: Int32.self)
                        }
                    }
                }

                IOObjectRelease(child)
            }
            IOObjectRelease(entry)
            IOObjectRelease(service)
        }
        IOObjectRelease(iterator)

        if platform?.isNewerThanOrEqual(.m6) == true && !list.isEmpty && !list.contains(where: { $0.type == .unknown }) {
            eCores = Int32(list.filter{ $0.type == .efficiency }.count)
            pCores = Int32(list.filter{ $0.type == .performance }.count)
            sCores = Int32(list.filter{ $0.type == .super }.count)
        }

        list.sort { $0.id < $1.id }
        for i in list.indices {
            list[i].id = Int32(i)
        }

        return (eCores, pCores, sCores, list)
    }

    private func getGPUInfo() -> [gpu_s]? {
        guard let res = process(path: "/usr/sbin/system_profiler", arguments: ["SPDisplaysDataType", "-json"]) else {
            return nil
        }

        var list: [gpu_s] = []
        var i = 0
        do {
            if let json = try JSONSerialization.jsonObject(with: Data(res.utf8), options: []) as? [String: Any] {
                if let arr = json["SPDisplaysDataType"] as? [[String: Any]] {
                    for obj in arr {
                        var gpu: gpu_s = gpu_s()
                        gpu.id = "\(i)"

                        gpu.name = obj["sppci_model"] as? String
                        gpu.vendor = obj["spdisplays_vendor"] as? String
                        gpu.cores = Int(obj["sppci_cores"] as? String ?? "")

                        if let vram = obj["spdisplays_vram_shared"] as? String {
                            gpu.vram = vram
                        } else if let vram = obj["spdisplays_vram"] as? String {
                            gpu.vram = vram
                        }

                        list.append(gpu)
                        i += 1
                    }
                }
            }
        } catch let err as NSError {
            error("error to parse system_profiler SPDisplaysDataType: \(err.localizedDescription)")
            return nil
        }

        return list
    }

    private func getFrequencies(for platform: Platform?) -> ([Int32], [Int32], [Int32])? {
        var eFreq: [Int32] = []
        var pFreq: [Int32] = []
        var sFreq: [Int32] = []

        let isCpuStartFromM4 = platform?.isNewerThanOrEqual(.m4) ?? false
        let isM5GenOrNewer = platform?.isNewerThanOrEqual(.m5) ?? false
        let isM6GenOrNewer = platform?.isNewerThanOrEqual(.m6) ?? false
        let names = isM6GenOrNewer ? ["pmgr", "pmgr-child"] : ["pmgr"]

        for name in names {
            var iterator = io_iterator_t()
            let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceNameMatching(name), &iterator)
            if result != kIOReturnSuccess {
                print("Error find \(name): " + (String(cString: mach_error_string(result), encoding: String.Encoding.ascii) ?? "unknown error"))
                continue
            }
            defer { IOObjectRelease(iterator) }

            while case let child = IOIteratorNext(iterator), child != 0 {
                defer { IOObjectRelease(child) }
                guard let props = getIOProperties(child) else { continue }

                if let data = props.value(forKey: "voltage-states1-sram") as? Data {
                    eFreq = convertCFDataToArr(data as CFData, isCpuStartFromM4)
                }
                if isM5GenOrNewer {
                    if let data = props.value(forKey: "voltage-states22-sram") as? Data {
                        pFreq = convertCFDataToArr(data as CFData, isCpuStartFromM4)
                    }
                    if let data = props.value(forKey: "voltage-states5-sram") as? Data {
                        sFreq = convertCFDataToArr(data as CFData, isCpuStartFromM4)
                    }
                } else {
                    if let data = props.value(forKey: "voltage-states5-sram") as? Data {
                        pFreq = convertCFDataToArr(data as CFData, isCpuStartFromM4)
                    }
                }
            }
        }

        // Use the shared cluster table when M6 has no separate performance table.
        if isM6GenOrNewer && pFreq.isEmpty {
            pFreq = sFreq
        }

        return (eFreq, pFreq, sFreq)
    }

    private func getPlatform(cpuName: String?) -> Platform? {
        if let name = cpuName?.lowercased() {
            if name.contains("intel") {
                return .intel
            } else if name.contains("m1") {
                if name.contains("pro") {
                    return .m1Pro
                } else if name.contains("max") {
                    return .m1Max
                } else if name.contains("ultra") {
                    return .m1Ultra
                } else {
                    return .m1
                }
            } else if name.contains("m2") {
                if name.contains("pro") {
                    return .m2Pro
                } else if name.contains("max") {
                    return .m2Max
                } else if name.contains("ultra") {
                    return .m2Ultra
                } else {
                    return .m2
                }
            } else if name.contains("m3") {
                if name.contains("pro") {
                    return .m3Pro
                } else if name.contains("max") {
                    return .m3Max
                } else if name.contains("ultra") {
                    return .m3Ultra
                } else {
                    return .m3
                }
            } else if name.contains("m4") {
                if name.contains("pro") {
                    return .m4Pro
                } else if name.contains("max") {
                    return .m4Max
                } else {
                    return .m4
                }
            } else if name.contains("m5") {
                if name.contains("pro") {
                    return .m5Pro
                } else if name.contains("max") {
                    return .m5Max
                } else if name.contains("ultra") {
                    return .m5Ultra
                } else {
                    return .m5
                }
            } else if name.contains("m6") {
                if name.contains("pro") {
                    return .m6Pro
                } else if name.contains("max") {
                    return .m6Max
                } else {
                    return .m6
                }
            } else if name.contains("a18 pro") {
                return .a18Pro
            }
        }
        return nil
    }

}
