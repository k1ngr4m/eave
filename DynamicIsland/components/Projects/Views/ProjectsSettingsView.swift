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

import KeyboardShortcuts
import SwiftUI

/// Settings page for the projects module: shortcut recorder, data management
/// (export / restore / open location) and recovery entry points (PRD 5.1, 13.4).
struct ProjectsSettingsView: View {
    @EnvironmentObject private var vm: ProjectWorkspaceViewModel
    @State private var restoreResult: RestoreResult?
    @State private var restorePreview: ProjectWorkspace?
    @State private var restoreSourceURL: URL?

    struct RestoreResult: Identifiable {
        let id = UUID()
        let success: Bool
        let message: String
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(String(localized: "打开项目与任务"))
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .openProjectTasks)
                }
                Text(String(localized: "打开项目与任务窗口的全局快捷键，默认不绑定，受快捷键总开关控制。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(String(localized: "快捷键"))
            }

            Section {
                LabeledContent(String(localized: "当前数据")) {
                    Text(String(localized: "\(vm.workspace.projects.count) 个项目 · \(vm.workspace.tasks.count) 个任务"))
                        .foregroundStyle(.secondary)
                }
                Button(String(localized: "导出备份…")) { exportWorkspace() }
                Button(String(localized: "从备份恢复…")) { pickAndPreviewRestore() }
                Button(String(localized: "打开数据位置")) { revealDataLocation() }
                if case .corrupted(let reason) = vm.loadState {
                    Label(String(localized: "数据读取失败：\(reason)"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Button(String(localized: "从备份恢复工作区")) { pickAndPreviewRestore() }
                }
            } header: {
                Text(String(localized: "数据"))
            } footer: {
                Text(String(localized: "数据保存在本机 Application Support/Eave/Projects/workspace.json，导出使用带版本号的 JSON。恢复采用整体替换，恢复前会先保存当前副本。"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            restorePreviewTitle,
            isPresented: Binding(get: { restorePreview != nil },
                                 set: { if !$0 { restorePreview = nil; restoreSourceURL = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "替换当前工作区"), role: .destructive) { performRestore() }
            Button(String(localized: "取消"), role: .cancel) {
                restorePreview = nil
                restoreSourceURL = nil
            }
        } message: {
            if let preview = restorePreview {
                Text(String(localized: "备份包含 \(preview.projects.count) 个项目、\(preview.tasks.count) 个任务。确认后当前工作区将被整体替换，撤销历史会清空。"))
            }
        }
        .alert(restoreResult?.message ?? "",
               isPresented: Binding(get: { restoreResult != nil && !restoreResult!.success },
                                    set: { if !$0 { restoreResult = nil } })) {
            Button(String(localized: "好"), role: .cancel) { restoreResult = nil }
        }
    }

    private var restorePreviewTitle: String {
        String(localized: "从备份恢复")
    }

    private func exportWorkspace() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Eave-Projects-Export.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            _ = vm.exportWorkspace(to: url)
        }
    }

    private func pickAndPreviewRestore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            switch ProjectWorkspaceStore.shared.readBackup(at: url) {
            case .success(let workspace):
                restorePreview = workspace
                restoreSourceURL = url
            case .failure(let error):
                restoreResult = RestoreResult(success: false, message: error.localizedDescription)
            }
        }
    }

    private func performRestore() {
        guard let url = restoreSourceURL else { return }
        let result = vm.restoreFromBackup(at: url)
        switch result {
        case .success:
            restoreResult = RestoreResult(success: true, message: String(localized: "已恢复工作区"))
        case .failure(let message):
            restoreResult = RestoreResult(success: false, message: message)
        }
        restorePreview = nil
        restoreSourceURL = nil
    }

    private func revealDataLocation() {
        NSWorkspace.shared.activateFileViewerSelecting([ProjectWorkspaceStore.shared.fileURL])
    }
}
