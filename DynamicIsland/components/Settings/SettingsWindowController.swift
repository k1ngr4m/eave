/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        setupWindow()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupWindow() {
        guard let window = window else { return }
        
        window.title = String(localized: "Eave Settings")
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.level = .normal
        
        // Make it behave like a regular app window with proper Spaces support
        window.collectionBehavior = [.managed, .participatesInCycle]
        
        // Ensure proper window behavior
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false
        
        // Configure window to be a standard document-style window
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("DynamicIslandSettingsWindow")
        
        // Create the SwiftUI content
        let settingsView = SettingsView()
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView
        
        // Handle window closing
        window.delegate = self
        
        ScreenCaptureVisibilityManager.shared.register(window, scope: .panelsOnly)
    }
    
    func showWindow() {
        DockActivationPolicy.shared.setWindowVisible(true, id: "settings")
        // Ensure window exists
        _ = window

        // Reassert regular window semantics in case any prior state mutated this window.
        window?.level = .normal
        window?.collectionBehavior = [.managed, .participatesInCycle]
        
        // If window is already visible, bring it to front properly
        if window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            window?.orderFrontRegardless()
            window?.makeKeyAndOrderFront(nil)
            return
        }
        
        // Show the window with proper ordering
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        window?.center()
        
        // Activate the app and ensure window gets focus
        NSApp.activate(ignoringOtherApps: true)
        
        // Force window to front after activation
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }
    
    override func close() {
        super.close()
        relinquishFocus()
    }
    
    private func relinquishFocus() {
        window?.orderOut(nil)
        
        DockActivationPolicy.shared.setWindowVisible(false, id: "settings")
    }
    
    deinit {
        if let window = window {
            ScreenCaptureVisibilityManager.shared.unregister(window)
        }
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        relinquishFocus()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        DockActivationPolicy.shared.setWindowVisible(true, id: "settings")
    }
    
    func windowDidResignKey(_ notification: Notification) {
    }
    
}

/// One owner for Dock visibility, including settings, onboarding and modal windows.
@MainActor
final class DockActivationPolicy {
    static let shared = DockActivationPolicy()
    private(set) var isDynamicDockEnabled = false
    private var visibleWindows: Set<String> = []
    private let apply: @MainActor (NSApplication.ActivationPolicy) -> Void

    init(apply: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) }) {
        self.apply = apply
    }

    func setDynamicDockEnabled(_ enabled: Bool) {
        isDynamicDockEnabled = enabled
        update()
    }

    func setWindowVisible(_ visible: Bool, id: String) {
        if visible { visibleWindows.insert(id) } else { visibleWindows.remove(id) }
        update()
    }

    private func update() {
        apply(isDynamicDockEnabled || !visibleWindows.isEmpty ? .regular : .accessory)
    }
}
