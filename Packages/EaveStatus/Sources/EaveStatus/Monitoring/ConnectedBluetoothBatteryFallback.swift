// Copyright (C) 2024-2026 Atoll Contributors
// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from Eave BluetoothAudioManager; this file retains its original license.

import Foundation
import IOKit

/// Eave's former cache/GATT fallback, shared with the menu and limited to
/// connected audio devices whose system report and accessory sources lack a level.
@MainActor
final class ConnectedBluetoothBatteryFallback {
    typealias Cache = (devices: [String: [String: Any]], identifiers: [String: [String: Any]], registry: [[String: Any]])
    private let scanner: any BluetoothLEBatteryScanning
    private let readCache: @MainActor () -> Cache
    private var addressesByID: [UUID: String] = [:]
    private var baseLevels: [String: BluetoothBatteryLevel] = [:]
    private var completion: (([String: BluetoothBatteryLevel]) -> Void)?
    private var generation: UInt64 = 0
    private var cachedReadings: [UUID: NearbyBluetoothBatteryDevice] = [:]

    init(scanner: any BluetoothLEBatteryScanning = CoreBluetoothLEBatteryScanner(),
         readCache: @escaping @MainActor () -> Cache = ConnectedBluetoothBatteryFallback.systemCache) {
        self.scanner = scanner
        self.readCache = readCache
    }

    func read(devices: [BluetoothDevice], levels: [String: BluetoothBatteryLevel],
              completion: @escaping ([String: BluetoothBatteryLevel]) -> Void) {
        let missing = devices.filter {
            $0.isConnected && ($0.kind.isAudio || $0.airPodsModel != nil)
                && levels[BluetoothBatteryReader.normalizedAddress($0.id)] == nil
        }
        guard !missing.isEmpty else { stop(); return }
        let cache = readCache()
        let devicesByName = Dictionary(grouping: devices.filter(\.isConnected)) { Self.normalizedName($0.name) }
        baseLevels = levels
        for device in missing {
            let address = BluetoothBatteryReader.normalizedAddress(device.id)
            if let level = Self.cachedLevel(for: device, cache: cache,
                allowNameMatch: devicesByName[Self.normalizedName(device.name)]?.count == 1) { baseLevels[address] = level }
        }
        self.completion = completion
        completion(baseLevels)
        var permitted: [UUID: String] = [:]
        var ambiguousIDs: Set<UUID> = []
        for device in missing where baseLevels[BluetoothBatteryReader.normalizedAddress(device.id)] == nil {
            if let uuid = Self.peripheralID(for: device, cache: cache.identifiers,
                allowNameMatch: devicesByName[Self.normalizedName(device.name)]?.count == 1), !ambiguousIDs.contains(uuid) {
                if permitted[uuid] != nil {
                    permitted.removeValue(forKey: uuid)
                    ambiguousIDs.insert(uuid)
                } else {
                    permitted[uuid] = BluetoothBatteryReader.normalizedAddress(device.id)
                }
            }
        }
        generation &+= 1
        let request = generation
        addressesByID = permitted
        cachedReadings = cachedReadings.filter { permitted[$0.key] != nil }
        scanner.onDevicesChanged = { [weak self] readings in
            guard let self, self.generation == request else { return }
            for reading in readings { self.cachedReadings[reading.id] = reading }
            var merged = self.baseLevels
            for reading in self.cachedReadings.values {
                guard let address = self.addressesByID[reading.id],
                      merged[address] == nil,
                      (0...100).contains(reading.batteryLevel),
                      Date().timeIntervalSince(reading.lastUpdated) < BluetoothLEBatteryScanPolicy.resultLifetime else { continue }
                merged[address] = BluetoothBatteryLevel(deviceAddress: address, main: reading.batteryLevel,
                                                       left: nil, right: nil, caseLevel: nil)
            }
            self.completion?(merged)
        }
        scanner.onDevicesChanged?([])
        scanner.setAllowedReadDeviceIDs(Set(permitted.keys))
        if permitted.isEmpty {
            scanner.stop()
        } else if scanner.isRunning {
            scanner.refresh()
        } else {
            scanner.start()
        }
    }

    func stop() {
        generation &+= 1
        completion = nil
        addressesByID = [:]
        baseLevels = [:]
        scanner.onDevicesChanged = nil
        scanner.setAllowedReadDeviceIDs([])
        scanner.stop()
    }

    static func cachedLevel(for device: BluetoothDevice, cache: Cache, allowNameMatch: Bool = true) -> BluetoothBatteryLevel? {
        let records = cache.registry.map { ("", $0) } + cache.devices.map { ($0.key, $0.value) }
        let address = BluetoothBatteryReader.normalizedAddress(device.id)
        let addressMatches = records.filter { identifiers(key: $0.0, payload: $0.1).contains(address) }
        let matches = addressMatches.isEmpty
            ? records.filter { allowNameMatch && identifiers(key: $0.0, payload: $0.1).isEmpty && names($0.1).contains(normalizedName(device.name)) }
            : addressMatches
        for (_, payload) in matches {
            let main = percentage(payload, keys: ["BatteryPercent", "BatteryPercentSingle", "BatteryPercentCombined", "BatteryPercentMain", "device_batteryLevelMain", "Battery Level"])
            let left = percentage(payload, keys: ["BatteryPercentLeft", "device_batteryLevelLeft", "Left Battery Level"])
            let right = percentage(payload, keys: ["BatteryPercentRight", "device_batteryLevelRight", "Right Battery Level"])
            let caseLevel = percentage(payload, keys: ["BatteryPercentCase", "device_batteryLevelCase"])
            let serviceLevel = (payload["Services"] as? [[String: Any]] ?? []).flatMap {
                ($0["BatteryPercentages"] as? [String: Any] ?? [:]).values.compactMap(percentage)
            }.max()
            guard main != nil || left != nil || right != nil || caseLevel != nil || serviceLevel != nil else { continue }
            return BluetoothBatteryLevel(deviceAddress: device.id, main: main ?? serviceLevel,
                                         left: left, right: right, caseLevel: caseLevel)
        }
        return nil
    }

    static func peripheralID(for device: BluetoothDevice, cache: [String: [String: Any]], allowNameMatch: Bool = true) -> UUID? {
        let address = BluetoothBatteryReader.normalizedAddress(device.id)
        let direct = cache.filter { identifiers(key: "", payload: $0.value).contains(address) }
        if direct.count == 1 { return UUID(uuidString: direct.first!.key) }
        guard allowNameMatch else { return nil }
        let matchingNames = cache.filter {
            identifiers(key: "", payload: $0.value).isEmpty && names($0.value).contains(normalizedName(device.name))
        }
        // A shared default name is not enough to connect the wrong peripheral.
        return matchingNames.count == 1 ? UUID(uuidString: matchingNames.first!.key) : nil
    }

    private static func identifiers(key: String, payload: [String: Any]) -> Set<String> {
        Set(([key] + ["DeviceAddress", "Address", "BD_ADDR", "SerialNumber", "device_address"].compactMap {
            string(payload[$0])
        }).map(BluetoothBatteryReader.normalizedAddress).filter { $0.count == 12 })
    }

    private static func names(_ payload: [String: Any]) -> Set<String> {
        Set(["Name", "DeviceName", "ProductName", "Product", "device_name", "USB Product Name", "Bluetooth Product Name"]
            .compactMap { string(payload[$0]) }.map(normalizedName).filter { !$0.isEmpty })
    }

    private static func normalizedName(_ value: String) -> String { value.lowercased().filter { $0.isLetter || $0.isNumber } }
    private static func string(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        return (value as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }
    private static func percentage(_ payload: [String: Any], keys: [String]) -> Int? { keys.compactMap { payload[$0].flatMap(percentage) }.first }
    private static func percentage(_ value: Any) -> Int? {
        let value = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap { Double($0.replacingOccurrences(of: "%", with: "")) }
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        return Int(value.rounded())
    }

    private static func systemCache() -> Cache {
        let preferences = UserDefaults(suiteName: "/Library/Preferences/com.apple.Bluetooth")
        var registry: [[String: Any]] = []
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            var entry = IOIteratorNext(iterator)
            while entry != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let payload = properties?.takeRetainedValue() as? [String: Any] { registry.append(payload) }
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
        }
        return (preferences?.object(forKey: "DeviceCache") as? [String: [String: Any]] ?? [:],
                preferences?.object(forKey: "CoreBluetoothCache") as? [String: [String: Any]] ?? [:], registry)
    }
}
