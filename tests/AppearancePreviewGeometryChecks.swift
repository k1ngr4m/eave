// Run: swiftc DynamicIsland/components/Settings/AppearancePreviewGeometry.swift tests/AppearancePreviewGeometryChecks.swift -o /tmp/eave-preview-checks && /tmp/eave-preview-checks
import Foundation

@main
struct AppearancePreviewGeometryChecks {
    static func main() {
        let scale = AppearancePreviewGeometry.scale(stageWidth: 700, referenceWidth: 900)
        precondition(scale > 0.7 && scale <= 1) // Readable without scaling to the entire display.
        precondition(900 * scale > 640 * scale) // Width changes remain visible.
        precondition(900 * scale <= 700 - 32)
        precondition(AppearancePreviewGeometry.scale(stageWidth: 0, referenceWidth: 900) == 0)
        precondition(AppearancePreviewGeometry.scale(stageWidth: 2000, referenceWidth: 900) == 1)
        precondition(1200 * AppearancePreviewGeometry.scale(stageWidth: 700, referenceWidth: 1200) <= 668)
        print("PASS: readable fixed preview scale, width changes and wide lyrics fitting")
    }
}
