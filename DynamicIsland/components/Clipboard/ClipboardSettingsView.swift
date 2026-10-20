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
                Toggle(String(localized: "Enable Clipboard"), isOn: $store.enabled)
            } footer: {
                Text(String(localized: "Turning this off stops recording, closes the panel, and disables its shortcut. Existing history is kept."))
            }
            Section("Permissions") {
                SettingsPermissionRow(title: String(localized: "Clipboard Access"), message: String(localized: "Required to record copied items. Allow Eave under “Paste from Other Apps” in System Settings."),
                                      state: readPermission, request: {
                    store.requestReadAccess()
                    refreshPermissions()
                }, openSettings: {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                }).disabled(!store.enabled)
                AccessibilitySettingsPermissionRow(message: String(localized: "Required to paste directly into the current app. Not needed when only copying to the clipboard."))
            }
            Group {
                Section {
                    Toggle(String(localized: "Sound effects"), isOn: $store.soundEffects)
                    Toggle(String(localized: "Pause recording"), isOn: $store.paused)
                    KeyboardShortcuts.Recorder(String(localized: "Open Clipboard:"), name: .toggleClipboard)
                        .disabled(!shortcutsEnabled)
                }
                Section(String(localized: "Paste Items")) {
                    Picker(String(localized: "Paste to"), selection: $store.pasteTarget) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "To the Active App"))
                            Text(String(localized: "Paste the selected item directly into the app you were using before opening the panel."))
                                .font(.caption).foregroundStyle(.secondary)
                        }.tag(ClipboardPasteTarget.activeApplication)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "To the Clipboard"))
                            Text(String(localized: "Copy the selected item to the system clipboard to paste manually later."))
                                .font(.caption).foregroundStyle(.secondary)
                        }.tag(ClipboardPasteTarget.clipboard)
                    }.pickerStyle(.radioGroup).labelsHidden()
                    Toggle(String(localized: "Always paste as plain text"), isOn: $store.alwaysPlainText)
                    Text(String(localized: "Plain text mode removes formatting. Images without text cannot be pasted as plain text."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(String(localized: "Keep History")) {
                    VStack(spacing: 12) {
                        Slider(value: $retentionPosition, in: 0...4) { editing in
                            if !editing {
                                let value = ClipboardRetention.atSliderPosition(retentionPosition)
                                store.retention = value
                                retentionPosition = value.sliderPosition
                            }
                        }.labelsHidden()
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(String(localized: "History retention period"))
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
                    Text(String(localized: "Items pinned to favorites or collections do not expire automatically. Shortening the period immediately deletes expired unpinned items. “Forever” is still subject to item and storage limits."))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(String(localized: "\(store.history.entries.count) items")).foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "Delete History…"), role: .destructive) { confirmClear = true }
                            .disabled(store.busy || store.history.entries.isEmpty)
                    }
                }
                Section(String(localized: "Storage")) {
                    Picker(String(localized: "Unpinned item limit"), selection: $store.itemLimit) {
                        ForEach([100, 300, 500, 1000], id: \.self) { Text(String(localized: "\($0) items")).tag($0) }
                    }
                    Picker(String(localized: "Storage limit"), selection: $store.capacityMB) {
                        ForEach([50, 100, 250, 500], id: \.self) { Text("\($0) MB").tag($0) }
                    }
                    Text(String(localized: "Up to 20 MB per copy. Copied files are not recorded yet."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(String(localized: "Privacy")) {
                    Text(String(localized: "Excluded app bundle IDs (one per line)")).font(.caption)
                    TextEditor(text: $store.excludedApps).font(.system(.caption, design: .monospaced)).frame(height: 70)
                    Text(String(localized: "Content marked as sensitive or transient is not saved. Unmarked sensitive content may still be recorded; exclude apps or pause recording as needed."))
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
        .alert(String(localized: "Delete all clipboard history?"), isPresented: $confirmClear) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Delete History"), role: .destructive) { store.clear() }
        } message: { Text(String(localized: "This includes favorites and items in collections and cannot be undone. Collection names will be kept.")) }
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
