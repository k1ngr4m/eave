import XCTest
import Defaults
@testable import Eave

final class MediaSettingsPreviewTests: XCTestCase {
    @MainActor
    func testPageSizesKeepLyricsOnMediaAndMirrorOnHome() {
        let saved = (Defaults[.enableMinimalisticUI], Defaults[.showStandardMediaControls],
                     Defaults[.enableLyrics], Defaults[.autoHideInactiveNotchMediaPlayer],
                     Defaults[.lyricsPanelWidth], Defaults[.lyricsPanelOffset], Defaults[.showMirror])
        defer {
            Defaults[.enableMinimalisticUI] = saved.0
            Defaults[.showStandardMediaControls] = saved.1
            Defaults[.enableLyrics] = saved.2
            Defaults[.autoHideInactiveNotchMediaPlayer] = saved.3
            Defaults[.lyricsPanelWidth] = saved.4
            Defaults[.lyricsPanelOffset] = saved.5
            Defaults[.showMirror] = saved.6
        }
        Defaults[.enableMinimalisticUI] = false
        Defaults[.showStandardMediaControls] = true
        Defaults[.autoHideInactiveNotchMediaPlayer] = false
        Defaults[.enableLyrics] = false
        let home = baseOpenNotchSize(for: .home, screen: nil)
        XCTAssertEqual(baseOpenNotchSize(for: .media, screen: nil), home)

        Defaults[.enableLyrics] = true
        Defaults[.lyricsPanelWidth] = 600
        Defaults[.lyricsPanelOffset] = -25
        Defaults[.showMirror] = false
        let media = baseOpenNotchSize(for: .media, screen: nil)
        XCTAssertEqual(sideLyricsRequiredNotchWidth(), 1065)
        XCTAssertEqual(media.height, 200)
        XCTAssertEqual(media.width, min(max(home.width, 1065), maxAllowedNotchWidth()))
        Defaults[.showMirror] = true
        XCTAssertEqual(sideLyricsRequiredNotchWidth(), 1065)
        XCTAssertEqual(baseOpenNotchSize(for: .media, screen: nil), media)
        XCTAssertEqual(baseOpenNotchSize(for: .home, screen: nil), home)
        XCTAssertEqual(getOpenNotchSize(screen: nil), home)

        for pill in [false, true] {
            let homeBase = minimalisticBaseOpenNotchSize(for: .home, isDynamicIslandMode: pill, includesLyrics: false)
            XCTAssertEqual(homeBase, CGSize(width: pill ? 340 : 420, height: pill ? 144 : 180))
            XCTAssertEqual(minimalisticBaseOpenNotchSize(for: .home, isDynamicIslandMode: pill, includesLyrics: true), homeBase)
            let mediaBase = minimalisticBaseOpenNotchSize(for: .media, isDynamicIslandMode: pill, includesLyrics: false)
            XCTAssertEqual(mediaBase, CGSize(width: pill ? 340 : 420, height: pill ? 186 : 204))
            XCTAssertEqual(minimalisticBaseOpenNotchSize(for: .media, isDynamicIslandMode: pill, includesLyrics: true).height,
                           mediaBase.height + 50)
            XCTAssertEqual(minimalisticOpenNotchSize(for: .media, isDynamicIslandMode: pill),
                           minimalisticBaseOpenNotchSize(for: .media, isDynamicIslandMode: pill,
                                                       includesLyrics: !MusicManager.shared.isAdvertisement))
        }
    }

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
