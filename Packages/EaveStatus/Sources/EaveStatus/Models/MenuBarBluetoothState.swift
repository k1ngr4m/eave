import Combine
import Foundation

/// The menu panel and Eave's connection HUD consume the same paired-device reading.
public struct MenuBarBluetoothDevice: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let isAudio: Bool
    public let isConnected: Bool
    public let vendorID: Int?
    public let productID: Int?
    public let batteryMain: Int?
    public let batteryLeft: Int?
    public let batteryRight: Int?
    public let batteryCase: Int?

    /// Matches Eave's existing single-number HUD; the panel keeps each channel.
    public var batteryPercentage: Int? {
        [batteryMain, batteryLeft, batteryRight, batteryCase].compactMap { $0 }.max()
    }

    init(device: BluetoothDevice, battery: BluetoothBatteryLevel?) {
        id = BluetoothBatteryReader.normalizedAddress(device.id)
        name = device.name
        isAudio = device.kind.isAudio || device.airPodsModel != nil
        isConnected = device.isConnected
        vendorID = device.vendorID
        productID = device.productID
        batteryMain = battery?.main
        batteryLeft = battery?.left
        batteryRight = battery?.right
        batteryCase = battery?.caseLevel
    }
}

public struct MenuBarBluetoothState: Equatable, Sendable {
    public let devices: [MenuBarBluetoothDevice]
    /// A pending or failed read must not look like every device disconnected.
    public let isAuthoritative: Bool

    init(devices: [BluetoothDevice], batteryLevels: [String: BluetoothBatteryLevel],
         availability: BluetoothAvailability, hasReadDevices: Bool) {
        switch availability {
        case .available:
            isAuthoritative = hasReadDevices
            self.devices = devices.map {
                MenuBarBluetoothDevice(device: $0, battery: batteryLevels[BluetoothBatteryReader.normalizedAddress($0.id)])
            }
        case .poweredOff, .authorizationDenied, .authorizationRestricted, .unavailable:
            isAuthoritative = true
            self.devices = []
        case .idle, .initializing, .authorizationNotDetermined, .failed:
            isAuthoritative = false
            self.devices = []
        }
    }
}

extension BluetoothDeviceController {
    var hostStatusPublisher: AnyPublisher<MenuBarBluetoothState, Never> {
        Publishers.CombineLatest4($devices, $batteryLevels, $availability, $hasReadDevices)
            .map { MenuBarBluetoothState(devices: $0, batteryLevels: $1, availability: $2, hasReadDevices: $3) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
