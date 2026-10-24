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

/// 300 pt detail column. Title/summary autosave after a pause; status,
/// priority, project and dates commit immediately (PRD 8.4).
struct TaskDetailPanel: View {
    @EnvironmentObject private var vm: ProjectWorkspaceViewModel
    @ObservedObject var uiState = ProjectsWindowState.shared
    let taskID: UUID

    // Drafts
    @State private var titleDraft = ""
    @State private var summaryDraft = ""
    @State private var titleSaveTask: DispatchWorkItem?
    @State private var summarySaveTask: DispatchWorkItem?
    @State private var titleError: String?

    @State private var confirmDelete = false
    @State private var addSubtaskSheetPresented = false
    @State private var moveToProjectMenuPresented = false

    var body: some View {
        Group {
            if let task = vm.task(taskID) {
                content(for: task)
            } else {
                deletedNotice
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .onAppear(perform: reloadDrafts)
        .onChange(of: taskID) { _, _ in reloadDrafts() }
        .onChange(of: vm.workspace) { _, _ in
            // Another entry point may have edited the same task; keep fields honest.
            if let task = vm.task(taskID) {
                if titleDraft != task.title && titleSaveTask == nil { titleDraft = task.title }
                if summaryDraft != task.summary && summarySaveTask == nil { summaryDraft = task.summary }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .projectsAddSubtaskRequested)) { note in
            if let id = note.object as? UUID, id == taskID {
                addSubtaskSheetPresented = true
            }
        }
    }

    private func content(for task: ProjectTask) -> some View {
        let isSummary = TaskRules.hasChildren(task, tasks: vm.workspace.tasks)

        return VStack(alignment: .leading, spacing: 0) {
            header(for: task)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    titleField(for: task)
                    saveStateLine
                    if isSummary {
                        summaryNotice(for: task)
                    }

                    fieldRow(String(localized: "状态")) {
                        if isSummary {
                            derivedStatusText(for: task)
                        } else {
                            Picker("", selection: Binding(
                                get: { task.status },
                                set: { vm.updateTask(task.id, status: $0) })) {
                                ForEach(ProjectTaskStatus.allCases) { status in
                                    Text(status.localizedName).tag(status)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                            .accessibilityLabel(String(localized: "状态"))
                        }
                    }

                    fieldRow(String(localized: "优先级")) {
                        Picker("", selection: Binding(
                            get: { task.priority },
                            set: { vm.updateTask(task.id, priority: $0) })) {
                            ForEach(ProjectTaskPriority.allCases) { priority in
                                Text(priority.localizedName).tag(priority)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        .accessibilityLabel(String(localized: "优先级"))
                    }

                    fieldRow(String(localized: "所属项目")) {
                        Picker("", selection: Binding(
                            get: { task.projectID },
                            set: { newValue in
                                if task.parentTaskID != nil {
                                    // Subtasks must become top-level before changing projects.
                                } else {
                                    vm.moveTopLevelTask(task.id, to: newValue)
                                }
                            })) {
                            Text(String(localized: "收集箱")).tag(UUID?.none)
                            ForEach(vm.workspace.projects.filter { !$0.isArchived || $0.id == task.projectID }) { project in
                                Text(project.title).tag(UUID?.some(project.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                        .disabled(task.parentTaskID != nil)
                        .accessibilityLabel(String(localized: "所属项目"))
                    }

                    dateFields(for: task, isSummary: isSummary)

                    summaryEditor(for: task)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }

            Divider().opacity(0.5)
            footer(for: task)
        }
        .sheet(isPresented: $addSubtaskSheetPresented) {
            AddSubtaskFlowSheet(parentTaskID: taskID)
        }
        .confirmationDialog(String(localized: "删除任务？"), isPresented: $confirmDelete, titleVisibility: .visible) {
            let childCount = TaskRules.children(of: task.id, in: vm.workspace.tasks).count
            if childCount > 0 {
                Button(String(localized: "删除任务及 \(childCount) 个子任务"), role: .destructive) {
                    vm.deleteTask(task.id)
                    uiState.detailVisible = false
                }
            } else {
                Button(String(localized: "删除任务"), role: .destructive) {
                    vm.deleteTask(task.id)
                    uiState.detailVisible = false
                }
            }
            Button(String(localized: "取消"), role: .cancel) {}
        }
    }

    // MARK: Sections

    private func header(for task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                breadcrumb(for: task)
                Spacer()
                taskMenu(for: task)
                Button {
                    commitDraftsNow()
                    uiState.detailVisible = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "关闭详情"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 44)
    }

    private func breadcrumb(for task: ProjectTask) -> some View {
        HStack(spacing: 4) {
            Text(vm.projectTitle(task.projectID))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let parent = task.parentTaskID.flatMap({ vm.task($0) }) {
                Text("›").font(.system(size: 10)).foregroundStyle(.tertiary)
                Text(parent.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func taskMenu(for task: ProjectTask) -> some View {
        Menu {
            if task.parentTaskID == nil {
                Button(String(localized: "添加子任务")) { addSubtaskSheetPresented = true }
                Menu(String(localized: "移动到项目")) {
                    Button(String(localized: "收集箱")) { vm.moveTopLevelTask(task.id, to: nil) }
                    ForEach(vm.workspace.projects.filter { !$0.isArchived && $0.id != task.projectID }) { project in
                        Button(project.title) { vm.moveTopLevelTask(task.id, to: project.id) }
                    }
                }
            } else {
                Button(String(localized: "移为顶层任务")) { vm.makeTopLevel(taskID: task.id) }
            }
            Divider()
            Button(String(localized: "删除任务…"), role: .destructive) { confirmDelete = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(String(localized: "任务操作"))
    }

    private func titleField(for task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(String(localized: "任务标题"), text: $titleDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold))
                .onChange(of: titleDraft) { _, newValue in
                    scheduleTitleSave(taskID: task.id, value: newValue)
                }
                .onSubmit { commitTitleNow(taskID: task.id) }
            if let titleError {
                Text(titleError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var saveStateLine: some View {
        switch vm.saveState {
        case .saved:
            HStack(spacing: 5) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text(String(localized: "已保存")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .saving:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(String(localized: "保存中")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text(String(localized: "未保存")).font(.system(size: 11)).foregroundStyle(.orange)
                    Button(String(localized: "重试")) { _ = vm.flushPendingSave() }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
                Text(reason)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Button(String(localized: "导出当前数据")) { exportCurrentData() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
        }
    }

    private func summaryNotice(for task: ProjectTask) -> some View {
        let dates = TaskRules.derivedDates(for: task.id, tasks: vm.workspace.tasks)
        let progress = TaskRules.summaryProgress(taskID: task.id, tasks: vm.workspace.tasks)
        return VStack(alignment: .leading, spacing: 4) {
            Label(String(localized: "汇总任务"), systemImage: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(String(localized: "状态与日期由 \(progress.total) 个子任务推导\(dates.unscheduledCount > 0 ? "，含 \(dates.unscheduledCount) 项待安排" : "")。标题、说明和优先级仍可直接编辑。"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 8))
    }

    private func derivedStatusText(for task: ProjectTask) -> some View {
        HStack(spacing: 6) {
            StatusDot(status: TaskRules.derivedStatus(for: task.id, tasks: vm.workspace.tasks))
            Text(String(localized: "由子任务推导"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 150, alignment: .leading)
    }

    @ViewBuilder
    private func dateFields(for task: ProjectTask, isSummary: Bool) -> some View {
        if isSummary {
            let dates = TaskRules.derivedDates(for: task.id, tasks: vm.workspace.tasks)
            fieldRow(String(localized: "开始日期")) {
                Text(dates.start?.shortDisplayText ?? "—")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
            }
            fieldRow(String(localized: "截止日期")) {
                Text(dates.due?.shortDisplayText ?? "—")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
            }
        } else {
            let startDate = Binding<Date?>(
                get: { task.startDate?.localNoon },
                set: { newValue in
                    let newStart = newValue.map(CalendarDate.from(localNoon:))
                    validateAndCommitDates(taskID: task.id, start: newStart, due: task.dueDate)
                })
            let dueDate = Binding<Date?>(
                get: { task.dueDate?.localNoon },
                set: { newValue in
                    let newDue = newValue.map(CalendarDate.from(localNoon:))
                    validateAndCommitDates(taskID: task.id, start: task.startDate, due: newDue)
                })

            fieldRow(String(localized: "开始日期")) {
                if let start = task.startDate {
                    DatePicker("", selection: Binding(get: { startDate.wrappedValue ?? start.localNoon },
                                                      set: { startDate.wrappedValue = $0 }),
                               displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 150)
                        .accessibilityLabel(String(localized: "开始日期"))
                } else {
                    Button(String(localized: "设置开始日期")) {
                        validateAndCommitDates(taskID: task.id,
                                               start: CalendarDate.today,
                                               due: task.dueDate)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }
            }
            fieldRow(String(localized: "截止日期")) {
                if let due = task.dueDate {
                    DatePicker("", selection: Binding(get: { dueDate.wrappedValue ?? due.localNoon },
                                                      set: { dueDate.wrappedValue = $0 }),
                               displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 150)
                        .accessibilityLabel(String(localized: "截止日期"))
                } else {
                    Button(String(localized: "设置截止日期")) {
                        validateAndCommitDates(taskID: task.id,
                                               start: task.startDate,
                                               due: CalendarDate.today)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }
            }
            if task.startDate != nil || task.dueDate != nil {
                HStack(spacing: 10) {
                    if let start = task.startDate, let due = task.dueDate {
                        Text(String(localized: "\(due.days(since: start) + 1) 个日历日"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if task.startDate != nil {
                        Text(String(localized: "请补充截止日期"))
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    } else {
                        Text(String(localized: "仅截止日期"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Button(String(localized: "清除日期")) {
                        vm.updateTask(task.id, startDate: .some(nil), dueDate: .some(nil))
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
                .padding(.leading, 90)
            }
        }
    }

    private func summaryEditor(for task: ProjectTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "说明"))
                .font(.system(size: 12, weight: .semibold))
            TextEditor(text: $summaryDraft)
                .font(.system(size: 12))
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor).opacity(0.4)))
                .onChange(of: summaryDraft) { _, newValue in
                    scheduleSummarySave(taskID: task.id, value: newValue)
                }
        }
    }

    private func footer(for task: ProjectTask) -> some View {
        HStack {
            Text(String(localized: "创建于 \(task.createdAt.formatted(date: .abbreviated, time: .omitted))"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var deletedNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 26))
                .foregroundStyle(.quaternary)
            Text(String(localized: "任务已删除"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button(String(localized: "关闭")) { uiState.detailVisible = false }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Field row helper

    @ViewBuilder
    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            content()
        }
    }

    // MARK: Autosave plumbing

    private func reloadDrafts() {
        guard let task = vm.task(taskID) else { return }
        titleDraft = task.title
        summaryDraft = task.summary
        titleError = nil
    }

    private func scheduleTitleSave(taskID: UUID, value: String) {
        titleError = ProjectsValidation.titleError(value, limit: ProjectWorkspaceViewModel.taskTitleLimit)
        titleSaveTask?.cancel()
        let workItem = DispatchWorkItem {
            self.commitTitleNow(taskID: taskID)
        }
        titleSaveTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    private func commitTitleNow(taskID: UUID) {
        titleSaveTask?.cancel()
        titleSaveTask = nil
        guard titleError == nil else { return } // keep the draft, never overwrite saved value
        vm.updateTask(taskID, title: titleDraft)
    }

    private func scheduleSummarySave(taskID: UUID, value: String) {
        summarySaveTask?.cancel()
        let workItem = DispatchWorkItem {
            vm.updateTask(taskID, summary: value)
        }
        summarySaveTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    /// Date range must be legal as a whole before committing (PRD 8.4, 10.1).
    private func validateAndCommitDates(taskID: UUID, start: CalendarDate?, due: CalendarDate?) {
        guard let current = vm.task(taskID) else { return }
        if let start, let due, start > due {
            // Inline rejection; do not auto-swap. Users fix via the pickers.
            NSSound.beep()
            return
        }
        if start != nil && due == nil && current.dueDate == nil {
            vm.updateTask(taskID, startDate: start, dueDate: start)
            return
        }
        vm.updateTask(taskID, startDate: start, dueDate: due)
    }

    private func commitDraftsNow() {
        if let id = uiState.detailTaskID {
            commitTitleNow(taskID: id)
            summarySaveTask?.cancel()
            summarySaveTask = nil
            vm.updateTask(id, summary: summaryDraft)
        }
    }

    private func exportCurrentData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Eave-Projects-\(Int(Date().timeIntervalSince1970)).json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            _ = vm.exportWorkspace(to: url)
        }
    }
}
