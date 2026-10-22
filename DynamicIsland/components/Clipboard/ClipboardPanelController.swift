// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ApplicationServices
import SwiftUI

private final class ClipboardPanel: NSPanel {
    var acceptsKeyboardFocus = false
    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { false }

    @discardableResult
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        guard acceptsKeyboardFocus || responder == nil else { return false }
        return super.makeFirstResponder(responder)
    }
}

@MainActor
final class ClipboardPanelController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ClipboardPanelController()
    @Published var query = ""
    @Published var collectionID: UUID?
    @Published var favoritesOnly = false
    @Published var sourceID = ""
    @Published var selectedID: UUID?
    @Published private(set) var keyboardSelectionID: UUID?
    struct ItemPresentation: Identifiable {
        enum Action { case edit, rename, preview }
        let id: UUID
        let action: Action
    }
    @Published var itemPresentation: ItemPresentation?
    @Published var settingsPresented = false
    @Published var collectionPresented = false
    @Published private(set) var pasting = false
    @Published private(set) var presentation = UUID()
    @Published private(set) var searchFocusRequest = UUID()
    @Published private(set) var isExpanded = false
    private(set) var isDismissing = false
    private var panel: ClipboardPanel?
    private var targetApplication: NSRunningApplication?
    private var targetWindow: AXUIElement?
    private var targetInput: AXUIElement?
    private var localMonitor: Any?
    private var outsideMonitor: Any?

    var visibleEntries: [ClipboardEntry] {
        ClipboardHistoryStore.shared.filteredEntries(query: query, collectionID: collectionID,
                                                     favoritesOnly: favoritesOnly, sourceID: sourceID)
    }

    func preload() {
        guard ClipboardHistoryStore.shared.enabled, panel == nil,
              let screen = NSScreen.main else { return }
        let panel = preparePanel(frame: Self.frame(in: screen.frame))
        // Warm SwiftUI layout and drawing without ordering a window in or taking focus.
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.displayIfNeeded()
    }

    private func preparePanel(frame: NSRect) -> ClipboardPanel {
        if let panel { return panel }
        let panel = ClipboardPanel(contentRect: frame,
            styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: ClipboardPanelView(controller: self, store: .shared))
        self.panel = panel
        return panel
    }

    func toggle() {
        guard ClipboardHistoryStore.shared.enabled else { return }
        if panel?.isVisible == true && !isDismissing { dismiss(); return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            targetApplication = NSWorkspace.shared.frontmostApplication
        }
        targetWindow = nil
        targetInput = nil
        if let targetApplication, AXIsProcessTrusted() {
            let app = AXUIElementCreateApplication(targetApplication.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.2)
            targetWindow = Self.element(kAXFocusedWindowAttribute, of: app)
            targetInput = Self.element(kAXFocusedUIElementAttribute, of: app)
        }
        keyboardSelectionID = nil
        query = ""
        sourceID = ""
        favoritesOnly = false
        collectionID = nil
        itemPresentation = nil
        settingsPresented = false
        collectionPresented = false
        selectedID = ClipboardHistoryStore.shared.history.entries.first?.id
        presentation = UUID()
        isDismissing = false
        let frame = Self.frame(in: screen.frame)
        let panel = preparePanel(frame: frame)
        panel.acceptsKeyboardFocus = true
        panel.ignoresMouseEvents = false
        panel.setFrame(frame, display: false)
        panel.alphaValue = 1
        panel.contentView?.layoutSubtreeIfNeeded()
        // Use a real app activation instead of borrowing another app's keyboard focus.
        // A frontmost-app/AX check cannot detect a nonactivating panel's focus ownership.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        focusSearchIfVisible()
        let token = presentation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.presentation == token, panel.isVisible else { return }
            self.isExpanded = true
        }
        installMonitors()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        focusSearchIfVisible()
    }

    func focusSearchIfVisible() {
        guard !isDismissing, NSApp.isActive, let panel, panel.isVisible,
              panel.attachedSheet == nil, !settingsPresented,
              !collectionPresented, itemPresentation == nil else { return }
        // Activation may complete after makeKeyAndOrderFront. Retry from the actual
        // activation/key-window events instead of assuming the next run loop is ready.
        if !panel.isKeyWindow { panel.makeKey() }
        let token = presentation
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDismissing, self.presentation == token, NSApp.isActive,
                  panel.isVisible, panel.isKeyWindow, panel.attachedSheet == nil,
                  !self.settingsPresented, !self.collectionPresented,
                  self.itemPresentation == nil else { return }
            self.searchFocusRequest = UUID()
        }
    }

    static func frame(in screenFrame: NSRect) -> NSRect {
        NSRect(x: screenFrame.minX + 12, y: screenFrame.minY,
               width: max(240, screenFrame.width - 24), height: min(350, screenFrame.height))
    }

    func dismiss(restoreTarget: Bool = true) {
        guard !isDismissing else { return }
        let shouldRestoreTarget = restoreTarget && NSApp.isActive && panel?.isKeyWindow == true
        let target = targetApplication
        presentation = UUID() // Cancel pending focus restoration/paste when the user dismisses or reopens.
        isDismissing = panel?.isVisible == true
        // The retained SwiftUI search field can request focus during teardown.
        // Reject it until the next explicit opening, including throughout the animation.
        panel?.acceptsKeyboardFocus = false
        panel?.makeFirstResponder(nil)
        panel?.ignoresMouseEvents = true
        isExpanded = false
        if isDismissing {
            let token = presentation
            let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.2 : 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self, self.presentation == token, self.isDismissing else { return }
                self.panel?.orderOut(nil)
                self.isDismissing = false
                if shouldRestoreTarget, let target { self.activateTarget(target) }
            }
        }
        targetWindow = nil
        targetInput = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        localMonitor = nil
        outsideMonitor = nil
        itemPresentation = nil
        settingsPresented = false
        collectionPresented = false
    }

    private func activateTarget(_ target: NSRunningApplication) {
        guard !target.isTerminated, target.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        NSApp.yieldActivation(to: target)
        target.activate(from: .current, options: [])
    }

    func selectFirstIfNeeded() {
        if !visibleEntries.contains(where: { $0.id == selectedID }) { selectedID = visibleEntries.first?.id }
    }

    func select(offset: Int) {
        let entries = visibleEntries
        guard !entries.isEmpty else { selectedID = nil; return }
        let index = entries.firstIndex(where: { $0.id == selectedID }) ?? 0
        selectedID = entries[min(max(index + offset, 0), entries.count - 1)].id
        keyboardSelectionID = selectedID
    }

    var pasteActionTitle: String {
        if ClipboardHistoryStore.shared.pasteTarget == .clipboard { return String(localized: "Copy to Clipboard") }
        guard let targetName = targetApplication?.localizedName else { return String(localized: "Paste") }
        return String(localized: "Paste to \(targetName)")
    }

    func presentItem(_ id: UUID, action: ItemPresentation.Action) {
        guard let entry = ClipboardHistoryStore.shared.history.entries.first(where: { $0.id == id }),
              action != .edit || entry.isEditable else { return }
        selectedID = id
        itemPresentation = ItemPresentation(id: id, action: action)
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
        let isText = store.history.entries.first(where: { $0.id == id })?.isEditable == true
        let usePlainText = plain || (store.alwaysPlainText && isText)
        Task {
            defer { pasting = false }
            guard await ClipboardHistoryStore.shared.copy(id, plain: usePlainText, ifCurrent: { token == self.presentation }) else { return }
            let copiedChange = NSPasteboard.general.changeCount
            let permission = AccessibilityPermissionStore.shared
            permission.refreshStatus()
            guard copyOnly || permission.isAuthorized else {
                permission.requestAuthorizationPrompt()
                ClipboardHistoryStore.shared.message = String(localized: "Allow Eave in System Settings → Privacy & Security → Accessibility. Then reopen the panel and double-click or press Enter to paste directly.")
                return
            }
            guard let target, !target.isTerminated, target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                if copyOnly { dismiss(); return }
                ClipboardHistoryStore.shared.message = String(localized: "Copied. Switch to the target app and press ⌘V to paste.")
                return
            }
            // orderOut must finish before handing activation back: resignKey is only
            // a notification, and delayed window teardown can disrupt the target's input.
            dismiss(restoreTarget: false)
            let token = presentation
            while isDismissing && token == presentation {
                try? await Task.sleep(for: .milliseconds(25))
            }
            guard token == presentation, copyOnly || NSPasteboard.general.changeCount == copiedChange else { return }
            activateTarget(target)
            let app = AXUIElementCreateApplication(target.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.2)
            var restoredFocus = false
            // Wait for the original input, not just the frontmost application.
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(25))
                guard token == presentation, copyOnly || NSPasteboard.general.changeCount == copiedChange else {
                    return
                }
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                   !NSApp.isActive,
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
                    if copyOnly {
                        return
                    }
                    guard let source = CGEventSource(stateID: .privateState),
                          let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                          let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { break }
                    down.flags = .maskCommand
                    up.flags = .maskCommand
                    // Follow the normal keyboard route after activation/focus is verified.
                    down.post(tap: .cghidEventTap)
                    up.post(tap: .cghidEventTap)
                    return
                }
            }
            // Never send keys to a different app if activation failed.
            ClipboardHistoryStore.shared.message = String(localized: "Copied, but the original input could not regain focus. Click the input and press ⌘V to paste.")
        }
    }

    private static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func dismissIfOutside(at point: NSPoint, presentation token: UUID) {
        guard token == presentation, let panel, panel.isVisible, !isDismissing,
              panel.attachedSheet == nil, !panel.frame.contains(point) else { return }
        dismiss(restoreTarget: false)
    }

    private func installMonitors() {
        let token = presentation
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type != .keyDown {
                if let window = event.window, window !== self.panel {
                    self.dismissIfOutside(at: window.convertPoint(toScreen: event.locationInWindow), presentation: token)
                }
                return event
            }
            guard event.window === self.panel, self.panel?.attachedSheet == nil,
                  !self.settingsPresented, !self.collectionPresented, self.itemPresentation == nil else { return event }
            if let editor = self.panel?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            if let id = self.selectedID {
                let store = ClipboardHistoryStore.shared
                let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
                let textSelection = (self.panel?.firstResponder as? NSTextView)?.selectedRange().length ?? 0
                if modifiers == .command {
                    switch event.keyCode {
                    case 8 where textSelection == 0:
                        Task { _ = await store.copy(id, plain: false) }; return nil
                    case 14: self.presentItem(id, action: .edit); return nil
                    case 15: self.presentItem(id, action: .rename); return nil
                    default: break
                    }
                } else if modifiers.isEmpty && self.query.isEmpty {
                    if event.keyCode == 49 { self.presentItem(id, action: .preview); return nil }
                    if event.keyCode == 51 || event.keyCode == 117 {
                        if !store.busy { store.delete(id) }
                        return nil
                    }
                }
            }
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
            let point = NSEvent.mouseLocation
            Task { @MainActor in self?.dismissIfOutside(at: point, presentation: token) }
        }
    }
}
