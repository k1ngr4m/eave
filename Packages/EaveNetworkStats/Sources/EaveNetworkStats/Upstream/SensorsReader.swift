//
//  readers.swift
//  Sensors
//
//  Created by Serhiy Mytrovtsiy on 17/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import CStatsSensors

internal class SensorsReader: Reader<Sensors_List> {
    static let HIDtypes: [SensorType] = [.temperature, .voltage]

    internal var list: Sensors_List = Sensors_List()

    private var lastRead: TimeInterval = ProcessInfo.processInfo.systemUptime
    private var consumption: Double = 0
    private var sampledDuration: Double = 0
    private var lastIOSensorsRead: TimeInterval? = nil

    private var HIDState: Bool {
        Store.shared.bool(key: "Sensors_hid", defaultValue: SystemKit.shared.device.platform == .m1)
    }
    private var unknownSensorsState: Bool

    private var channels: CFMutableDictionary? = nil
    private var subscription: IOReportSubscriptionRef? = nil
    private var powers: (CPU: Double, GPU: Double, ANE: Double, RAM: Double, PCI: Double) = (0.0, 0.0, 0.0, 0.0, 0.0)

    init(callback: @escaping (T?) -> Void = {_ in }) {
        self.unknownSensorsState = Store.shared.bool(key: "Sensors_unknown", defaultValue: false)
        super.init(.sensors, callback: callback)

        self.channels = self.getChannels()
        var dict: Unmanaged<CFMutableDictionary>?
        if let channels = self.channels {
            self.subscription = IOReportCreateSubscription(nil, channels, &dict, 0, nil)
        }
        dict?.release()

        self.list.sensors = self.sensors()
    }

    deinit {
        AppleSiliconSensorsReset()
    }

    public override func stop() {
        super.stop()
        self.resetHIDSensors()
    }

    public override func terminate() {
        self.resetHIDSensors()
    }

    @objc private func resetHIDSensors() {
        AppleSiliconSensorsReset()
    }

    func resetSampling() {
        resetHIDSensors()
        lastRead = ProcessInfo.processInfo.systemUptime
        consumption = 0
        sampledDuration = 0
        lastIOSensorsRead = nil
        powers = (0, 0, 0, 0, 0)
        list.sensors = sensors()
    }

    private func sensors() -> [Sensor_p] {
        var available: [String] = HardwareAccess.smcKeys()
        var list: [Sensor_p] = []
        var sensorsList = SensorsList

        if let platform = SystemKit.shared.device.platform {
            sensorsList = sensorsList.filter({ $0.platforms.contains(platform) })
        }

        if let count = HardwareAccess.smcValue("FNum"), count.isFinite {
            list += self.loadFans(Int(min(10, max(0, count))))
        }

        available = available.filter({ (key: String) -> Bool in
            switch key.prefix(1) {
            case "T", "V", "P", "I": return true
            default: return false
            }
        })

        sensorsList.forEach { (s: Sensor) in
            if let idx = available.firstIndex(where: { $0 == s.key }) {
                list.append(s)
                available.remove(at: idx)
            }
        }
        sensorsList.filter{ $0.key.contains("%") }.forEach { (s: Sensor) in
            var index = 1
            for i in 0..<10 {
                let key = s.key.replacingOccurrences(of: "%", with: "\(i)")
                if let idx = available.firstIndex(where: { $0 == key }) {
                    var sensor = s.copy()
                    sensor.key = key
                    sensor.name = s.name.replacingOccurrences(of: "%", with: "\(index)")

                    list.append(sensor)
                    available.remove(at: idx)
                    index += 1
                }
            }
        }
        available.forEach { (key: String) in
            var type: SensorType? = nil
            switch key.prefix(1) {
            case "T": type = .temperature
            case "V": type = .voltage
            case "P": type = .power
            case "I": type = .current
            default: type = nil
            }
            if let t = type {
                list.append(Sensor(key: key, name: key, group: .unknown, type: t, platforms: []))
            }
        }

        for i in list.indices {
            list[i].value = Self.validValue(HardwareAccess.smcValue(list[i].key), type: list[i].type, group: list[i].group)
        }
        var results = list

        #if arch(arm64)
        if self.HIDState {
            results += self.initHIDSensors()
        }
        results += self.initIOSensors()
        #endif
        results += self.initCalculatedSensors(results)

        return results
    }

    public override func read() {
        var sensors = self.list.sensors
        for i in sensors.indices where sensors[i].group == .hid || sensors[i].isComputed {
            sensors[i].value = .nan
        }

        for i in sensors.indices {
            guard sensors[i].group != .hid && !sensors[i].isComputed else { continue }
            sensors[i].value = Self.validValue(HardwareAccess.smcValue(sensors[i].key), type: sensors[i].type, group: sensors[i].group)
        }

        var cpuSensors = sensors.filter({ $0.group == .CPU && $0.type == .temperature && $0.average }).map{ $0.value }.filter { $0.isFinite }
        var gpuSensors = sensors.filter({ $0.group == .GPU && $0.type == .temperature && $0.average }).map{ $0.value }.filter { $0.isFinite }
        let fanSensors = sensors.filter({ $0.type == .fan && !$0.isComputed && $0.value.isFinite })

        #if arch(arm64)
        if self.HIDState {
            for typ in SensorsReader.HIDtypes {
                let (page, usage, type) = self.m1Preset(type: typ)
                AppleSiliconSensors(page, usage, type).forEach { (key, value) in
                    guard let key = key as? String, let value = value as? Double, value.isFinite && value < 300 && value >= 0 else {
                        return
                    }

                    if let idx = sensors.firstIndex(where: { $0.group == .hid && $0.key == key }) {
                        sensors[idx].value = Self.validValue(value, type: sensors[idx].type, group: sensors[idx].group)
                    }
                }
            }

            cpuSensors += sensors.filter({ $0.key.hasPrefix("pACC MTR Temp") || $0.key.hasPrefix("eACC MTR Temp") }).map{ $0.value }.filter { $0.isFinite }
            gpuSensors += sensors.filter({ $0.key.hasPrefix("GPU MTR Temp") }).map{ $0.value }.filter { $0.isFinite }

            let socSensors = sensors.filter({ $0.key.hasPrefix("SOC MTR Temp") }).map{ $0.value }.filter { $0.isFinite }
            if !socSensors.isEmpty {
                if let idx = sensors.firstIndex(where: { $0.key == "Average SOC" }) {
                    sensors[idx].value = socSensors.reduce(0, +) / Double(socSensors.count)
                }
                if let max = socSensors.max() {
                    if let idx = sensors.firstIndex(where: { $0.key == "Hottest SOC" }) {
                        sensors[idx].value = max
                    }
                }
            }
        }

        if let (cpu, gpu, ane, ram, pci) = self.IOSensors() {
            if let idx = sensors.firstIndex(where: { $0.key == "CPU Power" }) {
                sensors[idx].value = cpu
            }
            if let idx = sensors.firstIndex(where: { $0.key == "GPU Power" }) {
                sensors[idx].value = gpu
            }
            if let idx = sensors.firstIndex(where: { $0.key == "ANE Power" }) {
                sensors[idx].value = ane
            }
            if let idx = sensors.firstIndex(where: { $0.key == "RAM Power" }) {
                sensors[idx].value = ram
            }
            if let idx = sensors.firstIndex(where: { $0.key == "PCI Power" }) {
                sensors[idx].value = pci
            }
        }
        #endif

        if !cpuSensors.isEmpty {
            if let idx = sensors.firstIndex(where: { $0.key == "Average CPU" }) {
                sensors[idx].value = cpuSensors.reduce(0, +) / Double(cpuSensors.count)
            }
            if let max = cpuSensors.max() {
                if let idx = sensors.firstIndex(where: { $0.key == "Hottest CPU" }) {
                    sensors[idx].value = max
                }
            }
        }
        if !gpuSensors.isEmpty {
            if let idx = sensors.firstIndex(where: { $0.key == "Average GPU" }) {
                sensors[idx].value = gpuSensors.reduce(0, +) / Double(gpuSensors.count)
            }
            if let max = gpuSensors.max() {
                if let idx = sensors.firstIndex(where: { $0.key == "Hottest GPU" }) {
                    sensors[idx].value = max
                }
            }
        }
        if !fanSensors.isEmpty {
            if let f = fanSensors.max(by: { $0.value < $1.value }) as? Fan {
                if let idx = sensors.firstIndex(where: { $0.key == "Fastest fan" }) {
                    if var fan = sensors[idx] as? Fan {
                        fan.value = f.value
                        fan.minSpeed = f.minSpeed
                        fan.maxSpeed = f.maxSpeed
                        sensors[idx] = fan
                    }
                }
            }
        }

        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastRead
        if let power = sensors.first(where: { $0.key == "PSTR" })?.value,
           power.isFinite, elapsed > 0 {
            consumption += power * elapsed / 3600
            sampledDuration += elapsed
            if let i = sensors.firstIndex(where: { $0.key == "Total System Consumption" }) {
                sensors[i].value = consumption
            }
            if let i = sensors.firstIndex(where: { $0.key == "Average System Total" }) {
                sensors[i].value = consumption * 3600 / sampledDuration
            }
        }
        lastRead = now

        // cut off low dc in voltage
        if let idx = sensors.firstIndex(where: { $0.key == "VD0R" }), sensors[idx].value < 0.4 {
            sensors[idx].value = 0
        }
        // cut off low dc in current
        if let idx = sensors.firstIndex(where: { $0.key == "ID0R" }), sensors[idx].value < 0.05 {
            sensors[idx].value = 0
        }

        let updated = Dictionary(sensors.map{ ($0.key, $0) }, uniquingKeysWith: { (first, _) in first })
        self.list.update { current in
            var list = current
            for i in list.indices {
                if let sensor = updated[list[i].key] {
                    list[i] = sensor
                }
            }
            return list
        }

        let snapshot = Sensors_List()
        snapshot.sensors = self.list.sensors
        self.callbackHandler(snapshot)
    }

    private func initCalculatedSensors(_ sensors: [Sensor_p]) -> [Sensor_p] {
        var list: [Sensor_p] = []

        var cpuSensors = sensors.filter({ $0.group == .CPU && $0.type == .temperature && $0.average }).map{ $0.value }.filter { $0.isFinite }
        var gpuSensors = sensors.filter({ $0.group == .GPU && $0.type == .temperature && $0.average }).map{ $0.value }.filter { $0.isFinite }

        #if arch(arm64)
        if self.HIDState {
            cpuSensors += sensors.filter({ $0.key.hasPrefix("pACC MTR Temp") || $0.key.hasPrefix("eACC MTR Temp") }).map{ $0.value }.filter { $0.isFinite }
            gpuSensors += sensors.filter({ $0.key.hasPrefix("GPU MTR Temp") }).map{ $0.value }.filter { $0.isFinite }
        }
        #endif

        let fanSensors = sensors.filter({ $0.type == .fan && !$0.isComputed && $0.value.isFinite })

        if !cpuSensors.isEmpty {
            let value = cpuSensors.reduce(0, +) / Double(cpuSensors.count)
            list.append(Sensor(key: "Average CPU", name: "Average CPU", value: value, group: .CPU, type: .temperature, platforms: Platform.all, isComputed: true))
            if let max = cpuSensors.max() {
                list.append(Sensor(key: "Hottest CPU", name: "Hottest CPU", value: max, group: .CPU, type: .temperature, platforms: Platform.all, isComputed: true))
            }
        }
        if !gpuSensors.isEmpty {
            let value = gpuSensors.reduce(0, +) / Double(gpuSensors.count)
            list.append(Sensor(key: "Average GPU", name: "Average GPU", value: value, group: .GPU, type: .temperature, platforms: Platform.all, isComputed: true))
            if let max = gpuSensors.max() {
                list.append(Sensor(key: "Hottest GPU", name: "Hottest GPU", value: max, group: .GPU, type: .temperature, platforms: Platform.all, isComputed: true))
            }
        }
        if !fanSensors.isEmpty {
            if let f = fanSensors.max(by: { $0.value < $1.value }) as? Fan {
                list.append(Fan(id: -1, key: "Fastest fan", name: "Fastest fan", minSpeed: f.minSpeed, maxSpeed: f.maxSpeed, value: f.value, isComputed: true))
            }
        }

        // Init total power since launched, only if Total Power sensor is available
        if sensors.contains(where: { $0.key == "PSTR"}) {
            list.append(Sensor(key: "Total System Consumption", name: "Total System Consumption", value: 0, group: .sensor, type: .energy, platforms: Platform.all, isComputed: true))
            list.append(Sensor(key: "Average System Total", name: "Average System Total", value: 0, group: .sensor, type: .power, platforms: Platform.all, isComputed: true))
        }

        return list.filter({ (s: Sensor_p) -> Bool in
            switch s.type {
            case .temperature:
                return s.value < 110 && s.value >= 0
            case .voltage:
                return s.value < 300 && s.value >= 0
            case .current:
                return s.value < 100 && s.value >= 0
            default: return true
            }
        }).sorted { $0.key.lowercased() < $1.key.lowercased() }
    }

    static func validValue(_ value: Double?, type: SensorType, group: SensorGroup? = nil) -> Double {
        guard let value, value.isFinite, value >= 0 else { return .nan }
        switch type {
        case .temperature: return ((group == .CPU ? 10.0 : 1.0)...120).contains(value) ? value : .nan
        case .voltage: return value < 300 ? value : .nan
        case .current: return value <= 100 ? value : .nan
        default: return value < Double(Int.max) / 100 ? value : .nan
        }
    }

    public func unknownCallback() {
        self.unknownSensorsState = Store.shared.bool(key: "Sensors_unknown", defaultValue: false)
    }
}

// MARK: - Fans

extension SensorsReader {
    private func loadFans(_ count: Int) -> [Sensor_p] {
        debug("Found \(Int(count)) fans", log: self.log)

        var list: [Fan] = []
        for i in 0..<Int(count) {
            var name = HardwareAccess.smcString("F\(i)ID")

            if name == nil && count == 2 {
                switch i {
                case 0:
                    name = localizedString("Left fan")
                case 1:
                    name = localizedString("Right fan")
                default: break
                }
            }

            list.append(Fan(
                id: i,
                key: "F\(i)Ac",
                name: name ?? "\(localizedString("Fan")) #\(i)",
                minSpeed: HardwareAccess.smcValue("F\(i)Mn") ?? 1,
                maxSpeed: HardwareAccess.smcValue("F\(i)Mx") ?? 1,
                value: HardwareAccess.smcValue("F\(i)Ac") ?? .nan
            ))
        }

        return list
    }

}

// MARK: - HID sensors

extension SensorsReader {
    private func m1Preset(type: SensorType) -> (Int32, Int32, Int32) {
        var page: Int32 = 0
        var usage: Int32 = 0
        var eventType: Int32 = kIOHIDEventTypeTemperature

        //  usagePage:
        //    kHIDPage_AppleVendor                        = 0xff00,
        //    kHIDPage_AppleVendorTemperatureSensor       = 0xff05,
        //    kHIDPage_AppleVendorPowerSensor             = 0xff08,
        //    kHIDPage_GenericDesktop
        //
        //  usage:
        //    kHIDUsage_AppleVendor_TemperatureSensor     = 0x0005,
        //    kHIDUsage_AppleVendorPowerSensor_Current    = 0x0002,
        //    kHIDUsage_AppleVendorPowerSensor_Voltage    = 0x0003,
        //    kHIDUsage_GD_Keyboard
        //

        switch type {
        case .temperature:
            page = 0xff00
            usage = 0x0005
            eventType = kIOHIDEventTypeTemperature
        case .current:
            page = 0xff08
            usage = 0x0002
            eventType = kIOHIDEventTypePower
        case .voltage:
            page = 0xff08
            usage = 0x0003
            eventType = kIOHIDEventTypePower
        case .power, .energy, .fan: break
        }

        return (page, usage, eventType)
    }

    private func initHIDSensors() -> [Sensor] {
        var list: [Sensor] = []

        for typ in SensorsReader.HIDtypes {
            let (page, usage, type) = self.m1Preset(type: typ)
            if let sensors = AppleSiliconSensors(page, usage, type) {
                sensors.forEach { (key, value) in
                    guard let key = key as? String, let value = value as? Double else {
                        return
                    }
                    var name: String = key

                    HIDSensorsList.forEach { (s: Sensor) in
                        if s.key.contains("%") {
                            var index = 1
                            for i in 0..<64 {
                                if s.key.replacingOccurrences(of: "%", with: "\(i)") == key {
                                    name = s.name.replacingOccurrences(of: "%", with: "\(index)")
                                }
                                index += 1
                            }
                        } else if s.key == key {
                            name = s.name
                        }
                    }

                    list.append(Sensor(
                        key: key,
                        name: name,
                        value: value,
                        group: .hid,
                        type: typ,
                        platforms: Platform.all
                    ))
                }
            }
        }

        let socSensors = list.filter({ $0.key.hasPrefix("SOC MTR Temp") }).map{ $0.value }.filter { $0.isFinite }
        if !socSensors.isEmpty {
            let value = socSensors.reduce(0, +) / Double(socSensors.count)
            list.append(Sensor(key: "Average SOC", name: "Average SOC", value: value, group: .hid, type: .temperature, platforms: Platform.all))
            if let max = socSensors.max() {
                list.append(Sensor(key: "Hottest SOC", name: "Hottest SOC", value: max, group: .hid, type: .temperature, platforms: Platform.all))
            }
        }

        return list.filter({ (s: Sensor_p) -> Bool in
            switch s.type {
            case .temperature:
                return s.value < 110 && s.value >= 0
            case .voltage:
                return s.value < 300 && s.value >= 0
            case .current:
                return s.value < 100 && s.value >= 0
            default: return true
            }
        }).sorted { $0.key.lowercased() < $1.key.lowercased() }
    }

    public func HIDCallback() {
        if self.HIDState {
            let hidSensors = self.initHIDSensors()
            self.list.update { current in
                current + hidSensors.filter({ (s: Sensor_p) in !current.contains(where: { $0.key == s.key }) })
            }
        } else {
            self.resetHIDSensors()
            self.list.update { current in
                current.filter({ $0.group != .hid })
            }
        }
    }
}

// MARK: - Apple Silicon power sensors

extension SensorsReader {
    private func getChannels() -> CFMutableDictionary? {
        let channelNames: [(String, String?)] = [("Energy Model", nil)]

        var channels: [CFDictionary] = []
        for (gname, sname) in channelNames {
            let channel = IOReportCopyChannelsInGroup(gname as CFString?, sname as CFString?, 0, 0, 0)
            guard let channel = channel?.takeRetainedValue() else { continue }
            channels.append(channel)
        }

        guard let chan = channels.first else { return nil }
        for i in 1..<channels.count {
            IOReportMergeChannels(chan, channels[i], nil)
        }

        let size = CFDictionaryGetCount(chan)
        guard let channel = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, size, chan),
              let chan = channel as? [String: Any], chan["IOReportChannels"] != nil else {
            return nil
        }

        return channel
    }

    private func initIOSensors() -> [Sensor] {
        guard let (cpu, gpu, ane, ram, pci) = self.IOSensors() else { return [] }
        return [
            Sensor(key: "CPU Power", name: "CPU Power", value: cpu, group: .CPU, type: .power, platforms: Platform.apple, isComputed: true),
            Sensor(key: "GPU Power", name: "GPU Power", value: gpu, group: .GPU, type: .power, platforms: Platform.apple, isComputed: true),
            Sensor(key: "ANE Power", name: "ANE Power", value: ane, group: .system, type: .power, platforms: Platform.apple, isComputed: true),
            Sensor(key: "RAM Power", name: "RAM Power", value: ram, group: .system, type: .power, platforms: Platform.apple, isComputed: true),
            Sensor(key: "PCI Power", name: "PCI Power", value: pci, group: .system, type: .power, platforms: Platform.apple, isComputed: true)
        ]
    }

    static func appleSiliconPower(currentEnergy: Double, previousEnergy: Double, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, currentEnergy.isFinite, previousEnergy.isFinite, currentEnergy >= previousEnergy else { return .nan }
        return (currentEnergy - previousEnergy) / elapsed
    }

    private func IOSensors() -> (Double, Double, Double, Double, Double)? {
        guard subscription != nil, channels != nil,
              let reportSample = IOReportCreateSamples(self.subscription, self.channels, nil)?.takeRetainedValue(),
              let dict = reportSample as? [String: Any],
              let channelsList = dict["IOReportChannels"] as? NSArray else {
            return nil
        }
        let items = channelsList as CFArray
        let now = ProcessInfo.processInfo.systemUptime

        let prevCPU = self.powers.CPU
        let prevGPU = self.powers.GPU
        let prevANE = self.powers.ANE
        let prevRAM = self.powers.RAM
        let prevPCI = self.powers.PCI

        self.powers = (.nan, .nan, .nan, .nan, .nan)
        for i in 0..<CFArrayGetCount(items) {
            let dict = CFArrayGetValueAtIndex(items, i)
            let item = unsafeBitCast(dict, to: CFDictionary.self)

            guard let group = IOReportChannelGetGroup(item)?.takeUnretainedValue() as? String,
                  group == "Energy Model",
                  let channel = IOReportChannelGetChannelName(item)?.takeUnretainedValue() as? String,
                  let unit = IOReportChannelGetUnitLabel(item)?.takeUnretainedValue() as? String else { continue }

            let value = Double(IOReportSimpleGetIntegerValue(item, 0))

            if channel.hasSuffix("CPU Energy") {
                self.powers.CPU = value.power(unit)
            } else if channel.hasSuffix("GPU Energy") {
                self.powers.GPU = value.power(unit)
            } else if channel.starts(with: "ANE") {
                self.powers.ANE = value.power(unit)
            } else if channel.starts(with: "DRAM") {
                self.powers.RAM = value.power(unit)
            } else if channel.starts(with: "PCI") && channel.hasSuffix("Energy") {
                self.powers.PCI = value.power(unit)
            }
        }

        guard let lastIOSensorsRead = self.lastIOSensorsRead else {
            self.lastIOSensorsRead = now
            return (.nan, .nan, .nan, .nan, .nan)
        }
        let elapsed = now - lastIOSensorsRead
        defer { self.lastIOSensorsRead = now }
        return (
            Self.appleSiliconPower(currentEnergy: self.powers.CPU, previousEnergy: prevCPU, elapsed: elapsed),
            Self.appleSiliconPower(currentEnergy: self.powers.GPU, previousEnergy: prevGPU, elapsed: elapsed),
            Self.appleSiliconPower(currentEnergy: self.powers.ANE, previousEnergy: prevANE, elapsed: elapsed),
            Self.appleSiliconPower(currentEnergy: self.powers.RAM, previousEnergy: prevRAM, elapsed: elapsed),
            Self.appleSiliconPower(currentEnergy: self.powers.PCI, previousEnergy: prevPCI, elapsed: elapsed)
        )
    }
}
