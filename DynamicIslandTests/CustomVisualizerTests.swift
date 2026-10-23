import XCTest
import SwiftUI
import Defaults
import Lottie
@testable import Eave

final class CustomVisualizerTests: XCTestCase {
    func testValidationTrimsInputAndAcceptsSpeedBoundaries() throws {
        for speed in [CGFloat(0.1), 1, 2] {
            let visualizer = try CustomVisualizer.validated(
                name: " \nMy animation\t ", url: " \nhttps://example.com/animation.json?version=2\t ", speed: speed)
            XCTAssertEqual(visualizer.name, "My animation")
            XCTAssertEqual(visualizer.url.absoluteString, "https://example.com/animation.json?version=2")
            XCTAssertEqual(visualizer.speed, speed)
        }
        XCTAssertNoThrow(try CustomVisualizer.validated(name: "Local", url: "http://localhost:8000/animation.json", speed: 1))
    }

    func testValidationRejectsEmptyNamesInvalidURLsAndInvalidSpeeds() {
        for name in ["", " \n\t "] {
            XCTAssertThrowsError(try CustomVisualizer.validated(name: name, url: "https://example.com/a.json", speed: 1))
        }
        for url in ["", " \n ", "animation.json", "//example.com/a.json", "file:///tmp/a.json",
                    "ftp://example.com/a.json", "https:///", "https://user@example.com/a.json",
                    "https://user:password@example.com/a.json", "https://:password@example.com/a.json"] {
            XCTAssertThrowsError(try CustomVisualizer.validated(name: "Animation", url: url, speed: 1), url)
        }
        for speed in [CGFloat.zero, -1, 0.099, 2.001, .nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try CustomVisualizer.validated(name: "Animation", url: "https://example.com/a.json", speed: speed))
        }
    }

    func testSelectionUsesLatestObjectAndFallsBackAfterDeletion() throws {
        let first = try CustomVisualizer.validated(name: "First", url: "https://example.com/first.json", speed: 1)
        let second = try CustomVisualizer.validated(name: "Second", url: "https://example.com/second.json", speed: 1)
        var updated = second
        updated.name = "Renamed"
        updated.speed = 2
        XCTAssertEqual(CustomVisualizer.resolvedSelection(second, in: [first, updated]), updated)
        XCTAssertEqual(CustomVisualizer.resolvedSelection(nil, in: [first, updated]), first)
        XCTAssertEqual(CustomVisualizer.resolvedSelection(second, in: [first]), first)
        XCTAssertNil(CustomVisualizer.resolvedSelection(first, in: []))
        XCTAssertNil(CustomVisualizer.resolvedSelection(nil, in: []))
    }

    func testExistingPersistedSelectionDecodesAndRoundTrips() throws {
        let data = Data("""
            {"UUID":"D9AECF34-01CD-4D83-B329-F0DC9B859D31","name":"Saved animation",\
            "url":"https://example.com/saved.json","speed":0.5}
            """.utf8)
        let saved = try JSONDecoder().decode(CustomVisualizer.self, from: data)
        XCTAssertEqual(saved.UUID.uuidString, "D9AECF34-01CD-4D83-B329-F0DC9B859D31")
        XCTAssertEqual(saved.name, "Saved animation")
        XCTAssertEqual(saved.url.absoluteString, "https://example.com/saved.json")
        XCTAssertEqual(saved.speed, 0.5)
        XCTAssertEqual(try JSONDecoder().decode(CustomVisualizer.self, from: JSONEncoder().encode(saved)), saved)

        var current = saved
        current.url = URL(string: "https://example.com/replacement.json")!
        current.speed = 1.5
        XCTAssertEqual(CustomVisualizer.resolvedSelection(saved, in: [current]), current)
    }

    @MainActor
    func testRenderedAnimationSwitchesAndTracksPlaybackAndSpeed() async throws {
        let saved = (Defaults[.customVisualizers], Defaults[.selectedVisualizer], LottieAnimationCache.shared)
        let cache = DefaultAnimationCache()
        LottieAnimationCache.shared = cache
        defer {
            Defaults[.customVisualizers] = saved.0
            Defaults[.selectedVisualizer] = saved.1
            cache.clearCache()
            LottieAnimationCache.shared = saved.2
        }

        func animation(color: String) throws -> Lottie.LottieAnimation {
            try Lottie.LottieAnimation.from(data: Data("""
                {"v":"5.7.4","fr":30,"ip":0,"op":60,"w":32,"h":32,"layers":[
                  {"ty":1,"ind":1,"nm":"Square","sr":1,"sw":32,"sh":32,"sc":"\(color)",
                   "ks":{"o":{"a":0,"k":100},"r":{"a":0,"k":0},"p":{"a":0,"k":[0,0,0]},
                         "a":{"a":0,"k":[0,0,0]},"s":{"a":0,"k":[100,100,100]}},
                   "ip":0,"op":60,"st":0,"bm":0}]
                }
                """.utf8))
        }
        let first = try CustomVisualizer.validated(name: "First", url: "https://visualizer-tests.invalid/first.json", speed: 0.5)
        var second = try CustomVisualizer.validated(name: "Second", url: "https://visualizer-tests.invalid/second.json", speed: 1.5)
        let firstAnimation = try animation(color: "#FF0000")
        let secondAnimation = try animation(color: "#0000FF")
        cache.setAnimation(firstAnimation, forKey: first.url.absoluteString)
        cache.setAnimation(secondAnimation, forKey: second.url.absoluteString)
        Defaults[.customVisualizers] = [first, second]
        Defaults[.selectedVisualizer] = first

        let host = NSHostingView(rootView: Eave.LottieAnimationView(isPlaying: true))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 64, height: 64),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }

        func rendered(in view: NSView) -> Lottie.LottieAnimationView? {
            if let animation = view as? Lottie.LottieAnimationView { return animation }
            return view.subviews.lazy.compactMap { rendered(in: $0) }.first
        }
        func waitFor(_ expected: Lottie.LottieAnimation, speed: CGFloat, playing: Bool) async throws -> Bool {
            for _ in 0..<60 {
                host.layoutSubtreeIfNeeded()
                if let view = rendered(in: host), view.animation === expected,
                   view.animationSpeed == speed, view.isAnimationPlaying == playing {
                    return true
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            return false
        }

        var matches = try await waitFor(firstAnimation, speed: 0.5, playing: true)
        XCTAssertTrue(matches, "The first cached animation must render and play.")
        Defaults[.selectedVisualizer] = second
        matches = try await waitFor(secondAnimation, speed: 1.5, playing: true)
        XCTAssertTrue(matches, "Changing the selection must replace the rendered Lottie animation.")

        second.speed = 2
        Defaults[.customVisualizers] = [first, second]
        matches = try await waitFor(secondAnimation, speed: 2, playing: true)
        XCTAssertTrue(matches, "Changing the selected animation's speed must update its existing view.")
        host.rootView = Eave.LottieAnimationView(isPlaying: false)
        matches = try await waitFor(secondAnimation, speed: 2, playing: false)
        XCTAssertTrue(matches, "Pausing music must pause the Lottie animation.")
        host.rootView = Eave.LottieAnimationView(isPlaying: true)
        matches = try await waitFor(secondAnimation, speed: 2, playing: true)
        XCTAssertTrue(matches, "Resuming music must resume the Lottie animation.")

        second.speed = 0
        Defaults[.customVisualizers] = [first, second]
        matches = try await waitFor(secondAnimation, speed: 1, playing: true)
        XCTAssertTrue(matches, "A zero speed saved by older versions must recover to normal playback.")
    }
}
