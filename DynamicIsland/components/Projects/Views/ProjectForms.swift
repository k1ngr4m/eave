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

// MARK: - Project create / edit (PRD 6.2)

struct ProjectFormSheet: View {
    @EnvironmentObject private var vm: ProjectWorkspaceViewModel
    @ObservedObject var uiState = ProjectsWindowState.shared
    @Environment(\.dismiss) private var dismiss

    let project: Project?

    @State private var title: String
    @State private var colorHex: String
    @State private var summary: String
    @State private var titleError: String?

    init(project: Project?) {
        self.project = project
        _title = State(initialValue: project?.title ?? "")
        _colorHex = State(initialValue: project?.colorHex ?? ProjectColor.allCases.first?.hex ?? "#0A84FF")
        _summary = State(initialValue: project?.summary ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(project == nil ? String(localized: "新项目") : String(localized: "编辑项目"))
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 5) {
                Text(String(localized: "名称"))
                    .font(.system(size: 12, weight: .medium))
                TextField(String(localized: "项目名称"), text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit(save)
                if let titleError {
                    Text(titleError).font(.system(size: 11)).foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(String(localized: "颜色"))
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 8) {
                    ForEach(ProjectColor.allCases) { color in
                        Button {
                            colorHex = color.hex
                        } label: {
                            Circle()
                                .fill(color.color)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle().stroke(Color.primary.opacity(colorHex == color.hex ? 0.8 : 0),
                                                    lineWidth: 2)
                                        .padding(-3)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "颜色") + " " + color.hex)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(String(localized: "说明（可选）"))
                    .font(.system(size: 12, weight: .medium))
                TextEditor(text: $summary)
                    .font(.system(size: 12))
                    .frame(height: 70)
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor).opacity(0.4)))
            }

            HStack {
                Spacer()
                Button(String(localized: "取消"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(project == nil ? String(localized: "创建") : String(localized: "保存"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmedForStorage.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 380)
    }

    private func save() {
        let error = ProjectsValidation.titleError(title, limit: ProjectWorkspaceViewModel.projectTitleLimit)
        titleError = error
        guard error == nil else { return }
        if let project {
            vm.updateProject(project.id, title: title, colorHex: colorHex, summary: summary)
        } else if let created = vm.createProject(title: title, colorHex: colorHex, summary: summary) {
            uiState.select(.project(created.id))
        }
        dismiss()
    }
}

// MARK: - Task create (PRD 7.2)

struct TaskFormSheet: View {
    @EnvironmentObject private var vm: ProjectWorkspaceViewModel
    @ObservedObject var uiState = ProjectsWindowState.shared
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID?
    let parentTaskID: UUID?

    @State private var title = ""
    @State private var selectedProjectID: UUID?
    @State private var priority: ProjectTaskPriority = .none
    @State private var startDate: Date?
    @State private var dueDate: Date?
    @State private var summary = ""
    @State private var dateError: String?

    init(projectID: UUID?, parentTaskID: UUID?) {
        self.projectID = projectID
        self.parentTaskID = parentTaskID
        _selectedProjectID = State(initialValue: projectID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(parentTaskID == nil ? String(localized: "新任务") : String(localized: "添加子任务"))
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 5) {
                Text(String(localized: "标题"))
                    .font(.system(size: 12, weight: .medium))
                TextField(String(localized: "要做什么？"), text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .onSubmit(save)
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "所属项目"))
                        .font(.system(size: 12, weight: .medium))
                    Picker("", selection: $selectedProjectID) {
                        Text(String(localized: "收集箱")).tag(UUID?.none)
                        ForEach(vm.workspace.projects.filter { !$0.isArchived }) { project in
                            Text(project.title).tag(UUID?.some(project.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "优先级"))
                        .font(.system(size: 12, weight: .medium))
                    Picker("", selection: $priority) {
                        ForEach(ProjectTaskPriority.allCases) { p in
                            Text(p.localizedName).tag(p)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "开始日期"))
                        .font(.system(size: 12, weight: .medium))
                    DatePicker("", selection: Binding(
                        get: { startDate ?? dueDate ?? Date() },
                        set: { startDate = $0 }), displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 140)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(String(localized: "截止日期"))
                        .font(.system(size: 12, weight: .medium))
                    DatePicker("", selection: Binding(
                        get: { dueDate ?? startDate ?? Date() },
                        set: { dueDate = $0 }), displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 140)
                }
                Button(String(localized: "清除")) {
                    startDate = nil
                    dueDate = nil
                    dateError = nil
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
            if let dateError {
                Text(dateError).font(.system(size: 11)).foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(String(localized: "说明（可选）"))
                    .font(.system(size: 12, weight: .medium))
                TextEditor(text: $summary)
                    .font(.system(size: 12))
                    .frame(height: 60)
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor).opacity(0.4)))
            }

            HStack {
                Spacer()
                Button(String(localized: "取消"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(parentTaskID == nil ? String(localized: "创建") : String(localized: "添加"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmedForStorage.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 440)
    }

    private func save() {
        guard !title.trimmedForStorage.isEmpty else { return }
        let start = startDate.map(CalendarDate.from(localNoon:))
        let due = dueDate.map(CalendarDate.from(localNoon:))
        if let start, let due, start > due {
            dateError = String(localized: "开始日期不能晚于截止日期")
            return
        }

        if let parentTaskID {
            // The conversion flow lives in AddSubtaskFlowSheet; plain create
            // here only applies to tasks that are already summaries.
            _ = vm.createTask(title: title,
                              projectID: selectedProjectID,
                              parentTaskID: parentTaskID,
                              priority: priority,
                              startDate: start,
                              dueDate: due,
                              summary: summary)
        } else {
            _ = vm.createTask(title: title,
                              projectID: selectedProjectID,
                              priority: priority,
                              startDate: start,
                              dueDate: due,
                              summary: summary)
        }
        dismiss()
    }
}

// MARK: - Add subtask with first-subtask conversion (PRD 7.4, design C03)

/// Adding the first subtask to a scheduled/non-todo task changes its meaning.
/// The explanation sheet must be accepted before the subtask form opens.
struct AddSubtaskFlowSheet: View {
    @EnvironmentObject private var vm: ProjectWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    let parentTaskID: UUID

    @State private var stage: Stage = .explanation
    @State private var title = ""

    enum Stage {
        case explanation
        case form
    }

    var body: some View {
        Group {
            switch stage {
            case .explanation:
                explanationView
            case .form:
                formView
            }
        }
        .padding(18)
        .frame(width: 400)
        .onAppear {
            if !vm.needsConversionConfirmation(for: parentTaskID) {
                stage = .form
            }
        }
    }

    private var explanationView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(String(localized: "改为汇总任务"), systemImage: "arrow.triangle.branch")
                .font(.system(size: 14, weight: .semibold))

            if let plan = vm.conversionPlan(for: parentTaskID) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "添加子任务后，「\(vm.task(parentTaskID)?.title ?? "")」将变为汇总任务："))
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    bullet(String(localized: "原状态和排期转交给首个子任务"))
                    bullet(String(localized: "汇总状态与日期此后由子任务推导"))
                    bullet(String(localized: "标题、说明和优先级保持可编辑"))
                    if plan.inheritedStatus == .completed {
                        bullet(String(localized: "首个子任务将保持已完成，可在表单中修改"))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button(String(localized: "取消"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "继续")) { stage = .form }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle().fill(Color.secondary).frame(width: 4, height: 4).padding(.top, 5)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var formView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "添加子任务"))
                .font(.system(size: 15, weight: .semibold))

            TextField(String(localized: "子任务标题"), text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit(add)

            HStack {
                Spacer()
                Button(String(localized: "取消"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "添加"), action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmedForStorage.isEmpty)
            }
        }
    }

    private func add() {
        guard !title.trimmedForStorage.isEmpty else { return }
        let needsConversion = vm.needsConversionConfirmation(for: parentTaskID)
        let created: ProjectTask?
        if needsConversion {
            created = vm.addFirstSubtaskAfterConversion(parentID: parentTaskID, childTitle: title)
        } else {
            created = vm.createTask(title: title,
                                    projectID: vm.task(parentTaskID)?.projectID,
                                    parentTaskID: parentTaskID)
        }
        if let created {
            ProjectsWindowState.shared.expandedTaskIDs.insert(parentTaskID)
            ProjectsWindowState.shared.detailTaskID = created.id
        }
        dismiss()
    }
}
