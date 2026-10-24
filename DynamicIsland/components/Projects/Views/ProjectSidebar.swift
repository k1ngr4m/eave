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

/// Fixed 200 pt sidebar: aggregates, project list with colored dots, archive
/// and the new-project action (PRD 5.4, design S/G01).
struct ProjectSidebar: View {
    @EnvironmentObject private var vm: ProjectWorkspaceViewModel
    @ObservedObject var uiState = ProjectsWindowState.shared
    @Binding var newProjectSheetPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    sidebarRow(icon: "tray", title: String(localized: "收集箱"),
                               count: vm.inboxCount, isSelected: isCurrent(.inbox)) {
                        uiState.select(.inbox)
                    }
                    sidebarRow(icon: "sun.max", title: String(localized: "今日"),
                               count: vm.todayTotalCount, isSelected: isCurrent(.today)) {
                        uiState.select(.today)
                    }
                    sidebarRow(icon: "square.stack.3d.up", title: String(localized: "全部任务"),
                               count: vm.allTasksCount, isSelected: isCurrent(.allTasks)) {
                        uiState.select(.allTasks)
                    }

                    sectionHeader(String(localized: "项目"))

                    ForEach(activeProjects) { project in
                        projectRow(project)
                    }

                    sectionHeader(String(localized: "已归档"))
                    sidebarRow(icon: "archivebox", title: String(localized: "已归档"),
                               count: archivedProjects.count, isSelected: isCurrent(.archived)) {
                        uiState.select(.archived)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    newProjectSheetPresented = true
                } label: {
                    Label(String(localized: "新项目"), systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                .accessibilityLabel(String(localized: "新建项目"))

                saveIndicator
            }
            .padding(10)
        }
        .frame(width: 200)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var activeProjects: [Project] {
        vm.workspace.projects.filter { !$0.isArchived }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    private var archivedProjects: [Project] {
        vm.workspace.projects.filter(\.isArchived)
    }

    private func isCurrent(_ navigation: ProjectsNavigation) -> Bool {
        uiState.selection == navigation
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 10)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private func sidebarRow(icon: String, title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func projectRow(_ project: Project) -> some View {
        let progress = TaskRules.projectProgress(projectID: project.id, tasks: vm.workspace.tasks)
        return Button {
            uiState.select(.project(project.id))
        } label: {
            HStack(spacing: 8) {
                ProjectDot(colorHex: project.colorHex)
                    .frame(width: 16)
                Text(project.title)
                    .font(.system(size: 13, weight: isCurrent(.project(project.id)) ? .medium : .regular))
                    .foregroundStyle(isCurrent(.project(project.id)) ? Color.accentColor : .primary)
                    .lineLimit(1)
                Spacer()
                if progress.total > 0 {
                    Text("\(progress.completed)/\(progress.total)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isCurrent(.project(project.id)) ? Color.accentColor.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(String(localized: "编辑项目")) {
                uiState.select(.project(project.id))
                NotificationCenter.default.post(name: .projectsEditProjectRequested, object: project.id)
            }
            Button(String(localized: "归档项目")) { vm.archiveProject(project.id) }
        }
        .accessibilityAddTraits(isCurrent(.project(project.id)) ? .isSelected : [])
    }

    @ViewBuilder
    private var saveIndicator: some View {
        switch vm.saveState {
        case .saved:
            HStack(spacing: 5) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text(String(localized: "本地已保存"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 10)
        case .saving:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(String(localized: "保存中"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 10)
        case .failed:
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                Text(String(localized: "未保存，重试"))
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .onTapGesture {
                        _ = vm.flushPendingSave()
                    }
            }
            .padding(.leading, 10)
            .help(String(localized: "保存失败，点击重试"))
        }
    }
}

extension Notification.Name {
    static let projectsEditProjectRequested = Notification.Name("projectsEditProjectRequested")
}
