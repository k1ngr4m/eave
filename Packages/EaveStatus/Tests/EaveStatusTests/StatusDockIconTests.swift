import AppKit
import Combine
import XCTest
@testable import EaveStatus

@MainActor
final class StatusDockIconTests: XCTestCase {
    func testDynamicDockUsesSharedSceneAndRestoresStaticIconWhenDisabled() throws {
        _ = NSApplication.shared
        let snapshots = CurrentValueSubject<StatusSnapshot, Never>(.placeholder)
        let preferences = CurrentValueSubject<IconPresentationSettings, Never>(settings(showsPercentage: true))
        let presentation = IconPresentationViewModel(
            snapshot: snapshots.value, settings: preferences.value,
            snapshots: snapshots.eraseToAnyPublisher(), preferences: preferences.eraseToAnyPublisher(),
            resolveInputs: { IconPresentationResourceResolver.inputs(snapshot: $0) }
        )
        presentation.start()
        defer { presentation.stop() }
        var rendered: [NSImage] = []
        var restored = 0
        let dock = StatusDockIconController(iconPresentation: presentation,
                                           restoreStaticIcon: { restored += 1 },
                                           applyIcon: { rendered.append($0) })
        dock.setEnabled(true)
        dock.setEnabled(true)
        XCTAssertEqual(rendered.count, 1)
        preferences.send(settings(showsPercentage: false))
        dock.flushPendingPresentationForTesting()
        XCTAssertEqual(rendered.count, 2)
        XCTAssertNotEqual(try pixels(rendered[0]).bytes, try pixels(rendered[1]).bytes)

        dock.setEnabled(false)
        dock.setEnabled(false)
        XCTAssertEqual(restored, 1)
        preferences.send(settings(showsPercentage: true))
        dock.flushPendingPresentationForTesting()
        XCTAssertEqual(rendered.count, 2, "Disabled Dock must not overwrite Eave's selected static icon")
        dock.setEnabled(true)
        XCTAssertEqual(rendered.count, 3)
        XCTAssertEqual(try pixels(rendered[0]).bytes, try pixels(rendered[2]).bytes)
        dock.stop()
        XCTAssertEqual(restored, 2)
    }

    func testDockRasterHasTransparentMarginAndChangesWithLiveStatus() throws {
        let first = IconPresentationMapper.scene(
            inputs: IconPresentationResourceResolver.inputs(snapshot: .placeholder), configuration: .standard
        )
        let changed = StatusSnapshot(
            battery: BatteryStatus(rawPercentage: 25, isPresent: true, isCharging: true,
                                   isLowPowerMode: false, isConnectedToPower: true),
            wifi: WiFiStatus(state: .connected, rssi: -50), connection: .wifi,
            volume: VolumeStatus(scalar: 0.75, isMuted: false, deviceName: "Speakers")
        )
        let second = IconPresentationMapper.scene(
            inputs: IconPresentationResourceResolver.inputs(snapshot: changed), configuration: .standard
        )
        let firstImage = try XCTUnwrap(DockIconRenderer.image(scene: first))
        let secondImage = try XCTUnwrap(DockIconRenderer.image(scene: second))
        let firstPixels = try pixels(firstImage)
        XCTAssertEqual(firstImage.size, NSSize(width: 256, height: 256))
        XCTAssertEqual(firstPixels.width, 512)
        XCTAssertEqual(firstPixels.rgba(x: 0, y: 0).alpha, 0)
        XCTAssertNotEqual(firstPixels.bytes, try pixels(secondImage).bytes)
        XCTAssertNil(DockIconRenderer.image(scene: first, pixelLength: 0))
        XCTAssertNil(DockIconRenderer.image(scene: first, pixelLength: 513))
    }

    func testSystemBackgroundResolvesLightDarkAndClear() {
        XCTAssertEqual(DockIconBackgroundResolver.style(for: .system,
            theme: SystemIconAppearanceTheme(style: .defaultStyle, appearance: .automatic),
            isDarkAppearance: true), .dark)
        XCTAssertEqual(DockIconBackgroundResolver.style(for: .system,
            theme: SystemIconAppearanceTheme(style: .defaultStyle, appearance: .automatic),
            isDarkAppearance: false), .light)
        XCTAssertEqual(DockIconBackgroundResolver.style(for: .system,
            theme: SystemIconAppearanceTheme(style: .clear, appearance: .dark),
            isDarkAppearance: true), .clear)
    }

    private func settings(showsPercentage: Bool) -> IconPresentationSettings {
        IconPresentationSettings(configuration: IconPresentationConfiguration(
            battery: BatteryIconOptions(showsPercentage: showsPercentage), connection: .standard,
            volume: .standard, bluetooth: .standard
        ), menuBarSize: 24, testsChargingEffect: false)
    }

    private func pixels(_ image: NSImage) throws -> PixelBuffer {
        let representation = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        return try PixelBuffer(image: XCTUnwrap(representation.cgImage))
    }
}
