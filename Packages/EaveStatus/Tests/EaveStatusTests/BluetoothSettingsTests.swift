import XCTest
@testable import EaveStatus

@MainActor
final class BluetoothSettingsTests: XCTestCase {
    func testSettingsPersistAndDeviceVisibilityDoesNotEraseOrder() {
        let suite = "EaveStatusTests.BluetoothSettings.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let keyboard = BluetoothDevice(id: "AA:BB:CC:DD:EE:01", name: "Keyboard", kind: .peripheral(.keyboard), isConnected: true)
        let mouse = BluetoothDevice(id: "AA:BB:CC:DD:EE:02", name: "Mouse", kind: .peripheral(.mouse), isConnected: true)

        settings.setPopupSection(.bluetooth, enabled: true)
        settings.bluetoothSymbolScale = 1.2
        settings.replacesNetworkIconWithBluetoothAudio = true
        settings.setBluetoothNetworkIconDevice(address: BluetoothBatteryReader.normalizedAddress(mouse.id), symbolName: "computermouse")
        settings.bluetoothAudioIconChoice = .headphones
        settings.usesBluetoothAudioVolumeColor = false
        settings.prioritizesNetworkErrorsOverBluetoothAudio = false
        settings.showsBluetoothBatteryLevels = false
        settings.showsBluetoothDeviceList = true
        settings.maxVisibleBluetoothDevices = 3
        settings.previewsBluetoothListeningMode = true
        settings.bluetoothListeningModePreviewDeviceName = "Preview AirPods"
        settings.bluetoothListeningModePreviewDeviceCount = 2
        settings.bluetoothListeningModePreviewLanguage = "zh-Hans"
        settings.moveBluetoothDevices(fromOffsets: IndexSet(integer: 1), toOffset: 0, in: [keyboard, mouse])
        settings.setBluetoothDeviceHidden(mouse.id, hidden: true)

        let saved = SettingsStore(defaults: defaults)
        XCTAssertTrue(saved.enabledPopupSections.contains(.bluetooth))
        XCTAssertEqual(saved.bluetoothSymbolScale, 1.2)
        XCTAssertTrue(saved.replacesNetworkIconWithBluetoothAudio)
        XCTAssertEqual(saved.bluetoothNetworkIconDeviceAddress, "AABBCCDDEE02")
        XCTAssertEqual(saved.bluetoothNetworkIconSymbolName, "computermouse")
        XCTAssertEqual(saved.bluetoothAudioIconChoice, .headphones)
        XCTAssertFalse(saved.usesBluetoothAudioVolumeColor)
        XCTAssertFalse(saved.prioritizesNetworkErrorsOverBluetoothAudio)
        XCTAssertFalse(saved.showsBluetoothBatteryLevels)
        XCTAssertTrue(saved.showsBluetoothDeviceList)
        XCTAssertEqual(saved.maxVisibleBluetoothDevices, 3)
        XCTAssertTrue(saved.previewsBluetoothListeningMode)
        XCTAssertEqual(saved.bluetoothListeningModePreviewDeviceName, "Preview AirPods")
        XCTAssertEqual(saved.bluetoothListeningModePreviewDeviceCount, 2)
        XCTAssertEqual(saved.bluetoothListeningModePreviewLanguage, "zh-Hans")
        XCTAssertEqual(saved.bluetoothDeviceOrder, ["AABBCCDDEE02", "AABBCCDDEE01"])
        XCTAssertTrue(saved.hiddenBluetoothDeviceAddresses.contains("AABBCCDDEE02"))
        let rows = BluetoothDeviceListPresentation.settingsDisplayRows(
            [keyboard, mouse], order: saved.bluetoothDeviceOrder, options: saved.bluetoothDeviceListOptions)
        XCTAssertEqual(rows.map(\.device.name), ["Mouse", "Keyboard"], "Hidden devices must remain available to reveal in settings")
        saved.setBluetoothDeviceHidden(mouse.id, hidden: false)
        XCTAssertTrue(saved.hiddenBluetoothDeviceAddresses.isEmpty)
        XCTAssertEqual(saved.bluetoothDeviceOrder, settings.bluetoothDeviceOrder)
    }
}
