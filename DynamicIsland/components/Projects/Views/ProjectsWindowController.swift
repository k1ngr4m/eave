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

/// Owns the single 项目与任务 window. Repeated openings activate the existing
/// window instead of creating a second one (PRD 5.2); closing flushes pending
/// autosaves and returns the Dock to the notch-only policy.
@MainActor
final class ProjectsWindowController: NSWindowController {
    static let shared = ProjectsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1160, height: 760),
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
        guard let window else { return }
        window.title = String(localized: "项目与任务")
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = false
        window.level = .normal
        window.collectionBehavior = [.managed, .participatesInCycle]
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("EaveProjectsWindow")

        let rootView = ProjectsWindowView()
            .environmentObject(ProjectWorkspaceViewModel.shared)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        window.contentMinSize = NSSize(width: 900, height: 600)
        window.contentView = hostingView
        window.setFrameUsingName("EaveProjectsWindow")
        window.setFrameAutosaveName("EaveProjectsWindow")

        window.delegate = self
        window.center()
    }

    func showWindow(focusing navigation: ProjectsNavigation? = nil, selecting taskID: UUID? = nil) {
        DockActivationPolicy.shared.setWindowVisible(true, id: "projects")
        _ = window

        if let navigation {
            ProjectsWindowFocus.shared.pendingNavigation = navigation
        }
        if let taskID {
            ProjectsWindowFocus.shared.pendingTaskSelection = taskID
        }

        window?.level = .normal
        window?.collectionBehavior = [.managed, .participatesInCycle]

        if window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            ProjectsWindowFocus.shared.deliverPending()
            window?.makeKeyAndOrderFront(nil)
            return
        }

        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        ProjectsWindowFocus.shared.deliverPending()
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self] in
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    override func close() {
        super.close()
        DockActivationPolicy.shared.setWindowVisible(false, id: "projects")
    }
}

extension ProjectsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Commit valid drafts before the window goes away; invalid drafts were
        // already surfaced by the detail panel's own gate (PRD 8.4).
        _ = ProjectWorkspaceViewModel.shared.flushPendingSave()
        DockActivationPolicy.shared.setWindowVisible(false, id: "projects")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}

/// Bridge for cross-surface "open window and locate X" requests (notch task
/// rows, "查看任务" after creating under a filter). Delivered on next show.
@MainActor
final class ProjectsWindowFocus: ObservableObject {
    static let shared = ProjectsWindowFocus()

    var pendingNavigation: ProjectsNavigation?
    var pendingTaskSelection: UUID?

    func deliverPending() {
        if let navigation = pendingNavigation {
            ProjectsWindowState.shared.select(navigation)
            pendingNavigation = nil
        }
        if let taskID = pendingTaskSelection {
            ProjectsWindowState.shared.openTaskDetail(taskID, in: ProjectWorkspaceViewModel.shared.workspace)
            pendingTaskSelection = nil
        }
    }
}
