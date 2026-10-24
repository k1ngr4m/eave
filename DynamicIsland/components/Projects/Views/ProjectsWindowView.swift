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

/// Root layout of the standalone window: fixed 200 pt sidebar, main content
/// (list or gantt), optional 300 pt detail. Narrow windows overlay the detail
/// so the gantt is never squeezed out of usability (PRD 5.4).
struct ProjectsWindowView: View {
    @EnvironmentObject private var vm: ProjectWorkspaceViewModel
    @ObservedObject var uiState = ProjectsWindowState.shared
    @State private var newProjectSheetPresented = false
    @State private var newTaskSheetPresented = false
    @State private var pendingTaskParentID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            ProjectSidebar(newProjectSheetPresented: $newProjectSheetPresented)
            Divider()
                .opacity(0.6)

            mainPane

            if uiState.detailVisible, let taskID = uiState.detailTaskID {
                Divider().opacity(0.6)
                TaskDetailPanel(taskID: taskID)
                    .frame(width: 300)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeOut(duration: 0.18), value: uiState.detailVisible)
        .sheet(isPresented: $newProjectSheetPresented) {
            ProjectFormSheet(project: nil)
        }
        .sheet(isPresented: $newTaskSheetPresented) {
            TaskFormSheet(projectID: defaultProjectForNewTask, parentTaskID: nil)
        }
        .onAppear {
            ProjectsWindowFocus.shared.deliverPending()
        }
        .onChange(of: uiState.selection) { _, newValue in
            guard case .project(let id) = newValue else { return }
            // A selected project may have been deleted from the notch or
            // another window entry point.
            if vm.project(id) == nil {
                uiState.select(.allTasks)
            }
        }
        .background {
            keyboardShortcuts
        }
    }

    /// Window-scope keyboard shortcuts (PRD 15.2). ⌘Z reaches structured
    /// operations only when no text input has focus; native text undo stays
    /// untouched inside fields.
    private var keyboardShortcuts: some View {
        Group {
            Button(String(localized: "新任务")) { newTaskSheetPresented = true }
                .keyboardShortcut("n", modifiers: .command)
            Button(String(localized: "搜索")) { uiState.searchFocusRequest += 1 }
                .keyboardShortcut("f", modifiers: .command)
            Button(String(localized: "撤销")) {
                vm.undoIfAppropriate(focusInTextField: uiState.searchFieldFocused)
            }
            .keyboardShortcut("z", modifiers: .command)
            Button(String(localized: "重做")) {
                vm.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var defaultProjectForNewTask: UUID? {
        if case .project(let id) = uiState.selection { return id }
        return nil
    }

    @ViewBuilder
    private var mainPane: some View {
        VStack(spacing: 0) {
            if case .corrupted(let reason) = vm.loadState {
                corruptedBanner(reason)
            }
            contentHeader

            Divider().opacity(0.6)

            contentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A corrupted workspace is never silently treated as empty (PRD 12).
    private func corruptedBanner(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(String(localized: "工作区数据读取失败，已保留原文件，未当作空数据使用。"))
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            Text(reason)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Button(String(localized: "从备份恢复…")) {
                    NSWorkspace.shared.activateFileViewerSelecting([ProjectWorkspaceStore.shared.directory])
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(String(localized: "打开数据位置")) {
                    NSWorkspace.shared.activateFileViewerSelecting([ProjectWorkspaceStore.shared.fileURL])
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: Header

    @ViewBuilder
    private var contentHeader: some View {
        switch uiState.selection {
        case .project(let id):
            if let project = vm.project(id) {
                ProjectHeader(project: project,
                              newTaskTapped: { newTaskSheetPresented = true })
            } else {
                EmptyView()
            }
        default:
            AggregateHeader(title: headerTitle,
                            subtitle: headerSubtitle,
                            supportsViewSwitch: supportsViewSwitch,
                            supportsGanttToolbar: supportsGanttToolbar,
                            newTaskTapped: { newTaskSheetPresented = true })
        }
    }

    private var headerTitle: String {
        switch uiState.selection {
        case .inbox: return String(localized: "收集箱")
        case .today: return String(localized: "今日")
        case .allTasks: return String(localized: "全部任务")
        case .project: return ""
        case .archived: return String(localized: "已归档")
        }
    }

    private var headerSubtitle: String? {
        guard case .today = uiState.selection else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        let count = vm.todayTotalCount
        return count > 0
            ? "\(formatter.string(from: Date())) · \(String(localized: "\(count) 项待处理"))"
            : formatter.string(from: Date())
    }

    private var supportsViewSwitch: Bool {
        switch uiState.selection {
        case .inbox, .allTasks, .project: return true
        case .today, .archived: return false
        }
    }

    private var supportsGanttToolbar: Bool { supportsViewSwitch }

    @ViewBuilder
    private var contentArea: some View {
        switch uiState.selection {
        case .archived:
            ArchivedProjectsView(newProjectSheetPresented: $newProjectSheetPresented)
        case .today:
            TodayListView()
        default:
            if uiState.contentView == .gantt {
                GanttContainerView()
            } else {
                TaskListContainerView()
            }
        }
    }
}

// MARK: - Project header

/// Header for a single project: name, status menu, archive/… menu, progress
/// summary line with derived date range.
private struct ProjectHeader: View {
    @EnvironmentObject private var vm: ProjectWorkspaceViewModel
    @ObservedObject var uiState = ProjectsWindowState.shared
    let project: Project
    let newTaskTapped: () -> Void

    @State private var editSheetPresented = false
    @State private var showArchiveConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showCompleteWithOpenTasksConfirm = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ProjectDot(colorHex: project.colorHex, size: 12)
                Text(project.title)
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(1)

                Menu {
                    ForEach(ProjectStatus.allCases) { status in
                        Button {
                            if status == .completed && hasUnfinishedTasks {
                                showCompleteWithOpenTasksConfirm = true
                            } else {
                                vm.updateProject(project.id, status: status)
                            }
                        } label: {
                            if project.status == status {
                                Label(status.localizedName, systemImage: "checkmark")
                            } else {
                                Text(status.localizedName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(project.status.localizedName)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .quaternarySystemFill), in: Capsule())
                }
                .fixedSize()
                .accessibilityLabel(String(localized: "项目状态"))

                Menu {
                    Button(String(localized: "编辑项目")) { editSheetPresented = true }
                    Button(project.isArchived ? String(localized: "恢复项目") : String(localized: "归档项目")) {
                        if project.isArchived {
                            vm.restoreArchivedProject(project.id)
                        } else {
                            showArchiveConfirm = true
                        }
                    }
                    Divider()
                    Button(String(localized: "删除项目…"), role: .destructive) { showDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 26, height: 22)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(String(localized: "项目操作"))

                Spacer()

                searchField
                newTaskButton
            }

            progressLine
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .sheet(isPresented: $editSheetPresented) {
            ProjectFormSheet(project: project)
        }
        .confirmationDialog(String(localized: "归档「\(project.title)」？"),
                            isPresented: $showArchiveConfirm, titleVisibility: .visible) {
            Button(String(localized: "归档")) { vm.archiveProject(project.id) }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "归档后项目与任务从常用视图和刘海中移除，可在“已归档”中查看并恢复。"))
        }
        .confirmationDialog(String(localized: "删除「\(project.title)」？"),
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(String(localized: "删除项目与全部任务"), role: .destructive) {
                vm.deleteProject(project.id)
                uiState.select(.allTasks)
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "将同时删除 \(taskCount) 个任务。建议先归档保留数据。删除后可在本次会话内撤销。"))
        }
        .confirmationDialog(String(localized: "仍有未完成的任务"),
                            isPresented: $showCompleteWithOpenTasksConfirm, titleVisibility: .visible) {
            Button(String(localized: "保留任务状态并完成项目")) {
                vm.updateProject(project.id, status: .completed)
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "项目中有 \(unfinishedCount) 个未完成任务。任务状态不会被批量修改。"))
        }
    }

    private var taskCount: Int {
        vm.workspace.tasks.filter { $0.projectID == project.id }.count
    }

    private var unfinishedCount: Int {
        vm.workspace.tasks.filter {
            $0.projectID == project.id && !$0.isCompleted && !TaskRules.hasChildren($0, tasks: vm.workspace.tasks)
        }.count
    }

    private var hasUnfinishedTasks: Bool {
        vm.workspace.tasks.contains { $0.projectID == project.id && !$0.isCompleted }
    }

    private var progressLine: some View {
        let progress = TaskRules.projectProgress(projectID: project.id, tasks: vm.workspace.tasks)
        let range = TaskRules.scheduledRange(ofTasks: vm.workspace.tasks.filter { $0.projectID == project.id })
        let unscheduled = vm.workspace.tasks.filter { $0.projectID == project.id && $0.startDate == nil && $0.dueDate == nil }.count

        return HStack(spacing: 10) {
            if progress.total == 0 {
                Text(String(localized: "暂无任务"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "完成 \(progress.completed)/\(progress.total) · \(progress.percentText ?? "")"))
                    .font(.system(size: 12, weight: .medium))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(nsColor: .quaternarySystemFill))
                        Capsule().fill(Color.accentColor)
                            .frame(width: max(4, geo.size.width * progress.fraction))
                    }
                }
                .frame(width: 130, height: 5)
            }
            if let range {
                Text("\(range.lowerBound.shortDisplayText) – \(range.upperBound.shortDisplayText)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if unscheduled > 0 {
                Text(String(localized: "\(unscheduled) 项待安排"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(String(localized: "搜索"), text: $uiState.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 140)
                .focused(uiState.$searchFieldFocused)
                .onChange(of: uiState.searchFocusRequest) { _, _ in
                    uiState.searchFieldFocused = true
                }
            if !uiState.searchQuery.isEmpty {
                Button {
                    uiState.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 7))
    }

    private var newTaskButton: some View {
        Button(action: newTaskTapped) {
            Label(String(localized: "新任务"), systemImage: "plus")
                .font(.system(size: 12, weight: .medium))
        }
        .controlSize(.regular)
        .buttonStyle(.borderedProminent)
    }
}

// MARK: - Aggregate header (inbox / today / all tasks)

private struct AggregateHeader: View {
    @ObservedObject var uiState = ProjectsWindowState.shared
    let title: String
    let subtitle: String?
    let supportsViewSwitch: Bool
    let supportsGanttToolbar: Bool
    let newTaskTapped: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
                Spacer()
                searchField
                if supportsViewSwitch {
                    viewSwitcher
                }
                filterMenu
                newTaskButton
            }
            if uiState.hasActiveFilters {
                activeFilterSummary
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var viewSwitcher: some View {
        Picker("", selection: $uiState.contentView) {
            Label(String(localized: "列表"), systemImage: "list.bullet").tag(ProjectsContentView.list)
            Label(String(localized: "甘特图"), systemImage: "rectangle.righthalf.inset.filled").tag(ProjectsContentView.gantt)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 150)
        .accessibilityLabel(String(localized: "视图类型"))
    }

    private var filterMenu: some View {
        Menu {
            filterSection(String(localized: "状态")) {
                ForEach(ProjectTaskStatus.allCases) { status in
                    toggleRow(status.localizedName, isOn: uiState.statusFilter.contains(status)) {
                        if uiState.statusFilter.contains(status) {
                            uiState.statusFilter.remove(status)
                        } else {
                            uiState.statusFilter.insert(status)
                        }
                    }
                }
            }
            filterSection(String(localized: "优先级")) {
                ForEach([ProjectTaskPriority.high, .medium, .low]) { priority in
                    toggleRow(priority.localizedName, isOn: uiState.priorityFilter.contains(priority)) {
                        if uiState.priorityFilter.contains(priority) {
                            uiState.priorityFilter.remove(priority)
                        } else {
                            uiState.priorityFilter.insert(priority)
                        }
                    }
                }
            }
            Divider()
            Button(String(localized: "清除筛选")) { uiState.clearFilters() }
                .disabled(!uiState.hasActiveFilters)
        } label: {
            Label(String(localized: "筛选"), systemImage: uiState.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 12, weight: .medium))
        }
        .accessibilityLabel(String(localized: "筛选"))
    }

    @ViewBuilder
    private func filterSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Section(title) { content() }
    }

    private func toggleRow(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isOn { Image(systemName: "checkmark") }
            }
        }
    }

    private var activeFilterSummary: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ForEach(Array(uiState.statusFilter).sorted { $0.rawValue < $1.rawValue }, id: \.rawValue) { status in
                filterChip(status.localizedName)
            }
            ForEach(Array(uiState.priorityFilter).sorted { $0.sortRank > $1.sortRank }, id: \.rawValue) { priority in
                filterChip(priority.localizedName)
            }
            Button(String(localized: "清除")) { uiState.clearFilters() }
                .buttonStyle(.link)
                .font(.system(size: 11))
            Spacer()
        }
    }

    private func filterChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(String(localized: "搜索当前任务"), text: $uiState.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 140)
                .focused(uiState.$searchFieldFocused)
                .onChange(of: uiState.searchFocusRequest) { _, _ in
                    uiState.searchFieldFocused = true
                }
            if !uiState.searchQuery.isEmpty {
                Button {
                    uiState.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 7))
    }

    private var newTaskButton: some View {
        Button(action: newTaskTapped) {
            Label(String(localized: "新任务"), systemImage: "plus")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.borderedProminent)
    }
}

// MARK: - Archived projects (read-only list)

private struct ArchivedProjectsView: View {
    @EnvironmentObject private var vm: ProjectWorkspaceViewModel
    @ObservedObject var uiState = ProjectsWindowState.shared
    @Binding var newProjectSheetPresented: Bool

    var body: some View {
        let archived = vm.workspace.projects.filter(\.isArchived).sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }

        if archived.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(archived) { project in
                        archivedRow(project)
                        Divider().opacity(0.5)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func archivedRow(_ project: Project) -> some View {
        let taskCount = vm.workspace.tasks.filter { $0.projectID == project.id }.count
        return HStack(spacing: 10) {
            ProjectDot(colorHex: project.colorHex)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .font(.system(size: 13, weight: .medium))
                Text(String(localized: "\(taskCount) 个任务 · 只读"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "查看任务")) {
                uiState.select(.project(project.id))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button(String(localized: "恢复")) {
                vm.restoreArchivedProject(project.id)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "archivebox")
                .font(.system(size: 34))
                .foregroundStyle(.quaternary)
            Text(String(localized: "没有已归档的项目"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
