// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ApplicationServices
import SwiftUI

private final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ClipboardPanelController: ObservableObject {
    static let shared = ClipboardPanelController()
    @Published var query = ""
    @Published var collectionID: UUID?
    @Published var favoritesOnly = false
    @Published var sourceID = ""
    @Published var selectedID: UUID?
    @Published var settingsPresented = false
    @Published var collectionPresented = false
    @Published private(set) var pasting = false
    @Published private(set) var presentation = UUID()
    private var panel: NSPanel?
    private var targetApplication: NSRunningApplication?
    private var targetWindow: AXUIElement?
    private var targetInput: AXUIElement?
    private var localMonitor: Any?
    private var outsideMonitor: Any?

    var visibleEntries: [ClipboardEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return ClipboardHistoryStore.shared.history.entries.filter {
            (!favoritesOnly || $0.isFavorite) &&
            (collectionID == nil || $0.collectionIDs.contains(collectionID!)) &&
            (sourceID.isEmpty || $0.sourceBundleID == sourceID) &&
            (query.isEmpty || $0.text.localizedStandardContains(query) || $0.sourceName.localizedStandardContains(query))
        }
    }

    func toggle() {
        guard ClipboardHistoryStore.shared.enabled else { return }
        if panel?.isVisible == true { dismiss(); return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        targetApplication = NSWorkspace.shared.frontmostApplication
        targetWindow = nil
        targetInput = nil
        if let targetApplication, AXIsProcessTrusted() {
            let app = AXUIElementCreateApplication(targetApplication.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.2)
            targetWindow = Self.element(kAXFocusedWindowAttribute, of: app)
            targetInput = Self.element(kAXFocusedUIElementAttribute, of: app)
        }
        query = ""
        sourceID = ""
        favoritesOnly = false
        collectionID = nil
        settingsPresented = false
        collectionPresented = false
        selectedID = ClipboardHistoryStore.shared.history.entries.first?.id
        presentation = UUID()
        let frame = Self.frame(in: screen.frame)
        let panel = self.panel ?? ClipboardPanel(contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: ClipboardPanelView(controller: self, store: .shared))
        self.panel = panel
        panel.setFrame(frame.offsetBy(dx: 0, dy: -24), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
        installMonitors()
    }

    static func frame(in screenFrame: NSRect) -> NSRect {
        NSRect(x: screenFrame.minX + 12, y: screenFrame.minY,
               width: max(240, screenFrame.width - 24), height: min(350, screenFrame.height))
    }

    func dismiss() {
        presentation = UUID() // Cancel pending focus restoration/paste when the user dismisses or reopens.
        panel?.resignKey()
        panel?.orderOut(nil)
        panel?.contentView = nil
        targetWindow = nil
        targetInput = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        localMonitor = nil
        outsideMonitor = nil
        settingsPresented = false
        collectionPresented = false
    }

    func selectFirstIfNeeded() {
        if !visibleEntries.contains(where: { $0.id == selectedID }) { selectedID = visibleEntries.first?.id }
    }

    func select(offset: Int) {
        let entries = visibleEntries
        guard !entries.isEmpty else { selectedID = nil; return }
        let index = entries.firstIndex(where: { $0.id == selectedID }) ?? 0
        selectedID = entries[min(max(index + offset, 0), entries.count - 1)].id
    }

    func paste(_ id: UUID, plain: Bool = false) {
        let store = ClipboardHistoryStore.shared
        guard store.enabled, !pasting else { return }
        pasting = true
        let token = presentation
        let target = targetApplication
        let targetWindow = targetWindow
        let targetInput = targetInput
        let copyOnly = store.pasteTarget == .clipboard
        let usePlainText = plain || store.alwaysPlainText
        Task {
            defer { pasting = false }
            guard await ClipboardHistoryStore.shared.copy(id, plain: usePlainText, ifCurrent: { token == self.presentation }) else { return }
            if copyOnly { dismiss(); return }
            let copiedChange = NSPasteboard.general.changeCount
            let permission = AccessibilityPermissionStore.shared
            permission.refreshStatus()
            guard permission.isAuthorized else {
                permission.requestAuthorizationPrompt()
                ClipboardHistoryStore.shared.message = "请在系统设置 → 隐私与安全性 → 辅助功能中允许 Eave；授权后重新打开面板，双击或按 Enter 即可直接粘贴。"
                return
            }
            guard let target, !target.isTerminated, target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                ClipboardHistoryStore.shared.message = "已复制，请切换到目标应用后按 ⌘V。"
                return
            }
            // A nonactivating panel can own keyboard focus while the target app remains frontmost.
            panel?.resignKey()
            panel?.orderOut(nil)
            target.activate(options: [])
            let app = AXUIElementCreateApplication(target.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.2)
            var restoredFocus = false
            // Wait for the original input, not just the frontmost application.
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(25))
                guard token == presentation, NSPasteboard.general.changeCount == copiedChange else {
                    if token == presentation { dismiss() }
                    return
                }
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                   panel?.isKeyWindow != true,
                   NSEvent.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty {
                    if !restoredFocus {
                        if let targetWindow {
                            AXUIElementSetAttributeValue(targetWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                            AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
                        }
                        if let targetInput {
                            AXUIElementSetAttributeValue(targetInput, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                        }
                        restoredFocus = true
                        continue // Let focus changes reach the target before sending keys.
                    }
                    if let targetInput {
                        guard let focused = Self.element(kAXFocusedUIElementAttribute, of: app),
                              CFEqual(focused, targetInput) else { continue }
                    }
                    guard let source = CGEventSource(stateID: .privateState),
                          let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                          let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { break }
                    down.flags = .maskCommand
                    up.flags = .maskCommand
                    down.postToPid(target.processIdentifier)
                    up.postToPid(target.processIdentifier)
                    dismiss()
                    return
                }
            }
            // Never send keys to a different app if activation failed.
            ClipboardHistoryStore.shared.message = "已复制，但原输入框未恢复焦点。请点击输入框后按 ⌘V 粘贴。"
            if token == presentation { panel?.makeKeyAndOrderFront(nil) }
        }
    }

    private static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func installMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type != .keyDown {
                if let window = event.window, window !== self.panel, self.panel?.attachedSheet == nil { self.dismiss() }
                return event
            }
            guard event.window === self.panel, self.panel?.attachedSheet == nil,
                  !self.settingsPresented, !self.collectionPresented else { return event }
            if let editor = self.panel?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            switch event.keyCode {
            case 53: self.dismiss(); return nil
            case 123 where !event.modifierFlags.contains(.command): self.select(offset: -1); return nil
            case 124 where !event.modifierFlags.contains(.command): self.select(offset: 1); return nil
            case 36, 76:
                if let id = self.selectedID { self.paste(id, plain: event.modifierFlags.contains(.shift)) }
                return nil
            default: return event
            }
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }
}
