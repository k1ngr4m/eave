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

/// 刘海任务页 (PRD 11): header with counts + 打开项目, the three exclusive
/// today groups (逾期 → 今日到期 → 进行中), quick add at the bottom. Shares
/// all rules with the full window through ProjectWorkspaceViewModel/TaskRules.
struct NotchTasksView: View {
    @EnvironmentObject private var vm: ProjectWorkspaceViewModel
    @EnvironmentObject private var viewModel: DynamicIslandViewModel

    @State private var collapsedSections: Set<TaskRules.TodaySection> = []
    @State private var quickAddText = ""
    @State private var quickAddProjectID: UUID?
    @State private var quickAddFocused = false
    @State private var completionToast: (title: String, at: Date)?
    @State private var toastUndoTaskID: UUID?
    @FocusState private var addFieldFocused: Bool

    private let quickAddToken = UUID()

    var body: some View {
        let groups = vm.todayGroups
        let total = groups.values.reduce(0) { $0 + $1.count }

        VStack(spacing: 0) {
            header(totalCount: total)

            if total == 0 && completionToast == nil {
                emptyState
            } else {
                groupsList(groups)
            }

            quickAddBar
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .padding(.top, 6)
        .onChange(of: vm.lastCompleted?.at) { _, newValue in
            guard let at = newValue, let entry = vm.lastCompleted, entry.at == at else { return }
            toastUndoTaskID = entry.task.id
            completionToast = (entry.task.title, entry.at)
            // Brief feedback, then the row is simply gone (PRD 11.2).
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                if let toast = completionToast, toast.at == at {
                    completionToast = nil
                    toastUndoTaskID = nil
                }
            }
        }
        .onChange(of: addFieldFocused) { _, focused in
            viewModel.setAutoCloseSuppression(focused, token: quickAddToken)
        }
        .onDisappear {
            viewModel.setAutoCloseSuppression(false, token: quickAddToken)
        }
    }

    // MARK: Header

    private func header(totalCount: Int) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "checklist")
                    .font(.system(size: 13, weight: .semibold))
                Text(String(localized: "任务"))
                    .font(.system(size: 14, weight: .semibold))
                if totalCount > 0 {
                    Text("· \(totalCount)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                openProjectsWindow()
            } label: {
                HStack(spacing: 4) {
                    Text(String(localized: "打开项目"))
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(String(localized: "打开项目与任务窗口"))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    // MARK: Groups

    private func groupsList(_ groups: [TaskRules.TodaySection: [ProjectTask]]) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(TaskRules.TodaySection.allCases, id: \.self) { section in
                    if let tasks = groups[section], !tasks.isEmpty {
                        notchGroupHeader(section, count: tasks.count)
                        if !collapsedSections.contains(section) {
                            ForEach(tasks) { task in
                                NotchTaskRow(task: task,
                                             today: vm.todayAnchor,
                                             projectTitle: vm.project(task.projectID)?.title) {
                                    openProjectsWindow(selecting: task.id)
                                } onToggle: {
                                    vm.toggleCompletion(task.id)
                                }
                            }
                        }
                    }
                }

                if let toast = completionToast, let undoID = toastUndoTaskID {
                    completionFeedback(title: toast.title, undoID: undoID)
                }
            }
            .padding(.horizontal, 2)
        }
        .foregroundStyle(.white)
    }

    private func notchGroupHeader(_ section: TaskRules.TodaySection, count: Int) -> some View {
        Button {
            if collapsedSections.contains(section) {
                collapsedSections.remove(section)
            } else {
                collapsedSections.insert(section)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: collapsedSections.contains(section) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Image(systemName: icon(for: section))
                    .font(.system(size: 10))
                    .foregroundStyle(tint(for: section))
                Text(section.localizedName)
                    .font(.system(size: 11, weight: .semibold))
                Text("· \(count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.top, 5)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func icon(for section: TaskRules.TodaySection) -> String {
        switch section {
        case .overdue: return "clock.badge.exclamationmark"
        case .dueToday: return "calendar"
        case .inProgress: return "play.fill"
        }
    }

    private func tint(for section: TaskRules.TodaySection) -> Color {
        switch section {
        case .overdue: return .red
        case .dueToday: return .blue
        case .inProgress: return .green
        }
    }

    private func completionFeedback(title: String, undoID: UUID) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
            Text(String(localized: "已完成「\(title)」"))
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            Button {
                vm.toggleCompletion(undoID)
                completionToast = nil
                toastUndoTaskID = nil
            } label: {
                Text(String(localized: "撤销"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(String(localized: "今天没有到期或进行中的任务"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button(String(localized: "查看全部任务")) {
                openProjectsWindow(navigation: .allTasks)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.blue)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    // MARK: Quick add (PRD 11.1/11.2)

    private var quickAddBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField(String(localized: "快速记一件事…"), text: $quickAddText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($addFieldFocused)
                .onSubmit(submitQuickAdd)

            projectPicker

            Button {
                submitQuickAdd()
            } label: {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(quickAddText.isEmpty ? Color.white.opacity(0.08) : Color.accentColor,
                                in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(quickAddText.trimmedForStorage.isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.08)))
    }

    private var projectPicker: some View {
        Menu {
            Button(String(localized: "收集箱")) { quickAddProjectID = nil }
            ForEach(vm.workspace.projects.filter { !$0.isArchived }) { project in
                Button {
                    quickAddProjectID = project.id
                } label: {
                    HStack {
                        ProjectDot(colorHex: project.colorHex, size: 7)
                        Text(project.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let project = vm.project(quickAddProjectID) {
                    ProjectDot(colorHex: project.colorHex, size: 7)
                    Text(project.title)
                        .font(.system(size: 10))
                        .lineLimit(1)
                } else {
                    Image(systemName: "tray")
                        .font(.system(size: 9))
                    Text(String(localized: "收集箱"))
                        .font(.system(size: 10))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!addFieldFocused && quickAddText.isEmpty)
    }

    private func submitQuickAdd() {
        let title = quickAddText
        guard !title.trimmedForStorage.isEmpty else { return }
        _ = vm.createTask(title: title, projectID: quickAddProjectID)
        quickAddText = ""
        addFieldFocused = true // keep focus for continuous capture (PRD 7.2)
    }

    // MARK: Window bridge

    private func openProjectsWindow(selecting taskID: UUID? = nil,
                                    navigation: ProjectsNavigation? = nil) {
        viewModel.close()
        if let navigation {
            ProjectsWindowController.shared.showWindow(focusing: navigation)
        } else {
            ProjectsWindowController.shared.showWindow(selecting: taskID)
        }
    }
}

/// One compact notch row: checkbox, title, project, due chip (PRD 11.1).
struct NotchTaskRow: View {
    let task: ProjectTask
    let today: CalendarDate
    let projectTitle: String?
    let onOpen: () -> Void
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? String(localized: "已完成") : String(localized: "标记完成"))

            Text(task.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)

            Spacer(minLength: 4)

            if let projectTitle {
                Text(projectTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let display = DueDisplay.resolve(task, today: today) {
                DueBadge(text: display.text, kind: display.badgeKind)
            } else if task.status == .inProgress, let due = task.dueDate {
                Text(due.shortDisplayText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}
