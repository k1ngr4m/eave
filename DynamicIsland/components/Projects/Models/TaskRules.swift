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

import Foundation

/// The single source of derived rules: summary-task aggregation, project
/// progress, overdue and today grouping. List, Gantt and notch views all read
/// from here so the numbers can never disagree between surfaces (PRD 10, 16).
enum TaskRules {

    // MARK: Tree helpers

    static func tasksByID(_ tasks: [ProjectTask]) -> [UUID: ProjectTask] {
        Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    }

    static func children(of taskID: UUID, in tasks: [ProjectTask]) -> [ProjectTask] {
        tasks.filter { $0.parentTaskID == taskID }
    }

    static func isSummary(_ task: ProjectTask, tasksByID: [UUID: ProjectTask]) -> Bool {
        tasksByID.values.contains { $0.parentTaskID == task.id }
    }

    /// Top-level tasks (no parent) belonging to a project — or the inbox when
    /// `projectID` is nil.
    static func topLevelTasks(in tasks: [ProjectTask], projectID: UUID?) -> [ProjectTask] {
        tasks.filter { $0.parentTaskID == nil && $0.projectID == projectID }
    }

    /// Walks from a top-level task down one level of children, in stable order.
    static func descendantsOneLevel(of taskID: UUID, in tasks: [ProjectTask]) -> [ProjectTask] {
        children(of: taskID, in: tasks)
    }

    // MARK: Progress (PRD 10.3 — leaf tasks only; summary parents never count)

    struct Progress: Equatable {
        let completed: Int
        let total: Int

        var fraction: Double {
            total > 0 ? Double(completed) / Double(total) : 0
        }

        /// Rounded integer percentage; nil for an empty project ("暂无任务").
        var percentText: String? {
            guard total > 0 else { return nil }
            let percent = Int((fraction * 100).rounded())
            return "\(percent)%"
        }
    }

    /// Project progress counts leaf tasks: standalone top-level tasks plus
    /// subtasks. Summary parents stay out of the denominator.
    static func projectProgress(projectID: UUID, tasks: [ProjectTask]) -> Progress {
        let leaves = tasks.filter { $0.projectID == projectID && $0.parentTaskID != nil }
            + tasks.filter { $0.projectID == projectID && $0.parentTaskID == nil && !isSummary($0, tasksByID: tasksByID(tasks)) }
        let done = leaves.filter(\.isCompleted).count
        return Progress(completed: done, total: leaves.count)
    }

    /// A summary task's progress is its subtask completion ratio.
    static func summaryProgress(taskID: UUID, tasks: [ProjectTask]) -> Progress {
        let kids = children(of: taskID, in: tasks)
        let done = kids.filter(\.isCompleted).count
        return Progress(completed: done, total: kids.count)
    }

    // MARK: Summary derivation (PRD 7.4)

    /// Summary status: all children completed → completed, all todo → todo,
    /// anything else → in progress.
    static func derivedStatus(for taskID: UUID, tasks: [ProjectTask]) -> ProjectTaskStatus {
        let kids = children(of: taskID, in: tasks)
        guard !kids.isEmpty else { return .todo }
        if kids.allSatisfy({ $0.status == .completed }) { return .completed }
        if kids.allSatisfy({ $0.status == .todo }) { return .todo }
        return .inProgress
    }

    /// Summary dates: earliest scheduled start and latest due across children.
    /// Returns nil ranges when no child has dates.
    static func derivedDates(for taskID: UUID, tasks: [ProjectTask]) -> (start: CalendarDate?, due: CalendarDate?, unscheduledCount: Int) {
        let kids = children(of: taskID, in: tasks)
        let starts = kids.compactMap(\.startDate)
        let dues = kids.compactMap(\.dueDate)
        let unscheduled = kids.filter { $0.startDate == nil && $0.dueDate == nil }.count
        return (starts.min(), dues.max(), unscheduled)
    }

    /// A task that has children is a summary task: its own status/dates are
    /// derived, never edited directly.
    static func hasChildren(_ task: ProjectTask, tasks: [ProjectTask]) -> Bool {
        tasks.contains { $0.parentTaskID == task.id }
    }

    // MARK: Due/overdue classification (PRD 10.2)

    /// Overdue: not completed and due before today. A due date of today is
    /// "due today" until the day ends; tasks without dates never go overdue.
    /// Completed tasks are never overdue (PRD 7.3).
    static func isOverdue(_ task: ProjectTask, today: CalendarDate) -> Bool {
        guard !task.isCompleted, let due = task.dueDate else { return false }
        return due < today
    }

    static func isDueToday(_ task: ProjectTask, today: CalendarDate) -> Bool {
        guard !task.isCompleted, let due = task.dueDate else { return false }
        return due == today
    }

    // MARK: Today view (PRD 8.1)

    /// Mutually exclusive buckets, ordered 逾期 → 今日到期 → 进行中. A task
    /// that is overdue and in-progress lands only in 逾期. Projects completed
    /// but not archived still contribute their unfinished tasks.
    enum TodaySection: Int, CaseIterable, Identifiable {
        case overdue
        case dueToday
        case inProgress

        var id: Int { rawValue }

        var localizedName: String {
            switch self {
            case .overdue: return String(localized: "逾期")
            case .dueToday: return String(localized: "今日到期")
            case .inProgress: return String(localized: "进行中")
            }
        }
    }

    /// Leaves and inbox tasks of non-archived projects, grouped into today's
    /// three buckets. `today` is injected so the boundary can be recomputed on
    /// day/time-zone changes without repolling.
    static func todayGroups(workspace: ProjectWorkspace, today: CalendarDate) -> [TodaySection: [ProjectTask]] {
        var buckets: [TodaySection: [ProjectTask]] = [:]
        let archivedProjectIDs = Set(workspace.projects.filter(\.isArchived).map(\.id))

        for task in workspace.tasks where !task.isCompleted {
            guard task.parentTaskID == nil else { continue } // summary parents never execute
            guard !hasChildren(task, tasks: workspace.tasks) else { continue }
            if let projectID = task.projectID, archivedProjectIDs.contains(projectID) { continue }

            let section: TodaySection
            if isOverdue(task, today: today) {
                section = .overdue
            } else if isDueToday(task, today: today) {
                section = .dueToday
            } else if task.status == .inProgress {
                section = .inProgress
            } else {
                continue // future-scheduled todo tasks stay out of today
            }
            buckets[section, default: []].append(task)
        }

        for (section, tasks) in buckets {
            buckets[section] = sortForExecution(tasks)
        }
        return buckets
    }

    /// Notch/list execution order: due-date ascending, then priority
    /// descending, then creation ascending; undated in-progress tasks last.
    static func sortForExecution(_ tasks: [ProjectTask]) -> [ProjectTask] {
        tasks.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case (nil, nil), (nil, _):
                if lhs.dueDate == nil && rhs.dueDate == nil {
                    return ordering(lhs, rhs)
                }
                return false // undated after dated
            case (_, nil):
                return true
            case (let l?, let r?):
                if l != r { return l < r }
                return ordering(lhs, rhs)
            }
        }
    }

    private static func ordering(_ lhs: ProjectTask, _ rhs: ProjectTask) -> Bool {
        if lhs.priority.sortRank != rhs.priority.sortRank {
            return lhs.priority.sortRank > rhs.priority.sortRank
        }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    // MARK: List ordering (PRD 8.3)

    enum ListSortField: String, CaseIterable, Identifiable {
        case createdAt
        case dueDate
        case priority

        var id: String { rawValue }

        var localizedName: String {
            switch self {
            case .createdAt: return String(localized: "创建时间")
            case .dueDate: return String(localized: "截止日期")
            case .priority: return String(localized: "优先级")
            }
        }
    }

    /// Sorts siblings within one parent only; the list code is responsible for
    /// keeping children attached to their parents.
    static func sortTasks(_ tasks: [ProjectTask], by field: ListSortField) -> [ProjectTask] {
        tasks.sorted { lhs, rhs in
            switch field {
            case .createdAt:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            case .dueDate:
                switch (lhs.dueDate, rhs.dueDate) {
                case (nil, nil):
                    return lhs.id.uuidString < rhs.id.uuidString
                case (nil, _):
                    return false // undated last
                case (_, nil):
                    return true
                case (let l?, let r?):
                    if l != r { return l < r }
                    if lhs.priority.sortRank != rhs.priority.sortRank {
                        return lhs.priority.sortRank > rhs.priority.sortRank
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
            case .priority:
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank > rhs.priority.sortRank
                }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    // MARK: Search (PRD 8.3)

    /// Case-insensitive match against title and description.
    static func matches(_ task: ProjectTask, query: String) -> Bool {
        let needle = query.lowercased()
        return task.title.lowercased().contains(needle) || task.summary.lowercased().contains(needle)
    }

    // MARK: Schedule range

    static func scheduledRange(ofTasks tasks: [ProjectTask]) -> ClosedRange<CalendarDate>? {
        var starts: [CalendarDate] = []
        var ends: [CalendarDate] = []
        for task in tasks {
            if let start = task.startDate { starts.append(start) }
            if let due = task.dueDate { ends.append(due) }
        }
        guard let first = starts.min() ?? ends.min(), let last = ends.max() ?? starts.max() else { return nil }
        return first...max(first, last)
    }
}
