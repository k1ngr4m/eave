import XCTest
@testable import Eave

final class MediaSettingsPreviewTests: XCTestCase {
    @MainActor
    func testPreviewDoesNotInstallRealWindowObserversOrSelectTabs() {
        let selected = DynamicIslandViewCoordinator.shared.currentView
        let vm = DynamicIslandViewModel(settingsPreview: true)
        XCTAssertEqual(vm.notchState, .open)
        XCTAssertTrue(vm.cancellables.isEmpty)
        XCTAssertNil(vm.onViewTeardown)
        XCTAssertEqual(DynamicIslandViewCoordinator.shared.currentView, selected)
    }

    @MainActor
    func testPlayerFitsNarrowAndWideSettingsWithoutUpscaling() {
        for content in [CGSize(width: 440, height: 200), CGSize(width: 1000, height: 200), CGSize(width: 420, height: 280)] {
            for stage in [CGSize(width: 200, height: 200), CGSize(width: 900, height: 200)] {
                let scale = MediaSettingsPreview.scale(content: content, stage: stage)
                XCTAssertGreaterThan(scale, 0)
                XCTAssertLessThanOrEqual(scale, 1)
                XCTAssertLessThanOrEqual(content.width * scale, stage.width - 32 + 0.001)
                XCTAssertLessThanOrEqual(content.height * scale, stage.height - 24 + 0.001)
            }
        }
        XCTAssertEqual(MediaSettingsPreview.scale(content: .zero, stage: .zero), 1)
        XCTAssertEqual(MediaSettingsPreview.scale(content: CGSize(width: 440, height: 200), stage: .zero), 0)
    }
}
