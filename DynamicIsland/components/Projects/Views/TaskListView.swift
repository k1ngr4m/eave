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

import SwiftUI

/// List content for inbox / all tasks / single project. Builds the visible
/// tree (top level + one level of children), applies search, filters and
/// sorting, shows the unscheduled section and hosts quick add (PRD 7.2, 8).
struct TaskListContainerView: View {
    @EnvironmentObject private var vm: ProjectWorkspaceViewModel
    @ObservedObject var uiState = ProjectsWindowState.shared
    @State private var quickAddText = ""
    @FocusState private var quickAddFocused: Bool
    @State private var hiddenCreateToast: String?
    @State private var hiddenCreateTaskID: UUID?

    var body: some View {
        let scope = visibleTasks

        VStack(spacing: 0) {
            columnHeader

            Divider().opacity(0.5)

            if scope.isEmpty && unscheduledTasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ForEach(Array(scope.enumerated()), id: \.element.id) { _, row in
                            rowView(row)
                            Divider().opacity(0.4).padding(.leading, 44)
                        }

                        if !unscheduledTasks.isEmpty {
                            unscheduledSection
                        }
                    }
                }
            }

            Divider().opacity(0.5)
            quickAddBar
        }
        .overlay(alignment: .bottom) {
            if let toast = hiddenCreateToast {
                createHiddenToast(text: toast)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: Data shaping

    private var navigationProjectID: UUID? {
        switch uiState.selection {
        case .project(let id): return id
        default: return nil
        }
    }

    /// Top-level tasks in the current navigation scope, filtered and sorted.
    private var topLevel: [ProjectTask] {
        var tasks = TaskRules.topLevelTasks(in: vm.workspace.tasks, projectID: navigationProjectID)
        if case .allTasks = uiState.selection {
            // exclude archived projects
            let archived = Set(vm.workspace.projects.filter(\.isArchived).map(\.id))
            tasks = tasks.filter { $0.projectID == nil || !archived.contains($0.projectID!) }
        }
        tasks = TaskRules.sortTasks(tasks, by: uiState.sortField)
        return applyTaskFilters(tasks)
    }

    struct ListRow: Identifiable {
        let task: ProjectTask
        let children: [ProjectTask]
        let isSummary: Bool
        let hiddenChildCount: Int

        var id: UUID { task.id }
    }

    /// Pairs every top-level task with its (filtered) children; parents stay
    /// visible as context when children match, with a "hidden" count for the
    /// filtered-out remainder (PRD 8.3).
    private var visibleTasks: [ListRow] {
        topLevel.compactMap { parent in
            let allChildren = TaskRules.children(of: parent.id, in: vm.workspace.tasks)
            let filteredChildren = applyTaskFilters(allChildren)
            let matchesSelf = matchesScope(parent)

            if uiState.hasActiveFilters {
                guard matchesSelf || !filteredChildren.isEmpty else { return nil }
            }

            let sortedChildren = TaskRules.sortTasks(filteredChildren, by: .createdAt)
            let hidden = allChildren.count - filteredChildren.count
            return ListRow(task: parent,
                           children: uiState.expandedTaskIDs.contains(parent.id) ? sortedChildren : [],
                           isSummary: !allChildren.isEmpty,
                           hiddenChildCount: hidden)
        }
    }

    private var unscheduledTasks: [ProjectTask] {
        applyTaskFilters(vm.workspace.tasks.filter { task in
            guard task.projectID == navigationProjectID, task.startDate == nil, task.dueDate == nil else { return false }
            if task.parentTaskID != nil { return false }
            if case .allTasks = uiState.selection {
                let archived = Set(vm.workspace.projects.filter(\.isArchived).map(\.id))
                if let pid = task.projectID, archived.contains(pid) { return false }
            }
            return true
        })
    }

    private func matchesScope(_ task: ProjectTask) -> Bool {
        applyTaskFilters([task]).count == 1
    }

    private func applyTaskFilters(_ tasks: [ProjectTask]) -> [ProjectTask] {
        var result = tasks
        if !uiState.searchQuery.isEmpty {
            result = result.filter { TaskRules.matches($0, query: uiState.searchQuery) }
        }
        if !uiState.statusFilter.isEmpty {
            result = result.filter { uiState.statusFilter.contains(effectiveStatus($0)) }
        }
        if !uiState.priorityFilter.isEmpty {
            result = result.filter { uiState.priorityFilter.contains($0.priority) }
        }
        if let projectFilter = uiState.projectFilter {
            result = result.filter { $0.projectID == projectFilter }
        }
        if !uiState.showCompletedTasks {
            result = result.filter { !$0.isCompleted || TaskRules.hasChildren($0, tasks: vm.workspace.tasks) }
        }
        return result
    }

    private func effectiveStatus(_ task: ProjectTask) -> ProjectTaskStatus {
        guard TaskRules.hasChildren(task, tasks: vm.workspace.tasks) else { return task.status }
        return TaskRules.derivedStatus(for: task.id, tasks: vm.workspace.tasks)
    }

    // MARK: Column header

    private var showsProjectColumn: Bool {
        switch uiState.selection {
        case .project: return false
        default: return true
        }
    }

    private var showsStartDateColumn: Bool {
        // Narrow windows fold the start-date column; the detail keeps both ends.
        true
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text(String(localized: "任务名称"))
                .frame(maxWidth: .infinity, alignment: .leading)
            columnHeaderCell(String(localized: "状态"), width: 76)
            columnHeaderCell(String(localized: "优先级"), width: 56)
            if showsStartDateColumn {
                columnHeaderCell(String(localized: "开始"), width: 64)
            }
            columnHeaderCell(String(localized: "截止"), width: 64)
            if showsProjectColumn {
                columnHeaderCell(String(localized: "项目"), width: 90)
            }
            Color.clear.frame(width: 16)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func columnHeaderCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .frame(width: width, alignment: .leading)
    }

    // MARK: Rows

    @ViewBuilder
    private func rowView(_ row: ListRow) -> some View {
        TaskRowView(task: row.task,
                    isSummary: row.isSummary,
                    childCount: TaskRules.children(of: row.task.id, in: vm.workspace.tasks).count,
                    showsProjectColumn: showsProjectColumn,
                    showsStartDateColumn: showsStartDateColumn)
        ForEach(row.children) { child in
            TaskRowView(task: child,
                        isSummary: false,
                        childCount: 0,
                        showsProjectColumn: showsProjectColumn,
                        showsStartDateColumn: showsStartDateColumn,
                        isIndented: true)
        }
        if row.hiddenChildCount > 0 && uiState.expandedTaskIDs.contains(row.task.id) {
            HStack {
                Spacer().frame(width: 66)
                Text(String(localized: "还有 \(row.hiddenChildCount) 个子任务未匹配当前筛选"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 3)
        }
    }

    private var unscheduledSection: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.6)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    uiState.showsUnscheduledFoldout.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: uiState.showsUnscheduledFoldout ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "待安排 · \(unscheduledTasks.count)"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if uiState.showsUnscheduledFoldout {
                ForEach(TaskRules.sortTasks(unscheduledTasks, by: uiState.sortField)) { task in
                    TaskRowView(task: task,
                                isSummary: TaskRules.hasChildren(task, tasks: vm.workspace.tasks),
                                childCount: TaskRules.children(of: task.id, in: vm.workspace.tasks).count,
                                showsProjectColumn: showsProjectColumn,
                                showsStartDateColumn: showsStartDateColumn,
                                unscheduledContext: true)
                    Divider().opacity(0.4).padding(.leading, 44)
                }
            }
        }
    }

    // MARK: Quick add

    private var quickAddBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(String(localized: "快速记一件事，回车保存…"), text: $quickAddText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($quickAddFocused)
                .onSubmit { submitQuickAdd() }
            if !quickAddText.isEmpty {
                Text(String(localized: "回车添加"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func submitQuickAdd() {
        let title = quickAddText
        guard !title.trimmedForStorage.isEmpty else { return }
        quickAddText = ""
        quickAddFocused = true // keep focus for continuous entry (PRD 7.2)
        let projectID: UUID?
        switch uiState.selection {
        case .project(let id): projectID = id
        default: projectID = nil
        }
        guard let created = vm.createTask(title: title, projectID: projectID) else { return }

        if !matchesScope(created) || !visibleTasks.contains(where: { $0.task.id == created.id }) {
            hiddenCreateTaskID = created.id
            hiddenCreateToast = String(localized: "已创建，当前筛选未显示")
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                if hiddenCreateTaskID == created.id {
                    hiddenCreateToast = nil
                    hiddenCreateTaskID = nil
                }
            }
        }
    }

    private func createHiddenToast(text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 12))
            Button(String(localized: "查看任务")) {
                guard let id = hiddenCreateTaskID else { return }
                uiState.clearFilters()
                uiState.searchQuery = ""
                uiState.openTaskDetail(id, in: vm.workspace)
                hiddenCreateToast = nil
                hiddenCreateTaskID = nil
            }
            .buttonStyle(.link)
            .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: uiState.hasActiveFilters ? "magnifyingglass" : "tray")
                .font(.system(size: 34))
                .foregroundStyle(.quaternary)
            Text(uiState.hasActiveFilters
                 ? String(localized: "没有匹配的任务")
                 : (navigationProjectID == nil ? String(localized: "收集箱是空的") : String(localized: "还没有任务")))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if uiState.hasActiveFilters {
                Button(String(localized: "清除条件")) {
                    uiState.clearFilters()
                    uiState.searchQuery = ""
                }
                .buttonStyle(.link)
            } else {
                Text(String(localized: "在下方输入标题，回车即可快速记录"))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Single row

struct TaskRowView: View {
    @EnvironmentObject private var vm: ProjectWorkspaceViewModel
    @ObservedObject var uiState = ProjectsWindowState.shared
    let task: ProjectTask
    let isSummary: Bool
    let childCount: Int
    let showsProjectColumn: Bool
    let showsStartDateColumn: Bool
    var isIndented = false
    var unscheduledContext = false

    @State private var confirmDelete = false

    var body: some View {
        let summary = isSummary
        let progress = summary ? TaskRules.summaryProgress(taskID: task.id, tasks: vm.workspace.tasks) : nil
        let isSelected = uiState.detailTaskID == task.id && uiState.detailVisible

        HStack(spacing: 0) {
            HStack(spacing: 8) {
                if isIndented { Spacer().frame(width: 22) }

                if summary {
                    Button {
                        uiState.toggleExpanded(task.id)
                    } label: {
                        Image(systemName: uiState.expandedTaskIDs.contains(task.id) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "展开子任务"))
                } else if !isIndented {
                    Color.clear.frame(width: 14)
                }

                if summary {
                    // Parents deliberately have no bulk-complete checkbox.
                    Circle()
                        .fill(Color(nsColor: .quaternarySystemFill))
                        .frame(width: 15, height: 15)
                        .overlay(
                            Text("\(progress?.completed ?? 0)/\(progress?.total ?? 0)")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.secondary)
                        )
                        .help(String(localized: "汇总任务：\(progress?.completed ?? 0)/\(progress?.total ?? 0) 已完成"))
                } else {
                    TaskCheckbox(isCompleted: task.isCompleted) {
                        vm.toggleCompletion(task.id)
                    }
                }

                titleText

                if summary {
                    Text("\(progress?.completed ?? 0)/\(progress?.total ?? 0)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color(nsColor: .quaternarySystemFill), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { openDetail() }

            statusCell
            priorityCell
            if showsStartDateColumn {
                dateCell(effectiveStart)
            }
            dateCell(effectiveDue)
            if showsProjectColumn {
                projectCell
            }
            Color.clear.frame(width: 16)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 42)
        .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        .contextMenu {
            if isSummary || !isSummary {
                Button(String(localized: "添加子任务")) {
                    uiState.detailTaskID = task.id
                    uiState.detailVisible = true
                    NotificationCenter.default.post(name: .projectsAddSubtaskRequested, object: task.id)
                }
                if !isSummary {
                    Menu(String(localized: "移动到项目")) {
                        Button(String(localized: "收集箱")) { vm.moveTopLevelTask(task.id, to: nil) }
                        ForEach(vm.workspace.projects.filter { !$0.isArchived && $0.id != task.projectID }) { project in
                            Button(project.title) { vm.moveTopLevelTask(task.id, to: project.id) }
                        }
                    }
                    .disabled(task.parentTaskID != nil)
                }
                if task.parentTaskID != nil {
                    Button(String(localized: "移为顶层任务")) { vm.makeTopLevel(taskID: task.id) }
                }
                Divider()
                Button(String(localized: "删除任务"), role: .destructive) {
                    if isSummary {
                        confirmDelete = true
                    } else {
                        vm.deleteTask(task.id)
                    }
                }
            }
        }
        .confirmationDialog(String(localized: "删除「\(task.title)」？"),
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(String(localized: "删除任务及 \(childCount) 个子任务"), role: .destructive) {
                vm.deleteTask(task.id)
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "该操作包含全部子任务，可在之后撤销。"))
        }
    }

    private var effectiveStatus: ProjectTaskStatus {
        guard isSummary else { return task.status }
        return TaskRules.derivedStatus(for: task.id, tasks: vm.workspace.tasks)
    }

    private var effectiveStart: CalendarDate? {
        guard isSummary else { return task.startDate }
        return TaskRules.derivedDates(for: task.id, tasks: vm.workspace.tasks).start
    }

    private var effectiveDue: CalendarDate? {
        guard isSummary else { return task.dueDate }
        return TaskRules.derivedDates(for: task.id, tasks: vm.workspace.tasks).due
    }

    private var titleText: some View {
        Text(task.title)
            .font(.system(size: 13, weight: task.isCompleted ? .regular : .medium))
            .strikethrough(task.isCompleted, color: .secondary)
            .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
            .lineLimit(1)
            .help(unscheduledHint ?? task.title)
    }

    private var unscheduledHint: String? {
        guard unscheduledContext, task.dueDate == nil, task.startDate == nil else { return nil }
        return String(localized: "待安排")
    }

    private var statusCell: some View {
        HStack {
            StatusDot(status: effectiveStatus)
            Spacer()
        }
        .frame(width: 76, alignment: .leading)
    }

    private var priorityCell: some View {
        HStack {
            PriorityChip(priority: task.priority)
            Spacer()
        }
        .frame(width: 56, alignment: .leading)
    }

    private func dateCell(_ date: CalendarDate?) -> some View {
        HStack {
            if let date {
                Text(date.shortDisplayText)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(dateColor(date))
            } else {
                Text("—")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }
            Spacer()
        }
        .frame(width: 64, alignment: .leading)
    }

    private func dateColor(_ date: CalendarDate) -> Color {
        if !task.isCompleted, let due = task.dueDate, date == due, due < CalendarDate.today {
            return .red
        }
        return .primary.opacity(0.8)
    }

    private var projectCell: some View {
        HStack(spacing: 5) {
            if let project = vm.project(task.projectID) {
                ProjectDot(colorHex: project.colorHex, size: 7)
                Text(project.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(String(localized: "收集箱"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .frame(width: 90, alignment: .leading)
    }

    private func openDetail() {
        uiState.detailTaskID = task.id
        uiState.detailVisible = true
    }
}

extension Notification.Name {
    static let projectsAddSubtaskRequested = Notification.Name("projectsAddSubtaskRequested")
}

// MARK: - Today view (grouped list, PRD 8.1 / design L02)

struct TodayListView: View {
    @EnvironmentObject private var vm: ProjectWorkspaceViewModel
    @ObservedObject var uiState = ProjectsWindowState.shared
    @State private var collapsedSections: Set<TaskRules.TodaySection> = []
    @State private var quickAddText = ""
    @FocusState private var quickAddFocused: Bool

    var body: some View {
        let groups = filteredGroups

        VStack(spacing: 0) {
            if groups.values.allSatisfy(\.isEmpty) {
                emptyToday
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        ForEach(TaskRules.TodaySection.allCases, id: \.self) { section in
                            if let tasks = groups[section], !tasks.isEmpty {
                                sectionHeader(section, count: tasks.count)
                                if !collapsedSections.contains(section) {
                                    ForEach(tasks) { task in
                                        TodayTaskRow(task: task, today: vm.todayAnchor)
                                        Divider().opacity(0.4).padding(.leading, 40)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }

            Divider().opacity(0.5)
            todayQuickAdd
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var filteredGroups: [TaskRules.TodaySection: [ProjectTask]] {
        var groups = vm.todayGroups
        if !uiState.searchQuery.isEmpty {
            for (section, tasks) in groups {
                groups[section] = tasks.filter { TaskRules.matches($0, query: uiState.searchQuery) }
            }
        }
        return groups
    }

    private func sectionHeader(_ section: TaskRules.TodaySection, count: Int) -> some View {
        Button {
            if collapsedSections.contains(section) {
                collapsedSections.remove(section)
            } else {
                collapsedSections.insert(section)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: collapsedSections.contains(section) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Image(systemName: icon(for: section))
                    .font(.system(size: 12))
                    .foregroundStyle(tint(for: section))
                Text(section.localizedName)
                    .font(.system(size: 13, weight: .semibold))
                Text("· \(count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func icon(for section: TaskRules.TodaySection) -> String {
        switch section {
        case .overdue: return "exclamationmark.circle"
        case .dueToday: return "calendar"
        case .inProgress: return "play.circle"
        }
    }

    private func tint(for section: TaskRules.TodaySection) -> Color {
        switch section {
        case .overdue: return .red
        case .dueToday: return .blue
        case .inProgress: return .green
        }
    }

    private var todayQuickAdd: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(String(localized: "快速记一件事，回车保存…"), text: $quickAddText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($quickAddFocused)
                .onSubmit {
                    guard !quickAddText.trimmedForStorage.isEmpty else { return }
                    _ = vm.createTask(title: quickAddText, projectID: nil)
                    quickAddText = ""
                    quickAddFocused = true
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyToday: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34))
                .foregroundStyle(.quaternary)
            Text(String(localized: "今天没有到期或进行中的任务"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button(String(localized: "查看全部任务")) { uiState.select(.allTasks) }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Today row: checkbox, title, project breadcrumb, priority and due badge.
struct TodayTaskRow: View {
    @EnvironmentObject private var vm: ProjectWorkspaceViewModel
    @ObservedObject var uiState = ProjectsWindowState.shared
    let task: ProjectTask
    let today: CalendarDate

    var body: some View {
        HStack(spacing: 10) {
            TaskCheckbox(isCompleted: task.isCompleted) {
                vm.toggleCompletion(task.id)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                breadcrumb
            }
            .contentShape(Rectangle())
            .onTapGesture {
                uiState.openTaskDetail(task.id, in: vm.workspace)
            }

            Spacer()

            PriorityChip(priority: task.priority)
            dueBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            if let project = vm.project(task.projectID) {
                ProjectDot(colorHex: project.colorHex, size: 6)
                Text(project.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let parent = task.parentTaskID.flatMap({ vm.task($0) }) {
                    Text("›")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(parent.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(String(localized: "收集箱"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dueBadge: some View {
        Group {
            if let display = DueDisplay.resolve(task, today: today) {
                DueBadge(text: display.text, kind: display.badgeKind)
            } else if task.status == .inProgress {
                Text(task.dueDate?.shortDisplayText ?? "—")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 52, alignment: .trailing)
    }
}
