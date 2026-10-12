import XCTest
import AppKit

@testable import Eave

final class MenuBarStatusTests: XCTestCase {
    @MainActor
    func testClosingSettingsKeepsDynamicDockAndDisablingRestoresAccessory() {
        var policies: [NSApplication.ActivationPolicy] = []
        let policy = DockActivationPolicy(apply: { policies.append($0) })
        policy.setDynamicDockEnabled(true)
        policy.setWindowVisible(true, id: "settings")
        policy.setWindowVisible(false, id: "settings")
        XCTAssertEqual(policies.last, .regular)
        policy.setDynamicDockEnabled(false)
        XCTAssertEqual(policies.last, .accessory)

        policy.setWindowVisible(true, id: "settings")
        policy.setWindowVisible(true, id: "cameraPermission")
        policy.setWindowVisible(false, id: "cameraPermission")
        XCTAssertEqual(policies.last, .regular)
        policy.setDynamicDockEnabled(true)
        policy.setDynamicDockEnabled(false)
        XCTAssertEqual(policies.last, .regular)
        policy.setWindowVisible(false, id: "settings")
        XCTAssertEqual(policies.last, .accessory)
    }

    @MainActor
    func testBatterySnapshotUsesCapacityRatioAndPreservesPowerState() {
        let state = MenuBarStatusManager.batteryState(from: BatteryInfo(
            isPluggedIn: true,
            isCharging: true,
            currentCapacity: 45,
            maxCapacity: 60,
            isInLowPowerMode: true,
            timeToFullCharge: 30
        ))
        XCTAssertEqual(state.rawPercentage, 75)
        XCTAssertTrue(state.isPresent)
        XCTAssertTrue(state.isCharging)
        XCTAssertFalse(state.isCharged)
        XCTAssertTrue(state.isConnectedToPower)
        XCTAssertTrue(state.isLowPowerMode)
        XCTAssertEqual(state.timeToFullChargeMinutes, 30)
    }

    @MainActor
    func testDesktopHasNoBatteryAndUnknownETAStaysUnknown() {
        let state = MenuBarStatusManager.batteryState(from: BatteryInfo(
            isPluggedIn: false,
            isCharging: false,
            currentCapacity: 0,
            maxCapacity: 0,
            isInLowPowerMode: false,
            timeToFullCharge: -1
        ))
        XCTAssertNil(state.rawPercentage)
        XCTAssertFalse(state.isPresent)
        XCTAssertFalse(state.isCharged)
        XCTAssertNil(state.timeToFullChargeMinutes)
    }
}

extension MenuBarStatusTests {
    @MainActor
    func testDirectDisplayFlyoutUsesReadbackAndDisablesUnavailableControls() {
        let controller = SystemVolumeController.shared
        let deviceID = controller.directDisplayRoute().id
        var writes: [Float] = []
        var mutes: [Bool] = []
        func inject(_ scalar: Float?) {
            controller.updateDirectDisplayVolume(deviceID: deviceID, scalar: scalar, canMute: scalar != nil,
                                                 setVolume: { writes.append($0) }, adjust: { _ in },
                                                 setMuted: { mutes.append($0) })
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }
        defer {
            controller.updateDirectDisplayVolume(deviceID: nil, scalar: nil, setVolume: { _ in },
                                                 adjust: { _ in }, setMuted: { _ in })
        }
        inject(0.4)
        let model = MediaOutputVolumeViewModel(controller: controller)
        model.setVolume(0.8)
        XCTAssertEqual(writes, [0.8])
        XCTAssertEqual(model.level, 0.4, "A queued DDC command is not a confirmed level")
        model.toggleMute()
        XCTAssertEqual(mutes, [true])
        XCTAssertFalse(model.isMuted, "A queued mute is not a confirmed mute")

        inject(nil)
        XCTAssertFalse(model.canSetVolume)
        XCTAssertFalse(model.canMute)
        model.setVolume(0.9)
        model.toggleMute()
        XCTAssertEqual(writes, [0.8])
        XCTAssertEqual(mutes, [true])
        inject(0.6)
        XCTAssertTrue(model.canSetVolume)
        XCTAssertTrue(model.canMute)
        XCTAssertEqual(model.level, 0.6)
        inject(0)
        XCTAssertTrue(model.isMuted)
    }
}
