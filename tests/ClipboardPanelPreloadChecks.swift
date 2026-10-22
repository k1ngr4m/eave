// Run with scripts/test-clipboard.sh. Uses a transparent window; does not read clipboard history.
import AppKit
import SwiftUI

@MainActor
final class AccessibilityPermissionStore {
    static let shared = AccessibilityPermissionStore()
    var isAuthorized = false
    func refreshStatus() {}
    func requestAuthorizationPrompt() {}
}

struct ClipboardPanelView: View {
    @MainActor static var taskStarted = false
    let controller: ClipboardPanelController
    let store: ClipboardHistoryStore
    var body: some View {
        Text("Preload check").frame(width: 400, height: 200)
            .task { Self.taskStarted = true }
    }
}

@main
struct ClipboardPanelPreloadChecks {
    @MainActor
    static func main() async throws {
        UserDefaults.standard.setVolatileDomain(["clipboardEnabled": true], forName: UserDefaults.argumentDomain)
        let app = NSApplication.shared
        let existing = Set(app.windows.map(ObjectIdentifier.init))
        let keyWindow = app.keyWindow
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let controller = ClipboardPanelController()
        controller.preload()
        for _ in 0..<50 where !ClipboardPanelView.taskStarted {
            try await Task.sleep(for: .milliseconds(10))
        }
        assert(ClipboardPanelView.taskStarted, "Preload must start SwiftUI resource tasks before showing")
        guard let panel = app.windows.first(where: { !existing.contains(ObjectIdentifier($0)) }) else {
            fatalError("Preload must create the panel")
        }
        let content = panel.contentView
        assert(content is NSHostingView<ClipboardPanelView>)
        assert(content!.frame.width > 0 && content!.frame.height > 0)
        assert(!panel.isVisible && !panel.isKeyWindow, "Preload must stay hidden")
        assert(!controller.isExpanded, "Preload must leave the reveal animation at its starting state")
        assert(app.keyWindow === keyWindow)
        assert(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost)
        controller.preload()
        controller.dismiss(restoreTarget: false)
        controller.preload()
        assert(panel.contentView === content, "Dismiss/preload must reuse the warm hosting view")
        assert(app.windows.filter { !existing.contains(ObjectIdentifier($0)) }.count == 1)
        assert(!panel.isVisible)
        assert(!controller.isExpanded, "Dismiss must reset the reveal for the next opening")
        panel.alphaValue = 0
        panel.orderFront(nil)
        controller.dismiss(restoreTarget: false)
        assert(panel.isVisible && controller.isDismissing, "Keep the panel around for its closing animation")
        assert(panel.ignoresMouseEvents && !panel.isKeyWindow, "Release interaction before the animation finishes")
        let dismissal = controller.presentation
        controller.dismiss(restoreTarget: false)
        assert(controller.presentation == dismissal, "Repeated dismissal must not invalidate pending teardown")
        try await Task.sleep(for: .milliseconds(650))
        assert(!panel.isVisible && !controller.isDismissing, "Hide after the closing animation")
        assert(panel.contentView === content, "Closing must retain the preloaded view")
        panel.orderFront(nil)
        controller.dismiss(restoreTarget: false)
        controller.toggle()
        panel.alphaValue = 0
        try await Task.sleep(for: .milliseconds(650))
        assert(panel.isVisible && controller.isExpanded && !controller.isDismissing,
               "An old close completion must not hide a reopened panel")
        assert(!panel.ignoresMouseEvents, "Reopening must restore interaction")
        controller.dismiss()
        try await Task.sleep(for: .milliseconds(650))
        assert(!panel.isVisible)
        print("Clipboard preload checks passed: hidden layout, no focus change, idempotence and view reuse.")
    }
}
