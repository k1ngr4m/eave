import SwiftUI

func musicPerimeterFraction(position: TimeInterval, duration: TimeInterval, isLiveStream: Bool) -> CGFloat? {
    guard !isLiveStream, duration.isFinite, duration > 0, position.isFinite else { return nil }
    return CGFloat(min(max(position / duration, 0), 1))
}

/// Opens the existing surface at its top edge, preserving its exact corner curves.
struct MusicPerimeterOutline: Shape {
    var surface: AnyShape
    var isPill: Bool

    func path(in rect: CGRect) -> Path {
        var perimeter = surface.path(in: rect)
        if isPill {
            // RoundedRectangle travels the opposite way to NotchShape.
            var reflection = CGAffineTransform(a: -1, b: 0, c: 0, d: 1,
                                               tx: rect.minX + rect.maxX, ty: 0)
            perimeter = Path(perimeter.cgPath.copy(using: &reflection)!)
        }
        var segments: [Path.Element] = []
        var current = CGPoint.zero
        var topEdge: Int?
        var start = CGPoint.zero
        perimeter.forEach { element in
            switch element {
            case .move(let point): current = point
            case .line(let point):
                if abs(current.y - rect.minY) < 0.0001, abs(point.y - rect.minY) < 0.0001,
                   current.x > point.x {
                    topEdge = segments.count
                    start = point
                }
                current = point
            case .quadCurve(let point, _): current = point
            case .curve(let point, _, _): current = point
            case .closeSubpath: return
            }
            segments.append(element)
        }
        guard let topEdge else { return Path() }

        // Start just after the top line and wrap around, omitting that line and the closing segment.
        var result = Path()
        result.move(to: start)
        for element in Array(segments.dropFirst(topEdge + 1)) + Array(segments.prefix(topEdge).dropFirst()) {
            switch element {
            case .line(let point): result.addLine(to: point)
            case .quadCurve(let point, let control): result.addQuadCurve(to: point, control: control)
            case .curve(let point, let control1, let control2):
                result.addCurve(to: point, control1: control1, control2: control2)
            case .move, .closeSubpath: break
            }
        }
        return result
    }
}
