// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Defaults
import EaveStatus
import KeyboardShortcuts
import SwiftUI

struct ClipboardSettingsView: View {
    @ObservedObject var store = ClipboardHistoryStore.shared
    @Default(.enableShortcuts) private var shortcutsEnabled
    @State private var retentionPosition = ClipboardRetention.month.sliderPosition
    @State private var confirmClear = false
    @State private var readPermission: SettingsPermissionState = .unknown

    var body: some View {
        Form {
            Section {
                Toggle("启用剪贴板", isOn: $store.enabled)
            } footer: {
                Text("关闭后停止记录、关闭面板并禁用呼出快捷键，已有历史保留。")
            }
            Section("Permissions") {
                SettingsPermissionRow(title: "读取剪贴板", message: "用于记录复制历史。请在系统设置的“从其他 App 粘贴”中允许 Eave 读取。",
                                      state: readPermission, request: {
                    store.requestReadAccess()
                    refreshPermissions()
                }, openSettings: {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                }).disabled(!store.enabled)
                AccessibilitySettingsPermissionRow(message: "用于将选中内容直接粘贴到当前应用；仅复制到剪贴板时不需要。")
            }
            Group {
                Section {
                    Toggle("音效", isOn: $store.soundEffects)
                    Toggle("暂停记录", isOn: $store.paused)
                    KeyboardShortcuts.Recorder("打开剪贴板：", name: .toggleClipboard)
                        .disabled(!shortcutsEnabled)
                }
                Section("粘贴项目") {
                    Picker("粘贴到", selection: $store.pasteTarget) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("到当前活动应用")
                            Text("将选定的项目直接粘贴到打开面板前正在使用的应用程序中。")
                                .font(.caption).foregroundStyle(.secondary)
                        }.tag(ClipboardPasteTarget.activeApplication)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("到剪贴板")
                            Text("将选定的项目复制到系统剪贴板，以便稍后手动粘贴。")
                                .font(.caption).foregroundStyle(.secondary)
                        }.tag(ClipboardPasteTarget.clipboard)
                    }.pickerStyle(.radioGroup).labelsHidden()
                    Toggle("始终以纯文本粘贴", isOn: $store.alwaysPlainText)
                    Text("纯文本模式会移除文字格式；不含文字的图片无法以纯文本粘贴。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("保留历史") {
                    VStack(spacing: 12) {
                        Slider(value: $retentionPosition, in: 0...4) { editing in
                            if !editing {
                                let value = ClipboardRetention.atSliderPosition(retentionPosition)
                                store.retention = value
                                retentionPosition = value.sliderPosition
                            }
                        }.labelsHidden()
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("历史保留期限")
                            .accessibilityValue(ClipboardRetention.atSliderPosition(retentionPosition).title)
                        GeometryReader { geometry in
                            ForEach(0..<5) { index in
                                Circle().fill(.secondary.opacity(0.5)).frame(width: 3, height: 3)
                                    .position(x: 12 + (geometry.size.width - 24) * Double(index) / 4, y: 2)
                            }
                        }.frame(height: 4).accessibilityHidden(true)
                        Text(ClipboardRetention.atSliderPosition(retentionPosition).title)
                            .frame(maxWidth: .infinity)

                    }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    Text("收藏不自动过期。缩短期限将立即删除过期的普通历史；“永久”仍受条数和容量上限约束。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("\(store.history.entries.count) 条记录").foregroundStyle(.secondary)
                        Spacer()
                        Button("删除历史…", role: .destructive) { confirmClear = true }
                            .disabled(store.busy || store.history.entries.isEmpty)
                    }
                }
                Section("容量") {
                    Picker("普通历史上限", selection: $store.itemLimit) {
                        ForEach([100, 300, 500, 1000], id: \.self) { Text("\($0) 条").tag($0) }
                    }
                    Picker("内容容量上限", selection: $store.capacityMB) {
                        ForEach([50, 100, 250, 500], id: \.self) { Text("\($0) MB").tag($0) }
                    }
                    Text("单次复制最多 20 MB；文件复制暂不记录。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("隐私") {
                    Text("排除的应用 Bundle ID（每行一个）").font(.caption)
                    TextEditor(text: $store.excludedApps).font(.system(.caption, design: .monospaced)).frame(height: 70)
                    Text("带有敏感或临时标记的内容不会保存。未标记的敏感内容仍可能被记录，请按需排除应用或暂停。")
                        .font(.caption).foregroundStyle(.secondary)

                }
            }.disabled(!store.enabled)
            if let message = store.message {
                Section { Text(message).font(.caption).foregroundStyle(.orange) }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            retentionPosition = store.retention.sliderPosition
            store.start()
            refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .onChange(of: store.retention) { _, value in retentionPosition = value.sliderPosition }
        .onChange(of: store.itemLimit) { _, _ in store.applyLimits() }
        .onChange(of: store.capacityMB) { _, _ in store.applyLimits() }
        .alert("删除所有剪贴板历史？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) {}
            Button("删除历史", role: .destructive) { store.clear() }
        } message: { Text("包括收藏和分类中的内容，删除后无法恢复。分类名称会保留。") }
    }

    private func refreshPermissions() {
        if #available(macOS 15.4, *) {
            switch NSPasteboard.general.accessBehavior {
            case .default: readPermission = .notDetermined
            case .ask: readPermission = .limited
            case .alwaysAllow: readPermission = .granted
            case .alwaysDeny: readPermission = .denied
            @unknown default: readPermission = .unknown
            }
        } else {
            readPermission = .granted
        }
    }
}
