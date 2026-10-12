/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import Combine
import AppKit
import Defaults
import SwiftUI
import IOBluetooth
import EaveStatus

/// Presents Eave's Bluetooth HUD from the same readings as the menu panel.
class BluetoothAudioManager: ObservableObject {
    static let shared = BluetoothAudioManager()

    @Published var lastConnectedDevice: BluetoothAudioDevice?
    @Published var connectedDevices: [BluetoothAudioDevice] = []
    @Published var isBluetoothAudioConnected = false
    @Published private(set) var activeListeningModeEvent: AirPodsListeningModeEvent?
    var requestStatusRefresh: (@MainActor () -> Void)?

    private var hasInitialStatus = false
    private var cancellables = Set<AnyCancellable>()
    private let coordinator = DynamicIslandViewCoordinator.shared
    private let appleVendorID: UInt16 = 0x05AC
    private let devicePIDMap: [UInt16: BluetoothAudioDeviceType] = [
        0x2002: .airpods,      // Gen 1 AirPods
        0x200F: .airpods,      // Gen 2 AirPods
        0x2013: .airpodsGen3,  // Gen 3 AirPods
        0x2019: .airpodsGen4,  // Gen 4 AirPods
        0x201B: .airpodsGen4,  // Gen 4 AirPods ANC
        0x200A: .airpodsMax,   // AirPods Max Lightning
        0x201F: .airpodsMax,   // AirPods Max USB-C
        0x200E: .airpodsPro,   // AirPods Pro Gen 1
        0x2014: .airpodsPro,   // AirPods Pro Gen 2 Lightning
        0x2024: .airpodsPro,   // AirPods Pro Gen 2 USB-C
        0x2027: .airpodsPro3,  // AirPods Pro Gen 3
        0x2017: .beatsstudio,  // Beats Studio Pro
        0x2009: .beatsstudio,  // Beats Studio 3
        0x2006: .beatssolo,    // Beats Solo 3
        0x200C: .beatssolo     // Beats Solo Pro
    ]

    private var hudBatteryWaitTasks: [UUID: Task<Void, Never>] = [:]
    private let hudBatteryWaitInterval: TimeInterval = 0.3
    private let hudBatteryWaitTimeout: TimeInterval = 1.8
    private var listeningModeClearTask: Task<Void, Never>?
    private var listeningModePresentationTask: Task<Void, Never>?
    private var lastListeningModeByAddress: [String: AirPodsListeningMode] = [:]
    private var listeningModeRefreshTask: Task<Void, Never>?
    private let listeningModeLogObserver = AirPodsListeningModeLogObserver()
    private let listeningModeNotificationNames: [Notification.Name] = [
        Notification.Name("com.apple.AudioAccessory.prefsChanged"),
        Notification.Name("com.apple.AudioAccessory.daemonStarted"),
        Notification.Name("com.apple.AudioAccessory.cdMsgNotification"),
        Notification.Name("com.apple.bluetooth.status"),
        Notification.Name("com.apple.Bluetooth.StatusNotification"),
        Notification.Name("com.apple.Bluetooth.DeviceUpdated"),
        Notification.Name("com.apple.Bluetooth.DeviceChanged"),
        Notification.Name("com.apple.Bluetooth.DevicePropertiesChanged"),
        Notification.Name("com.apple.Bluetooth.AudioDevicePropertiesChanged"),
        Notification.Name("com.apple.BluetoothServices.AudioDeviceChanged"),
        Notification.Name("com.apple.BluetoothServices.AudioDevicePropertiesChanged"),
        Notification.Name("com.apple.bluetooth.device.updated"),
        Notification.Name("com.apple.bluetooth.device.changed"),
        Notification.Name("com.apple.bluetooth.audio.changed"),
        Notification.Name("com.apple.controlcenter.airpodspro.settingschanged")
    ]

    private init() {
        setupAirPodsListeningModeObservers()
        setupAirPodsListeningModeLogObserver()
    }

    deinit { cleanup() }

    /// The first successful reading is the startup baseline, not a connection.
    /// Stable IDs let a later battery update complete the existing HUD wait.
    @MainActor
    func applyStatus(_ state: MenuBarBluetoothState) {
        guard state.isAuthoritative else { return }
        let previous = Dictionary(connectedDevices.map { (normalizeBluetoothIdentifier($0.address), $0) }, uniquingKeysWith: { first, _ in first })
        let latest = state.devices.filter { $0.isConnected && $0.isAudio }.map { device in
            let old = previous[normalizeBluetoothIdentifier(device.id)]
            return BluetoothAudioDevice(
                id: old?.id ?? UUID(), name: device.name, address: device.id,
                batteryLevel: device.batteryPercentage,
                deviceType: detectDeviceType(from: device)
            )
        }
        let newIDs = Set(latest.map(\.id))
        connectedDevices.filter { !newIDs.contains($0.id) }.forEach { cancelHUDBatteryWait(for: $0) }
        connectedDevices = latest
        isBluetoothAudioConnected = !latest.isEmpty
        if let current = lastConnectedDevice, let updated = latest.first(where: { $0.id == current.id }) {
            lastConnectedDevice = updated
        } else {
            lastConnectedDevice = latest.last
        }
        updateActiveBluetoothHUDBattery(with: lastConnectedDevice?.batteryLevel)
        let newlyConnected = latest.filter { previous[normalizeBluetoothIdentifier($0.address)] == nil }
        if hasInitialStatus {
            for device in newlyConnected {
                lastConnectedDevice = device
                showDeviceConnectedHUD(device)
            }
        }
        hasInitialStatus = true
    }

    /// Watches private Bluetooth/Control Center notifications that Apple posts
    /// when AirPods device properties change. The actual keys are OS-version
    /// dependent, so the handler parses the payload first and then falls back to
    /// a one-shot IORegistry read triggered by the event.
    private func setupAirPodsListeningModeObservers() {
        let dnc = DistributedNotificationCenter.default()

        for name in listeningModeNotificationNames {
            dnc.addObserver(
                self,
                selector: #selector(handleAirPodsListeningModeNotification(_:)),
                name: name,
                object: nil
            )
        }

        dnc.addObserver(
            self,
            selector: #selector(handlePotentialAirPodsListeningModeNotification(_:)),
            name: nil,
            object: nil
        )

        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        for name in listeningModeNotificationNames {
            CFNotificationCenterAddObserver(
                darwinCenter,
                Unmanaged.passUnretained(self).toOpaque(),
                { _, observer, cfName, _, _ in
                    guard let observer, let cfName else { return }
                    let manager = Unmanaged<BluetoothAudioManager>.fromOpaque(observer).takeUnretainedValue()
                    let name = cfName.rawValue as String
                    manager.handleAirPodsListeningModeDarwinNotification(name)
                },
                name.rawValue as CFString,
                nil,
                .deliverImmediately
            )
        }
    }

    private func setupAirPodsListeningModeLogObserver() {
        listeningModeLogObserver.onModeChange = { [weak self] mode, address in
            Task { @MainActor in
                self?.handleListeningMode(mode, address: address)
            }
        }

        if Defaults[.showAirPodsListeningModeChanges] {
            listeningModeLogObserver.start()
        }

        Defaults.publisher(.showAirPodsListeningModeChanges, options: [])
            .sink { [weak self] change in
                if change.newValue {
                    self?.listeningModeLogObserver.start()
                } else {
                    self?.listeningModeLogObserver.stop()
                }
            }
            .store(in: &cancellables)
    }

    @objc private func handleAirPodsListeningModeNotification(_ notification: Notification) {
        guard Defaults[.showAirPodsListeningModeChanges] else { return }
        if let event = listeningModeEvent(from: notification.userInfo) {
            presentListeningModeIfChanged(event)
            return
        }
        scheduleEventDrivenListeningModeRefresh(reason: notification.name.rawValue)
    }

    @objc private func handlePotentialAirPodsListeningModeNotification(_ notification: Notification) {
        guard Defaults[.showAirPodsListeningModeChanges] else { return }
        let name = notification.name.rawValue.lowercased()
        let payload = notification.userInfo?
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
            .lowercased() ?? ""

        let hasExplicitModePayload = payload.contains("listening") ||
            payload.contains("lsnm") ||
            payload.contains("noisecontrol") ||
            payload.contains("anc") ||
            payload.contains("transparency") ||
            payload.contains("adaptive") ||
            payload.contains("conversation")

        let isSpecificSettingsNotification = name.contains("airpodspro.settingschanged") ||
            name.contains("audioaccessory.prefschanged") ||
            name.contains("controlcenter.airpods")

        guard hasExplicitModePayload || isSpecificSettingsNotification else { return }
        scheduleEventDrivenListeningModeRefresh(reason: notification.name.rawValue)
    }

    private func handleAirPodsListeningModeDarwinNotification(_ name: String) {
        guard Defaults[.showAirPodsListeningModeChanges] else { return }
        scheduleEventDrivenListeningModeRefresh(reason: name)
    }

    @MainActor
    private func handleListeningMode(_ mode: AirPodsListeningMode, address: String?) {
        guard Defaults[.showAirPodsListeningModeChanges] else { return }

        let normalizedAddress = address.map(normalizeBluetoothIdentifier)
        let device = connectedDevices.first { candidate in
            guard candidate.deviceType.isAirPods else { return false }
            if let normalizedAddress {
                return normalizeBluetoothIdentifier(candidate.address) == normalizedAddress
            }
            return true
        } ?? primaryConnectedAirPodsDevice()

        guard let device else { return }
        presentListeningModeIfChanged(AirPodsListeningModeEvent(device: device, mode: mode))
    }

    private func detectDeviceType(from device: MenuBarBluetoothDevice) -> BluetoothAudioDeviceType {
        let lowercaseName = device.name.lowercased()

        if let productID = device.productID, let pid = UInt16(exactly: productID),
           device.vendorID == nil || device.vendorID == Int(appleVendorID),
           let pidBasedType = devicePIDMap[pid] {
            return pidBasedType
        }

        // Check for specific AirPods models
        if lowercaseName.contains("airpods") {
            if lowercaseName.contains("max") {
                return .airpodsMax
            } else if lowercaseName.contains("pro") {
                if lowercaseName.contains("3") || lowercaseName.contains("gen 3") || lowercaseName.contains("gen3") {
                    return .airpodsPro3
                }
                return .airpodsPro
            } else if lowercaseName.contains("gen 4")
                        || lowercaseName.contains("gen4")
                        || lowercaseName.contains("4th")
                        || lowercaseName.contains("airpods 4")
                        || lowercaseName.contains("airpods4") {
                return .airpodsGen4
            } else if lowercaseName.contains("gen 3")
                        || lowercaseName.contains("gen3")
                        || lowercaseName.contains("3rd")
                        || lowercaseName.contains("third")
                        || lowercaseName.contains("airpods 3")
                        || lowercaseName.contains("airpods3") {
                return .airpodsGen3
            }
            return .airpods
        }

        // Check for other brands
        if lowercaseName.contains("beats") {
            if lowercaseName.contains("studio") {
                return .beatsstudio
            }
            if lowercaseName.contains("solo") {
                return .beatssolo
            }
            return .beatssolo
        } else if lowercaseName.contains("speaker") || lowercaseName.contains("boombox") {
            return .speaker
        } else if lowercaseName.contains("headphone") || lowercaseName.contains("headset") ||
                  lowercaseName.contains("buds") || lowercaseName.contains("earbuds") {
            return .headphones
        }

        // Check device class for more specific detection
        let address = stride(from: 0, to: device.id.count, by: 2).map { offset in
            String(device.id.dropFirst(offset).prefix(2))
        }.joined(separator: ":")
        let deviceClass = IOBluetoothDevice(addressString: address)?.classOfDevice ?? 0
        let minorClass = (deviceClass >> 2) & 0x3F

        // Minor classes for audio devices
        switch minorClass {
        case 0x01: return .headphones  // Wearable Headset
        case 0x02: return .headphones  // Hands-free
        case 0x06: return .headphones  // Headphones
        case 0x08: return .speaker     // Portable Audio
        case 0x0C: return .speaker     // Loudspeaker
        default: return .generic
        }
    }

    private func updateActiveBluetoothHUDBattery(with level: Int?) {
        guard let level else { return }
        DispatchQueue.main.async {
            guard self.coordinator.sneakPeek.show,
                  self.coordinator.sneakPeek.type == .bluetoothAudio,
                  self.coordinator.sneakPeek.value >= 0 else { return }
            self.coordinator.sneakPeek.value = CGFloat(level) / 100.0
        }
    }

    private func bestBatteryLevel(for device: BluetoothAudioDevice) -> Int? { device.batteryLevel }
    private func clampBatteryPercentage(_ value: Int) -> Int { min(max(value, 0), 100) }

    private func cancelHUDBatteryWait(for device: BluetoothAudioDevice) {
        let cancelBlock = { [weak self] in
            guard let self else { return }
            self.hudBatteryWaitTasks[device.id]?.cancel()
            self.hudBatteryWaitTasks.removeValue(forKey: device.id)
        }

        if Thread.isMainThread {
            cancelBlock()
        } else {
            DispatchQueue.main.async(execute: cancelBlock)
        }
    }

    private func normalizeBluetoothIdentifier(_ value: String) -> String {
        return value
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    // MARK: - HUD Display

    /// Shows HUD notification for newly connected audio device
    private func showDeviceConnectedHUD(_ device: BluetoothAudioDevice) {
        guard Defaults[.showBluetoothDeviceConnections] else { return }

        cancelHUDBatteryWait(for: device)

        if let battery = bestBatteryLevel(for: device) {
            presentDeviceConnectedHUD(device: device, batteryLevel: battery)
            return
        }

        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(self.hudBatteryWaitTimeout)
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: UInt64(self.hudBatteryWaitInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }

                let batteryInfo = await MainActor.run { () -> (BluetoothAudioDevice, Int)? in
                    guard let refreshedDevice = self.connectedDevices.first(where: { $0.id == device.id }),
                          let battery = self.bestBatteryLevel(for: refreshedDevice) else {
                        return nil
                    }
                    return (refreshedDevice, battery)
                }

                if let (refreshedDevice, battery) = batteryInfo {
                    await MainActor.run {
                        self.presentDeviceConnectedHUD(device: refreshedDevice, batteryLevel: battery)
                    }
                    self.cancelHUDBatteryWait(for: device)
                    return
                }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.presentDeviceConnectedHUD(device: device, batteryLevel: nil)
            }
            self.cancelHUDBatteryWait(for: device)
        }

        hudBatteryWaitTasks[device.id] = task
    }

    private func presentDeviceConnectedHUD(device: BluetoothAudioDevice, batteryLevel: Int?) {
        guard Defaults[.showBluetoothDeviceConnections] else { return }

        print("🎧 [BluetoothAudioManager] 📱 Showing device connected HUD")

        let batteryValue: CGFloat = if let batteryLevel {
            CGFloat(clampBatteryPercentage(batteryLevel)) / 100.0
        } else {
            0.0
        }

        HUDSuppressionCoordinator.shared.suppressVolumeHUD(for: 1.5)

        Task { @MainActor in
            coordinator.toggleSneakPeek(
                status: true,
                type: .bluetoothAudio,
                duration: 2.5,
                value: batteryValue,
                icon: device.deviceType.sfSymbol
            )
        }
    }

    private func scheduleEventDrivenListeningModeRefresh(reason: String) {
        listeningModeRefreshTask?.cancel()
        listeningModeRefreshTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard let self, !Task.isCancelled else { return }

            await MainActor.run {
                guard let device = self.primaryConnectedAirPodsDevice(),
                      let mode = self.readListeningModeViaDynamicSelectors(for: device) ??
                        Self.readListeningModeFromIORegistry() else {
                    return
                }

                self.presentListeningModeIfChanged(
                    AirPodsListeningModeEvent(device: device, mode: mode)
                )
            }
        }
    }

    private func presentListeningModeIfChanged(_ event: AirPodsListeningModeEvent) {
        guard Defaults[.showAirPodsListeningModeChanges] else { return }
        guard event.device.deviceType.isAirPods else { return }

        let address = event.device.address
        guard lastListeningModeByAddress[address] != event.mode else { return }

        listeningModePresentationTask?.cancel()
        listeningModePresentationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.presentStableListeningMode(event)
        }
    }

    private func presentStableListeningMode(_ event: AirPodsListeningModeEvent) {
        guard Defaults[.showAirPodsListeningModeChanges] else { return }
        guard event.device.deviceType.isAirPods else { return }

        let address = event.device.address
        guard lastListeningModeByAddress[address] != event.mode else { return }
        lastListeningModeByAddress[address] = event.mode
        activeListeningModeEvent = event

        print("🎧 [BluetoothAudioManager] 🎚️ AirPods listening mode changed: \(event.mode.displayName)")

        HUDSuppressionCoordinator.shared.suppressVolumeHUD(for: 1.5)

        Task { @MainActor in
            coordinator.toggleSneakPeek(
                status: true,
                type: .bluetoothAudio,
                duration: 2.5,
                value: -1,
                icon: event.mode.sfSymbol
            )
        }

        listeningModeClearTask?.cancel()
        let eventID = event.id
        listeningModeClearTask = Task { @MainActor [weak self, eventID] in
            try? await Task.sleep(nanoseconds: 2_700_000_000)
            guard !Task.isCancelled else { return }
            if self?.activeListeningModeEvent?.id == eventID {
                self?.activeListeningModeEvent = nil
            }
        }
    }

    private func listeningModeEvent(from userInfo: [AnyHashable: Any]?) -> AirPodsListeningModeEvent? {
        guard let mode = AirPodsListeningMode.from(userInfo: userInfo),
              let device = deviceMatchingListeningModePayload(userInfo) ?? primaryConnectedAirPodsDevice() else {
            return nil
        }

        return AirPodsListeningModeEvent(device: device, mode: mode)
    }

    private func deviceMatchingListeningModePayload(_ userInfo: [AnyHashable: Any]?) -> BluetoothAudioDevice? {
        guard let userInfo else { return nil }

        let payloadText = userInfo.values
            .map { "\($0)" }
            .joined(separator: " ")
            .lowercased()

        return connectedDevices.first { device in
            device.deviceType.isAirPods &&
            (
                payloadText.contains(device.address.lowercased()) ||
                payloadText.contains(normalizeBluetoothIdentifier(device.address)) ||
                payloadText.contains(device.name.lowercased())
            )
        }
    }

    private func primaryConnectedAirPodsDevice() -> BluetoothAudioDevice? {
        if let device = lastConnectedDevice, device.deviceType.isAirPods {
            return device
        }

        return connectedDevices.first { $0.deviceType.isAirPods }
    }

    private func readListeningModeViaDynamicSelectors(for device: BluetoothAudioDevice) -> AirPodsListeningMode? {
        guard let ioDevice = ioBluetoothDevice(for: device) else { return nil }
        let selectors = [
            "listeningMode",
            "LsnM",
            "noiseControlMode",
            "activeNoiseControlMode",
            "activeNoiseCancellationMode",
            "ancMode",
            "bluetoothListeningMode",
            "adaptiveAudioMode",
            "conversationAwarenessMode"
        ]

        for selectorName in selectors {
            let selector = NSSelectorFromString(selectorName)
            guard ioDevice.responds(to: selector),
                  let value = ioDevice.perform(selector)?.takeUnretainedValue(),
                  let mode = AirPodsListeningMode.from(value) else {
                continue
            }

            return mode
        }

        return nil
    }

    private func ioBluetoothDevice(for device: BluetoothAudioDevice) -> IOBluetoothDevice? {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return nil
        }

        return pairedDevices.first { ioDevice in
            let address = ioDevice.addressString ?? ""
            return normalizeBluetoothIdentifier(address) == normalizeBluetoothIdentifier(device.address)
        }
    }

    private static func readListeningModeFromIORegistry() -> AirPodsListeningMode? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-r", "-l", "-w", "0"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        let interestingLines = output
            .components(separatedBy: .newlines)
            .filter {
                let lowercased = $0.lowercased()
                return lowercased.contains("airpods") ||
                    lowercased.contains("listening") ||
                    lowercased.contains("noise") ||
                    lowercased.contains("transparency") ||
                    lowercased.contains("adaptive") ||
                    lowercased.contains("conversation")
            }

        return AirPodsListeningMode.from(interestingLines.joined(separator: "\n"))
    }

    // MARK: - Cleanup

    private func cleanup() {
        print("🎧 [BluetoothAudioManager] Cleaning up observers...")

        let dnc = DistributedNotificationCenter.default()
        dnc.removeObserver(self)
        cancellables.removeAll()
        hudBatteryWaitTasks.values.forEach { $0.cancel() }
        hudBatteryWaitTasks.removeAll()
        listeningModeRefreshTask?.cancel()
        listeningModeClearTask?.cancel()
        listeningModePresentationTask?.cancel()
        listeningModeLogObserver.stop()

        let darwinCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(darwinCenter, Unmanaged.passUnretained(self).toOpaque())
    }

    @MainActor
    func refreshConnectedDeviceBatteries() {
        requestStatusRefresh?()
    }

    @MainActor
    func activeDeviceIconSymbol() -> String? {
        if let prioritizedDevice = connectedDevices.last {
            return prioritizedDevice.deviceType.sfSymbol
        }
        return nil
    }
}

private final class AirPodsListeningModeLogObserver {
    var onModeChange: ((AirPodsListeningMode, String?) -> Void)?

    private var process: Process?
    private let queue = DispatchQueue(label: "com.dynamicisland.airpods-listening-log", qos: .utility)
    private var lineBuffer = ""

    func start() {
        guard process == nil else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--style",
            "compact",
            "--predicate",
            "(process == \"audioaccessoryd\" OR process == \"bluetoothd\" OR process == \"heard\") AND (eventMessage CONTAINS[c] \"LsnM\" OR eventMessage CONTAINS[c] \"noiseControlMode\" OR eventMessage CONTAINS[c] \"activeNoiseControlMode\" OR eventMessage CONTAINS[c] \"activeNoiseCancellationMode\")"
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.queue.async {
                self?.consume(text)
            }
        }

        do {
            try process.run()
            self.process = process
            print("🎧 [BluetoothAudioManager] AirPods listening mode log observer started")
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            print("🎧 [BluetoothAudioManager] AirPods listening mode log observer unavailable: \(error.localizedDescription)")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private func consume(_ text: String) {
        lineBuffer += text

        while let newlineRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[..<newlineRange.lowerBound])
            lineBuffer.removeSubrange(lineBuffer.startIndex...newlineRange.lowerBound)
            handle(line)
        }
    }

    private func handle(_ line: String) {
        guard Self.isModeChangeLine(line) else { return }
        guard let mode = AirPodsListeningMode.from(line) else { return }
        onModeChange?(mode, extractBluetoothAddress(from: line))
    }

    private static func isModeChangeLine(_ line: String) -> Bool {
        let value = line.lowercased()

        if value.contains("available") ||
           value.contains("supported") ||
           value.contains("capability") ||
           value.contains("capabilities") ||
           value.contains("listening modes") {
            return false
        }

        return value.contains("lsnm") ||
            value.contains("noisecontrolmode") ||
            value.contains("active noise control") ||
            value.contains("activeNoiseControlMode".lowercased()) ||
            value.contains("activeNoiseCancellationMode".lowercased())
    }

    private func extractBluetoothAddress(from line: String) -> String? {
        let pattern = #"[0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range, in: line) else {
            return nil
        }
        return String(line[range])
    }
}

// MARK: - HUD Models

struct BluetoothAudioDevice: Identifiable {
    let id: UUID
    let name: String
    let address: String
    let batteryLevel: Int?  // 0-100, nil if not available
    let deviceType: BluetoothAudioDeviceType

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        batteryLevel: Int?,
        deviceType: BluetoothAudioDeviceType
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.batteryLevel = batteryLevel
        self.deviceType = deviceType
    }
}

struct AirPodsListeningModeEvent: Identifiable {
    let id = UUID()
    let device: BluetoothAudioDevice
    let mode: AirPodsListeningMode
}

enum AirPodsListeningMode: Equatable {
    case noiseCancellation
    case transparency
    case adaptive
    case conversationAwareness
    case off

    var displayName: String {
        switch self {
        case .noiseCancellation:
            return String(localized: "Noise Cancellation")
        case .transparency:
            return String(localized: "Transparency")
        case .adaptive:
            return String(localized: "Adaptive Audio")
        case .conversationAwareness:
            return String(localized: "Conversation Awareness")
        case .off:
            return String(localized: "Off")
        }
    }

    var sfSymbol: String {
        switch self {
        case .noiseCancellation:
            return "ear.badge.waveform"
        case .transparency:
            return "ear"
        case .adaptive:
            return "waveform"
        case .conversationAwareness:
            return "person.wave.2"
        case .off:
            return "airpods.pro"
        }
    }

    static func fromHUDSymbol(_ symbol: String) -> AirPodsListeningMode? {
        switch symbol {
        case "ear.badge.waveform", "airpods.mode.noise-cancellation":
            return .noiseCancellation
        case "ear", "airpods.mode.transparency":
            return .transparency
        case "waveform", "airpods.mode.adaptive":
            return .adaptive
        case "person.wave.2", "airpods.mode.conversation-awareness":
            return .conversationAwareness
        case "airpods.pro", "airpods.mode.off":
            return .off
        default:
            return nil
        }
    }

    static func from(userInfo: [AnyHashable: Any]?) -> AirPodsListeningMode? {
        guard let userInfo else { return nil }

        let modeKeys = [
            "listeningMode",
            "ListeningMode",
            "noiseControlMode",
            "NoiseControlMode",
            "activeNoiseControlMode",
            "ANCMode",
            "ancMode",
            "adaptiveAudioMode",
            "AdaptiveAudioMode",
            "conversationAwareness",
            "ConversationAwareness",
            "conversationDetect",
            "ConversationDetect"
        ]

        for key in modeKeys {
            if let value = userInfo[key], let mode = from(value) {
                return mode
            }
        }

        return from(userInfo.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
    }

    static func from(_ value: Any) -> AirPodsListeningMode? {
        if let mode = value as? AirPodsListeningMode {
            return mode
        }

        if let number = value as? NSNumber {
            return fromPrivateValue(number.intValue)
        }

        if let string = value as? String {
            return from(string)
        }

        return from("\(value)")
    }

    static func fromPrivateValue(_ value: Int) -> AirPodsListeningMode? {
        switch value {
        case 0:
            return .off
        case 1:
            return .noiseCancellation
        case 2:
            return .transparency
        case 3:
            return .adaptive
        case 4:
            return .conversationAwareness
        default:
            return nil
        }
    }

    private static func from(_ rawValue: String) -> AirPodsListeningMode? {
        let value = rawValue.lowercased()

        if value.contains("lsnm anc") || value.contains("listeningmode anc") || value == "anc" {
            return .noiseCancellation
        }

        if value.contains("lsnm transparency") || value == "transparency" {
            return .transparency
        }

        if value.contains("lsnm autoanc") || value.contains("autoanc") {
            return .adaptive
        }

        if value.contains("lsnm normal") || value == "normal" {
            return .off
        }

        if value.contains("conversation") || value.contains("conversational") {
            return .conversationAwareness
        }

        if value.contains("adaptive") {
            return .adaptive
        }

        if value.contains("transparency") || value.contains("transparent") || value.contains("ambient") {
            return .transparency
        }

        if value.contains("noise cancellation") ||
           value.contains("noisecancellation") ||
           value.contains("noise cancelling") ||
           value.contains("noisecancelling") ||
           value.contains("anc") {
            return .noiseCancellation
        }

        if value.contains("listeningmode = 0") ||
           value.contains("listeningmode=0") ||
           value.contains("noisecontrolmode = 0") ||
           value.contains("noisecontrolmode=0") ||
           value.contains(" off") ||
           value.hasSuffix("off") {
            return .off
        }

        return nil
    }
}

extension BluetoothAudioDevice {
    func withBatteryLevel(_ batteryLevel: Int?) -> BluetoothAudioDevice {
        BluetoothAudioDevice(
            id: id,
            name: name,
            address: address,
            batteryLevel: batteryLevel,
            deviceType: deviceType
        )
    }
}

enum BluetoothAudioDeviceType {
    case airpods
    case airpodsGen3
    case airpodsGen4
    case airpodsPro
    case airpodsPro3
    case airpodsMax
    case beats
    case beatsstudio
    case beatssolo
    case headphones
    case speaker
    case generic

    var sfSymbol: String {
        switch self {
        case .airpods:
            return "airpods"
        case .airpodsGen3:
            return "airpods.gen3"
        case .airpodsGen4:
            return "airpods.gen4"
        case .airpodsPro:
            return "airpods.pro"
        case .airpodsPro3:
            return "airpods.pro"
        case .airpodsMax:
            return "airpodsmax"
        case .beats:
            return "beats.headphones"
        case .beatsstudio:
            return "beats.headphones"
        case .beatssolo:
            return "beats.headphones"
        case .headphones:
            return "headphones"
        case .speaker:
            return "hifispeaker.fill"
        case .generic:
            return "bluetooth.circle.fill"
        }
    }

    var displayName: String {
        switch self {
        case .airpods: return "AirPods"
        case .airpodsGen3: return "AirPods (Gen 3)"
        case .airpodsGen4: return "AirPods (Gen 4)"
        case .airpodsPro: return "AirPods Pro"
        case .airpodsPro3: return "AirPods Pro 3"
        case .airpodsMax: return "AirPods Max"
        case .beats: return "Beats"
        case .beatsstudio: return "Beats Studio"
        case .beatssolo: return "Beats Solo"
        case .headphones: return String(localized: "Headphones")
        case .speaker: return String(localized: "Speaker")
        case .generic: return String(localized: "Bluetooth Device")
        }
    }

    /// Inline HUD only: base filename (no extension) for a looping .mov animation.
    var inlineHUDAnimationBaseName: String {
        String(describing: self)
    }
}

extension BluetoothAudioDeviceType {
    /// Resolves the bundled looping HUD animation for this device type.
    ///
    /// Returns `nil` when the movie is missing *or* when the bundled file is not a real
    /// QuickTime/MP4 movie (for example an un-fetched Git LFS pointer, which is a small
    /// text file that ships with the correct name and extension but decodes to nothing).
    /// Callers can then fall back to the SF Symbol instead of rendering an empty frame.
    /// Memoised so the validation runs once per device type.
    ///
    /// This is read from `body` — `InlineHUD` evaluates it on every HUD render
    /// — and validation opens the file and walks its atom chain. Bundled
    /// resources cannot change while the app runs, so the answer is computed
    /// once and kept, including a negative answer.
    private static let animationURLCacheLock = NSLock()
    private static var animationURLCache: [BluetoothAudioDeviceType: URL?] = [:]

    var inlineHUDAnimationURL: URL? {
        BluetoothAudioDeviceType.animationURLCacheLock.lock()
        defer { BluetoothAudioDeviceType.animationURLCacheLock.unlock() }

        if let cached = BluetoothAudioDeviceType.animationURLCache[self] {
            return cached
        }

        let resolved = resolvedInlineHUDAnimationURL
        BluetoothAudioDeviceType.animationURLCache[self] = resolved
        return resolved
    }

    private var resolvedInlineHUDAnimationURL: URL? {
        // Each candidate is validated in turn: a stub in the subdirectory must
        // not mask a real movie sitting at the bundle root.
        let candidates = [
            Bundle.main.url(
                forResource: inlineHUDAnimationBaseName,
                withExtension: "mov",
                subdirectory: "BluetoothHUDAnimations"
            ),
            Bundle.main.url(
                forResource: inlineHUDAnimationBaseName,
                withExtension: "mov"
            )
        ].compactMap { $0 }

        return candidates.first { BluetoothAudioDeviceType.isPlayableMovieFile(at: $0) }
    }

    /// Atom types a QuickTime/ISO BMFF file may legitimately start with. Only
    /// the *first* atom is checked against this list — enough to reject a text
    /// file such as an un-fetched Git LFS pointer — because a valid container
    /// may carry all sorts of top-level atoms after it, and rejecting an
    /// unfamiliar one would silently disable a perfectly good animation.
    ///
    /// The padding and placeholder types (`free`, `skip`, `wide`, `pnot`) are
    /// included because real files do start with them: QuickTime writers emit
    /// `wide` before `mdat` to reserve room for a 64-bit size, and editors
    /// leave `free`/`skip` where data was removed. The assets here begin
    /// `ftyp` → `wide` → `mdat` → `moov`.
    private static let leadingAtomTypes: Set<String> = ["ftyp", "moov", "mdat", "free", "skip", "wide", "pnot"]

    /// Upper bound on the atom walk. These are small bundled assets, so a
    /// chain this long means the file is not what it claims; the bound stops a
    /// malformed one from being walked indefinitely.
    private static let maximumAtomCount = 128

    /// Walks the top-level atom chain and reports whether the file is a
    /// structurally complete movie.
    ///
    /// The chain must tile the file exactly and include a `moov`, which is
    /// where the playable metadata lives; in these assets it is the last atom,
    /// so the walk necessarily reaches EOF. This rejects both an un-fetched Git
    /// LFS pointer and a truncated or header-only file, either of which would
    /// otherwise reach the player and draw nothing.
    private static func isPlayableMovieFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        guard let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(UInt64.init),
              fileSize >= 8 else { return false }

        var offset: UInt64 = 0
        var sawMovieAtom = false
        var atomCount = 0

        while offset + 8 <= fileSize {
            atomCount += 1
            guard atomCount <= BluetoothAudioDeviceType.maximumAtomCount else { return false }

            guard (try? handle.seek(toOffset: offset)) != nil,
                  let header = try? handle.read(upToCount: 16),
                  header.count >= 8 else { return false }
            let bytes = [UInt8](header)

            // Atom types are four printable ISO 646 characters, so ASCII
            // decoding is exact rather than an assumption; anything that fails
            // to decode is not a container header.
            guard let atomType = String(bytes: bytes[4 ..< 8], encoding: .ascii),
                  atomType.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value <= 0x7E }) else { return false }
            if offset == 0, !leadingAtomTypes.contains(atomType) { return false }

            let declaredSize = bytes[0 ..< 4].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let extent: UInt64

            switch declaredSize {
            case 0:
                // The atom runs to the end of the file.
                extent = fileSize - offset
            case 1:
                // Extended size: the real length is the next 64 bits.
                guard bytes.count >= 16 else { return false }
                extent = bytes[8 ..< 16].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                guard extent >= 16 else { return false }
            case 2 ... 7:
                // Smaller than the header it must contain.
                return false
            default:
                extent = declaredSize
            }

            // Subtract rather than add: `extent` comes straight off the file
            // and can be UInt64.max, and `offset + extent` would trap before
            // the bound is ever tested. The loop condition keeps
            // `offset <= fileSize`, so this cannot underflow.
            guard extent >= 8, extent <= fileSize - offset else { return false }
            if atomType == "moov" { sawMovieAtom = true }
            offset += extent
        }

        // The chain has to account for the whole file, with the movie metadata
        // present — a header-only file tiles cleanly but cannot play.
        return sawMovieAtom && offset == fileSize
    }

    var isAirPods: Bool {
        switch self {
        case .airpods, .airpodsGen3, .airpodsGen4, .airpodsPro, .airpodsPro3, .airpodsMax:
            return true
        default:
            return false
        }
    }
}

// MARK: - Notification Name Constants

private let IOBluetoothDeviceConnectionNotification = "IOBluetoothDeviceConnectionNotification"
private let IOBluetoothDeviceDisconnectionNotification = "IOBluetoothDeviceDisconnectionNotification"
