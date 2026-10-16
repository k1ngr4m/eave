// Run from the repository root:
// swiftc DynamicIsland/components/Notch/{NotchShape,DynamicIslandPillShape}.swift DynamicIsland/components/Music/MusicPerimeterOutline.swift tests/test_music_perimeter.swift -o /tmp/test-music-perimeter && /tmp/test-music-perimeter
import SwiftUI

@main
struct MusicPerimeterChecks {
    static func main() {
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            assert(musicPerimeterFraction(position: fraction * 200, duration: 200, isLiveStream: false) == fraction)
        }
        assert(musicPerimeterFraction(position: -10, duration: 200, isLiveStream: false) == 0)
        assert(musicPerimeterFraction(position: 300, duration: 200, isLiveStream: false) == 1)
        for duration in [0.0, -1, .infinity, .nan] {
            assert(musicPerimeterFraction(position: 10, duration: duration, isLiveStream: false) == nil)
        }
        assert(musicPerimeterFraction(position: 10, duration: 200, isLiveStream: true) == nil)
        assert(musicPerimeterFraction(position: .nan, duration: 200, isLiveStream: false) == nil)
        assert(musicPerimeterFraction(position: .infinity, duration: 200, isLiveStream: false) == nil)

        for isPill in [false, true] {
            for size in [CGSize(width: 200, height: 32), CGSize(width: 640, height: 160),
                         CGSize(width: 648, height: 168)] {
                let rect = CGRect(origin: CGPoint(x: 10, y: 5), size: size)
                let surface = isPill
                    ? AnyShape(DynamicIslandPillShape(cornerRadius: 20))
                    : AnyShape(NotchShape(topCornerRadius: 6, bottomCornerRadius: 14))
                let path = MusicPerimeterOutline(surface: surface, isPill: isPill).path(in: rect)
                assert(!path.isEmpty, "Empty outline: pill=\(isPill), size=\(size), surface=\(surface.path(in: rect))")
                var moves = 0
                var start = CGPoint.zero
                path.forEach { element in
                    if case .move(let point) = element { moves += 1; start = point }
                    if case .closeSubpath = element { assertionFailure("Progress must remain open") }
                }
                assert(moves == 1, "Corner joins must remain continuous")
                let end = path.currentPoint!
                assert(start.x < rect.midX && end.x > rect.midX)
                assert(abs(start.y - rect.minY) < 0.01 && abs(end.y - rect.minY) < 0.01)
                assert(abs(start.x + end.x - 2 * rect.midX) < 0.01)
                let midpoint = path.trimmedPath(from: 0, to: 0.5).currentPoint!
                assert(abs(midpoint.x - rect.midX) < 0.5 && abs(midpoint.y - rect.maxY) < 0.5,
                       "50% must reach the bottom center: \(midpoint)")
                let quarter = path.trimmedPath(from: 0, to: 0.25).currentPoint!
                let threeQuarters = path.trimmedPath(from: 0, to: 0.75).currentPoint!
                assert(abs(quarter.x + threeQuarters.x - 2 * rect.midX) < 0.5)
                assert(abs(quarter.y - threeQuarters.y) < 0.5)
            }
        }
        print("Music perimeter checks passed")
    }
}
