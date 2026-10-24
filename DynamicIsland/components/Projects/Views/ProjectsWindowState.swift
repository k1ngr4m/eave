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

import Combine
import Foundation
import SwiftUI

/// Which item the window is browsing. Archive is its own read-only surface.
enum ProjectsNavigation: Equatable, Hashable {
    case inbox
    case today
    case allTasks
    case project(UUID)
    case archived
}

enum ProjectsContentView: String {
    case list
    case gantt
}

/// Per-window UI state: selection, expansion, search/filters, view mode and
/// the open detail. Navigation selection plus view type and sort restore
/// across relaunches; search and temporary filters do not (PRD 8.3).
@MainActor
final class ProjectsWindowState: ObservableObject {
    /// Single window, single UI state; survives window close/reopen so the
    /// last context is restored (PRD 5.2).
    static let shared = ProjectsWindowState()

    @Published var selection: ProjectsNavigation = .today
    @Published var expandedTaskIDs: Set<UUID> = []
    @Published var searchQuery: String = ""
    @Published var statusFilter: Set<ProjectTaskStatus> = []
    @Published var priorityFilter: Set<ProjectTaskPriority> = []
    @Published var projectFilter: UUID?
    @Published var sortField: TaskRules.ListSortField = .createdAt {
        didSet { persistSort() }
    }
    @Published var contentView: ProjectsContentView = .list
    @Published var detailTaskID: UUID?
    @Published var detailVisible = false
    @Published var ganttScale: GanttScale = .week
    @Published var ganttAnchorDate: CalendarDate = .today
    @Published var showsUnscheduledFoldout = true
    @Published var showCompletedTasks = true
    @Published var searchFocusRequest = 0
    @FocusState var searchFieldFocused: Bool

    private var cancellables = Set<AnyCancellable>()

    static let sortKey = "projectsWindowSort"
    static let selectionKey = "projectsWindowSelection"

    init() {
        restore()
        // Collapse the detail when the selected task disappears (deleted in
        // another entry point) so the panel cannot write into a ghost (PRD 8.4).
    }

    private static func encodeNav(_ navigation: ProjectsNavigation) -> String {
        switch navigation {
        case .inbox: return "inbox"
        case .today: return "today"
        case .allTasks: return "all"
        case .archived: return "archived"
        case .project(let id): return "project-\(id.uuidString)"
        }
    }

    private static func decodeNav(_ raw: String) -> ProjectsNavigation? {
        switch raw {
        case "inbox": return .inbox
        case "today": return .today
        case "all": return .allTasks
        case "archived": return .archived
        default:
            guard raw.hasPrefix("project-"),
                  let id = UUID(uuidString: String(raw.dropFirst("project-".count))) else { return nil }
            return .project(id)
        }
    }

    private func restore() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.selectionKey), let nav = Self.decodeNav(raw) {
            selection = nav
        }
        if let raw = defaults.string(forKey: Self.sortKey),
           let field = TaskRules.ListSortField(rawValue: raw) {
            sortField = field
        }
        $selection
            .dropFirst()
            .sink { nav in
                defaults.set(Self.encodeNav(nav), forKey: Self.selectionKey)
            }
            .store(in: &cancellables)
    }

    func persistSort() {
        UserDefaults.standard.set(sortField.rawValue, forKey: Self.sortKey)
    }
    // MARK: Selection helpers

    func select(_ navigation: ProjectsNavigation) {
        selection = navigation
        detailVisible = false
        detailTaskID = nil
    }

    /// Opens the detail for a task, expanding ancestors and switching to the
    /// navigation item that contains it (PRD 11.2).
    func openTaskDetail(_ taskID: UUID, in workspace: ProjectWorkspace) {
        guard let task = workspace.tasks.first(where: { $0.id == taskID }) else { return }
        let target: ProjectsNavigation
        if task.parentTaskID == nil {
            target = task.projectID.map { .project($0) } ?? .inbox
        } else if let parent = workspace.tasks.first(where: { $0.id == task.parentTaskID }) {
            target = parent.projectID.map { .project($0) } ?? .inbox
        } else {
            target = .inbox
        }
        if selection != target { selection = target }
        // Expand the parent chain so the row is visible.
        if let parentID = task.parentTaskID {
            expandedTaskIDs.insert(parentID)
        }
        detailTaskID = taskID
        detailVisible = true
    }

    func clearFilters() {
        statusFilter.removeAll()
        priorityFilter.removeAll()
        projectFilter = nil
    }

    var hasActiveFilters: Bool {
        !statusFilter.isEmpty || !priorityFilter.isEmpty || projectFilter != nil || !searchQuery.isEmpty
    }

    func toggleExpanded(_ id: UUID) {
        if expandedTaskIDs.contains(id) {
            expandedTaskIDs.remove(id)
        } else {
            expandedTaskIDs.insert(id)
        }
    }
}
