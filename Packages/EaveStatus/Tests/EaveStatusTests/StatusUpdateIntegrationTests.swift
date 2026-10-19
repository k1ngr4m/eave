import AppKit
import Combine
import XCTest
@testable import EaveStatus

@MainActor
final class StatusUpdateIntegrationTests: XCTestCase {
    func testFullThresholdPersistsAndChangesBothIconSurfacesWithoutChangingPercentage() throws {
        let suite = "EaveStatusTests.FullThreshold.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let snapshot = StatusSnapshot(
            battery: BatteryStatus(rawPercentage: 80, isPresent: true, isCharging: false,
                                   isLowPowerMode: false, isConnectedToPower: false),
            wifi: WiFiStatus(state: .connected, rssi: -50), connection: .wifi, volume: .placeholder
        )
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(snapshot)
        let presentation = IconPresentationViewModel(
            snapshot: snapshot,
            settings: IconPresentationSettings(configuration: .standard, menuBarSize: 24, testsChargingEffect: false),
            snapshots: snapshots.eraseToAnyPublisher(), preferences: settings.iconPresentationPublisher,
            resolveInputs: { IconPresentationResourceResolver.inputs(snapshot: $0) }
        )
        presentation.start()
        defer { presentation.stop() }
        var dockImages: [NSImage] = []
        let dock = StatusDockIconController(iconPresentation: presentation, restoreStaticIcon: {},
                                           applyIcon: { dockImages.append($0) })
        dock.setEnabled(true)
        defer { dock.stop() }
        let before = try XCTUnwrap(StatusIconRenderer.image(scene: presentation.output.scene, size: 24, scale: 2))
        XCTAssertEqual(presentation.output.scene.outerRing?.segments.first?.progress, 0.8)
        settings.batteryFullThreshold = 80
        dock.flushPendingPresentationForTesting()
        let after = try XCTUnwrap(StatusIconRenderer.image(scene: presentation.output.scene, size: 24, scale: 2))
        XCTAssertEqual(presentation.output.scene.outerRing?.segments.first?.progress, 1)
        XCTAssertEqual(dockImages.count, 2)
        XCTAssertNotEqual(before.tiffRepresentation, after.tiffRepresentation)
        XCTAssertNotEqual(dockImages[0].tiffRepresentation, dockImages[1].tiffRepresentation)
        XCTAssertEqual(snapshot.battery.percentage, 80)
        if case let .text(text) = presentation.output.scene.outerRing?.accessory {
            XCTAssertEqual(text.text, "80")
        } else {
            XCTFail("The ring must retain its actual battery percentage")
        }
        XCTAssertEqual(SettingsStore(defaults: defaults).batteryFullThreshold, 80)
        settings.batteryFullThreshold = .nan
        XCTAssertEqual(settings.batteryFullThreshold, 100)
        settings.batteryFullThreshold = 0
        XCTAssertEqual(settings.batteryFullThreshold, 50)
    }

    func testInputSourceUpdatesTheSharedSceneAndDockImmediately() throws {
        let sources = CurrentValueSubject<InputSourceDescriptor?, Never>(nil)
        let config = IconPresentationConfiguration(battery: .standard,
            connection: ConnectionIconOptions(centerSource: .inputSource, prioritizesNetworkErrorsOverInputSource: false),
            volume: .standard, bluetooth: .standard)
        let preferences = IconPresentationSettings(configuration: config, menuBarSize: 24, testsChargingEffect: false)
        let presentation = IconPresentationViewModel(snapshot: .placeholder, settings: preferences,
            snapshots: Just(StatusSnapshot.placeholder).eraseToAnyPublisher(),
            preferences: Just(preferences).eraseToAnyPublisher(), inputSources: sources.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationResourceResolver.inputs(snapshot: $0) })
        presentation.start()
        defer { presentation.stop() }
        var images: [NSImage] = []
        let dock = StatusDockIconController(iconPresentation: presentation, restoreStaticIcon: {},
                                           applyIcon: { images.append($0) })
        dock.setEnabled(true)
        defer { dock.stop() }
        let state = InputSourceState.resolved(selectedID: "test.pinyin", rawSources: [
            RawInputSource(id: "test.pinyin", localizedName: "拼音", languages: ["zh-Hans"],
                           iconImageURL: nil, isEnabled: true, isSelectCapable: true)
        ])
        sources.send(state.selectedDescriptor)
        dock.flushPendingPresentationForTesting()
        guard case let .text(text) = presentation.output.scene.center else { return XCTFail("Missing input-source label") }
        XCTAssertEqual(text.text, state.selectedDescriptor?.shortLabel)
        XCTAssertEqual(images.count, 2)
        XCTAssertNotEqual(images[0].tiffRepresentation, images[1].tiffRepresentation)
    }

    func testLocalIPIsPresentedOnWiFiAndEthernetAndSharingTargetsItsOwnPane() throws {
        let suite = "EaveStatusTests.Network.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let localization = Localization(defaults: defaults, preferredLanguages: ["en"])
        for connection in [NetworkConnection.wifi, .ethernet] {
            let row = PanelPresentationMapper.network(wifi: WiFiStatus(state: .connected, rssi: -50),
                connection: connection, wired: nil, isConstrained: false, isResolvingName: false,
                localIPAddress: "192.168.1.28", localization: localization)
            XCTAssertTrue(row.subtitle.hasPrefix("192.168.1.28"))
            XCTAssertTrue(row.accessibilityValue.contains("192.168.1.28"))
        }
        XCTAssertEqual(StatusBarController.sharingSettingsURLs.first?.absoluteString,
                       "x-apple.systempreferences:com.apple.Sharing-Settings.extension")
        XCTAssertEqual(StatusBarController.keyboardSettingsURLs.first?.absoluteString,
                       "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }
}
