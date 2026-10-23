import Foundation

/// Reserve the editable width range so dragging width does not rescale the preview.
enum AppearancePreviewGeometry {
    static func scale(stageWidth: CGFloat, referenceWidth: CGFloat) -> CGFloat {
        max(0, min(1, (stageWidth - 32) / max(1, referenceWidth)))
    }
}
