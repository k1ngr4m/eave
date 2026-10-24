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

/// Single shared owner of the projects workspace. The notch page and the
/// standalone window mutate through this one instance so no entry point can
/// write a stale copy over fresher data (PRD 13.3).
@MainActor
final class ProjectWorkspaceViewModel: ObservableObject {
    static let shared = ProjectWorkspaceViewModel()

    enum LoadState: Equatable {
        case loading
        case ready
        case corrupted(reason: String)
    }

    enum SaveState: Equatable {
        case saved
        case saving
        case failed(reason: String)

        var localizedName: String {
            switch self {
            case .saved: return String(localized: "已保存")
            case .saving: return String(localized: "保存中")
            case .failed: return String(localized: "未保存")
            }
        }
    }

    /// One committed workspace change; snapshots make undo restore IDs,
    /// hierarchy, status and dates exactly (PRD 7.5).
    private struct Snapshot {
        let workspace: ProjectWorkspace
    }

    @Published private(set) var workspace = ProjectWorkspace()
    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var saveState: SaveState = .saved
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    /// Bumped whenever completion feedback should re-render (notch toast).
    @Published var lastCompleted: (task: ProjectTask, at: Date)?

    private let store: ProjectWorkspaceStore
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var hasUnsavedChanges = false
    private var saveWorkItem: DispatchWorkItem?
    private var backupWrittenThisSession = false
    /// Refreshes today/overdue grouping after midnight or zone changes.
    @Published var todayAnchor: CalendarDate = .today

    private let maxUndoOperations = 50

    init(store: ProjectWorkspaceStore = .shared) {
        self.store = store
        load()
        startDayAnchorObserver()
    }

    // MARK: Load / save lifecycle

    func load() {
        switch store.load() {
        case .empty:
            workspace = ProjectWorkspace()
            loadState = .ready
            saveState = .saved
        case .loaded(let loaded):
            workspace = loaded
            loadState = .ready
            saveState = .saved
        case .corrupted(let rawData, let reason):
            workspace = ProjectWorkspace()
            loadState = .corrupted(reason: reason)
            store.quarantineMainFile()
            _ = rawData // retained on disk untouched; recovery reads from backup or export
            saveState = .failed(reason: reason)
        }
        undoStack.removeAll()
        redoStack.removeAll()
        updateUndoFlags()
        todayAnchor = .today
    }

    /// Flushes any pending autosave; called before window close and module
    /// disable. Returns false when content still cannot be persisted.
    @discardableResult
    func flushPendingSave() -> Bool {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        guard hasUnsavedChanges else { return true }
        return performSave()
    }

    private func performSave() -> Bool {
        hasUnsavedChanges = false
        saveState = .saving
        if let error = store.save(workspace, preservingBackup: !backupWrittenThisSession) {
            backupWrittenThisSession = true
            saveState = .failed(reason: error.localizedDescription)
            hasUnsavedChanges = true // keep the in-memory draft; disk keeps the last good file
            return false
        }
        backupWrittenThisSession = true
        saveState = .saved
        return true
    }

    /// Mutations call this after applying their change to `workspace`.
    private func commit() {
        hasUnsavedChanges = true
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            _ = self?.performSave()
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
        objectWillChange.send()
    }

    // MARK: Undo / redo (PRD 7.5, 3.4)

    private func beginOperation() -> Snapshot {
        let snapshot = Snapshot(workspace: workspace)
        undoStack.append(snapshot)
        if undoStack.count > maxUndoOperations { undoStack.removeFirst() }
        redoStack.removeAll()
        updateUndoFlags()
        return snapshot
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(workspace: workspace))
        workspace = previous.workspace
        hasUnsavedChanges = true
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in _ = self?.performSave() }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
        updateUndoFlags()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(workspace: workspace))
        workspace = next.workspace
        hasUnsavedChanges = true
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in _ = self?.performSave() }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
        updateUndoFlags()
    }

    private func updateUndoFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    /// Text fields keep native text undo; ⌘Z only reaches structured
    /// operations when focus is outside a text input (PRD 7.5). Callers check
    /// this before invoking undo/redo.
    func undoIfAppropriate(focusInTextField: Bool) {
        guard !focusInTextField else { return }
        undo()
    }

    // MARK: Projects (PRD 6)

    static let projectTitleLimit = 100
    static let projectSummaryLimit = 2000
    static let taskTitleLimit = 200
    static let taskSummaryLimit = 10000

    @discardableResult
    func createProject(title: String, colorHex: String, summary: String) -> Project? {
        let cleanTitle = title.trimmedForStorage
        guard !cleanTitle.isEmpty, cleanTitle.count <= Self.projectTitleLimit else { return nil }
        beginOperation()
        var project = Project(title: cleanTitle, colorHex: colorHex, summary: String(summary.prefix(Self.projectSummaryLimit)))
        project.updatedAt = Date()
        workspace.projects.append(project)
        commit()
        return project
    }

    func updateProject(_ id: UUID, title: String? = nil, colorHex: String? = nil, summary: String? = nil, status: ProjectStatus? = nil) {
        guard let index = workspace.projects.firstIndex(where: { $0.id == id }) else { return }
        beginOperation()
        if let title, let clean = title.trimmedForStorage.isEmpty ? nil : title.trimmedForStorage, clean.count <= Self.projectTitleLimit {
            workspace.projects[index].title = clean
        }
        if let colorHex { workspace.projects[index].colorHex = colorHex }
        if let summary { workspace.projects[index].summary = String(summary.prefix(Self.projectSummaryLimit)) }
        if let status { workspace.projects[index].status = status }
        workspace.projects[index].updatedAt = Date()
        commit()
    }

    func archiveProject(_ id: UUID) {
        guard let index = workspace.projects.firstIndex(where: { $0.id == id }) else { return }
        beginOperation()
        workspace.projects[index].archivedAt = Date()
        workspace.projects[index].updatedAt = Date()
        commit()
    }

    func restoreArchivedProject(_ id: UUID) {
        guard let index = workspace.projects.firstIndex(where: { $0.id == id }) else { return }
        beginOperation()
        workspace.projects[index].archivedAt = nil
        workspace.projects[index].updatedAt = Date()
        commit()
    }

    /// Deletes a project and all of its tasks as one undoable operation.
    func deleteProject(_ id: UUID) {
        guard workspace.projects.contains(where: { $0.id == id }) else { return }
        beginOperation()
        workspace.projects.removeAll { $0.id == id }
        workspace.tasks.removeAll { $0.projectID == id }
        commit()
    }

    func project(_ id: UUID?) -> Project? {
        guard let id else { return nil }
        return workspace.projects.first { $0.id == id }
    }

    func projectTitle(_ id: UUID?) -> String {
        project(id)?.title ?? String(localized: "收集箱")
    }

    // MARK: Tasks (PRD 7)

    func task(_ id: UUID) -> ProjectTask? {
        workspace.tasks.first { $0.id == id }
    }

    /// Minimal creation: title only. Returns the new task.
    @discardableResult
    func createTask(title: String,
                    projectID: UUID?,
                    parentTaskID: UUID? = nil,
                    priority: ProjectTaskPriority = .none,
                    startDate: CalendarDate? = nil,
                    dueDate: CalendarDate? = nil,
                    summary: String = "",
                    status: ProjectTaskStatus = .todo) -> ProjectTask? {
        let clean = title.trimmedForStorage
        guard !clean.isEmpty, clean.count <= Self.taskTitleLimit else { return nil }
        if let parentID = parentTaskID, task(parentID) == nil { return nil }
        beginOperation()
        let now = Date()
        var newTask = ProjectTask(projectID: projectID,
                                  parentTaskID: parentTaskID,
                                  title: clean,
                                  summary: String(summary.prefix(Self.taskSummaryLimit)),
                                  status: status,
                                  priority: priority,
                                  startDate: startDate,
                                  dueDate: dueDate,
                                  completedAt: status == .completed ? now : nil,
                                  createdAt: now,
                                  updatedAt: now)
        // Validation pass would reject nothing here, but keep IDs stable.
        workspace.tasks.append(newTask)
        commit()
        return newTask
    }

    /// Applies arbitrary validated field edits to one task as one operation.
    func updateTask(_ id: UUID,
                    title: String? = nil,
                    summary: String? = nil,
                    status: ProjectTaskStatus? = nil,
                    priority: ProjectTaskPriority? = nil,
                    startDate: CalendarDate?? = nil,
                    dueDate: CalendarDate?? = nil,
                    projectID: UUID?? = nil) {
        guard let index = workspace.tasks.firstIndex(where: { $0.id == id }) else { return }
        beginOperation()

        if let title {
            let clean = title.trimmedForStorage
            if !clean.isEmpty && clean.count <= Self.taskTitleLimit {
                workspace.tasks[index].title = clean
            }
        }
        if let summary { workspace.tasks[index].summary = String(summary.prefix(Self.taskSummaryLimit)) }
        if let status { setStatusInPlace(index: index, status: status) }
        if let priority { workspace.tasks[index].priority = priority }
        if let startDate {
            workspace.tasks[index].startDate = startDate
            // First chosen start date defaults the due date to the same day
            // when the task had no schedule at all (PRD 10.1).
            if startDate != nil, workspace.tasks[index].dueDate == nil {
                workspace.tasks[index].dueDate = startDate
            }
        }
        if let dueDate { workspace.tasks[index].dueDate = dueDate }
        if let projectID { workspace.tasks[index].projectID = projectID }
        workspace.tasks[index].updatedAt = Date()
        commit()
    }

    private func setStatusInPlace(index: Int, status: ProjectTaskStatus) {
        workspace.tasks[index].status = status
        if status == .completed {
            if workspace.tasks[index].completedAt == nil {
                workspace.tasks[index].completedAt = Date()
            }
        } else {
            workspace.tasks[index].completedAt = nil
        }
    }

    /// Checkbox toggle: unchecking returns to todo (PRD 7.3).
    func toggleCompletion(_ id: UUID) {
        guard let current = task(id), !TaskRules.hasChildren(current, tasks: workspace.tasks) else { return }
        updateTask(id, status: current.isCompleted ? .todo : .completed)
        if !current.isCompleted {
            lastCompleted = (current, Date())
        }
    }

    /// Deletes one task. Parent tasks cascade their single level of children;
    /// the whole deletion is one undoable operation.
    func deleteTask(_ id: UUID) {
        guard let victim = task(id) else { return }
        beginOperation()
        let childrenIDs = Set(TaskRules.children(of: victim.id, in: workspace.tasks).map(\.id))
        workspace.tasks.removeAll { $0.id == victim.id || childrenIDs.contains($0.id) }
        commit()
    }

    /// Removes the last child, turning a summary back into a normal task that
    /// keeps the previously displayed summary values (PRD 7.4).
    func removeSubtaskAndRestoreParent(childID: UUID) {
        guard let child = task(childID), let parentID = child.parentTaskID,
              let parent = task(parentID) else {
            deleteTask(childID)
            return
        }
        beginOperation()
        workspace.tasks.removeAll { $0.id == child.id }
        if TaskRules.children(of: parentID, in: workspace.tasks).isEmpty {
            if let index = workspace.tasks.firstIndex(where: { $0.id == parentID }) {
                workspace.tasks[index].status = TaskRules.derivedStatus(for: parentID, tasks: workspace.tasks)
                let dates = TaskRules.derivedDates(for: parentID, tasks: workspace.tasks)
                workspace.tasks[index].startDate = dates.start
                workspace.tasks[index].dueDate = dates.due
                workspace.tasks[index].updatedAt = Date()
            }
        }
        commit()
    }

    /// "移为顶层任务": detaches a subtask while keeping project and data.
    func makeTopLevel(taskID: UUID) {
        guard let index = workspace.tasks.firstIndex(where: { $0.id == taskID }),
              workspace.tasks[index].parentTaskID != nil else { return }
        beginOperation()
        let parentID = workspace.tasks[index].parentTaskID
        workspace.tasks[index].parentTaskID = nil
        workspace.tasks[index].updatedAt = Date()
        if let parentID, TaskRules.children(of: parentID, in: workspace.tasks).isEmpty,
           let parentIndex = workspace.tasks.firstIndex(where: { $0.id == parentID }) {
            workspace.tasks[parentIndex].status = TaskRules.derivedStatus(for: parentID, tasks: workspace.tasks)
            let dates = TaskRules.derivedDates(for: parentID, tasks: workspace.tasks)
            workspace.tasks[parentIndex].startDate = dates.start
            workspace.tasks[parentIndex].dueDate = dates.due
            workspace.tasks[parentIndex].updatedAt = Date()
        }
        commit()
    }

    // MARK: Subtask conversion (PRD 7.4, C03)

    struct SubtaskConversionPlan {
        let inheritedStatus: ProjectTaskStatus
        let inheritedPriority: ProjectTaskPriority
        let inheritedStart: CalendarDate?
        let inheritedDue: CalendarDate?
    }

    /// Whether turning `parent` into a summary task needs explicit user
    /// confirmation first: only tasks that carry their own schedule or a
    /// non-todo status change meaning when they become summaries.
    func needsConversionConfirmation(for parentID: UUID) -> Bool {
        guard let parent = task(parentID) else { return false }
        if parent.startDate != nil || parent.dueDate != nil { return true }
        if parent.status != .todo { return true }
        return false
    }

    func conversionPlan(for parentID: UUID) -> SubtaskConversionPlan? {
        guard let parent = task(parentID) else { return nil }
        return SubtaskConversionPlan(inheritedStatus: parent.status,
                                     inheritedPriority: parent.priority,
                                     inheritedStart: parent.startDate,
                                     inheritedDue: parent.dueDate)
    }

    /// Adds the first subtask of a task with schedule/status, transferring
    /// those values to the new child and clearing the parent's own copy.
    @discardableResult
    func addFirstSubtaskAfterConversion(parentID: UUID, childTitle: String) -> ProjectTask? {
        guard let parent = task(parentID),
              let clean = childTitle.trimmedForStorage.isEmpty ? nil : childTitle.trimmedForStorage,
              clean.count <= Self.taskTitleLimit else { return nil }
        beginOperation()
        guard let parentIndex = workspace.tasks.firstIndex(where: { $0.id == parentID }) else { return nil }
        let now = Date()
        let child = ProjectTask(projectID: workspace.tasks[parentIndex].projectID,
                                parentTaskID: parentID,
                                title: clean,
                                status: workspace.tasks[parentIndex].status,
                                priority: .none,
                                startDate: workspace.tasks[parentIndex].startDate,
                                dueDate: workspace.tasks[parentIndex].dueDate,
                                completedAt: workspace.tasks[parentIndex].completedAt,
                                createdAt: now,
                                updatedAt: now)
        workspace.tasks.append(child)
        workspace.tasks[parentIndex].status = .todo
        workspace.tasks[parentIndex].startDate = nil
        workspace.tasks[parentIndex].dueDate = nil
        workspace.tasks[parentIndex].completedAt = nil
        workspace.tasks[parentIndex].updatedAt = now
        commit()
        return child
    }

    // MARK: Moving (PRD 7.4)

    /// Moves a top-level task (with all of its children) to another project.
    func moveTopLevelTask(_ id: UUID, to projectID: UUID?) {
        guard let moving = task(id), moving.parentTaskID == nil else { return }
        if let target = projectID, project(target)?.isArchived == true { return }
        beginOperation()
        let childIDs = Set(TaskRules.children(of: id, in: workspace.tasks).map(\.id))
        for index in workspace.tasks.indices {
            let matches = workspace.tasks[index].id == id || childIDs.contains(workspace.tasks[index].id)
            if matches {
                workspace.tasks[index].projectID = projectID
                workspace.tasks[index].updatedAt = Date()
            }
        }
        commit()
    }

    // MARK: Recovery (PRD 12, 13.4)

    func restoreFromBackup(at url: URL) -> Result<Void, String> {
        switch store.readBackup(at: url) {
        case .failure(let error):
            return .failure(error.errorDescription ?? String(localized: "备份无效"))
        case .success(let restored):
            if let error = store.restore(restored) {
                return .failure(error.localizedDescription)
            }
            undoStack.removeAll()
            redoStack.removeAll()
            updateUndoFlags()
            workspace = restored
            loadState = .ready
            saveState = .saved
            hasUnsavedChanges = false
            return .success(())
        }
    }

    func exportWorkspace(to url: URL) -> String? {
        if let error = store.export(workspace, to: url) {
            return error.localizedDescription
        }
        return nil
    }

    // MARK: Day rollover

    private func startDayAnchorObserver() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshTodayAnchor() }
        }
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshTodayAnchor() }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshTodayAnchor() }
        }
    }

    private func refreshTodayAnchor() {
        todayAnchor = .today
    }

    // MARK: Derived conveniences

    var todayGroups: [TaskRules.TodaySection: [ProjectTask]] {
        TaskRules.todayGroups(workspace: workspace, today: todayAnchor)
    }

    var todayTotalCount: Int {
        todayGroups.values.reduce(0) { $0 + $1.count }
    }

    var inboxCount: Int {
        workspace.tasks.filter { $0.parentTaskID == nil && $0.projectID == nil }.count
    }

    var allTasksCount: Int {
        workspace.projects.filter { !$0.isArchived }.reduce(0) { count, project in
            count + workspace.tasks.filter { $0.projectID == project.id }.count
        } + workspace.tasks.filter { $0.projectID == nil }.count
    }
}
