// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardIgnoredAppsView: View {
    @ObservedObject var store: ClipboardHistoryStore
    @State private var selectedID: String?
    @State private var pickerError: String?

    var body: some View {
        VStack(spacing: 0) {
            if store.excludedApplicationIDs.isEmpty {
                Text(String(localized: "No ignored applications"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 64)
            } else {
                List(store.excludedApplicationIDs, id: \.self, selection: $selectedID) { id in
                    IgnoredAppRow(bundleID: id).tag(id)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .frame(height: min(240, CGFloat(store.excludedApplicationIDs.count) * 52))
            }
            Divider()
            HStack(spacing: 12) {
                Button(action: chooseApplications) { Image(systemName: "plus").frame(width: 20, height: 20) }
                    .help(String(localized: "Add Application"))
                    .accessibilityLabel(String(localized: "Add Application"))
                Divider().frame(height: 18)
                Button {
                    if let selectedID { store.removeIgnoredApplication(selectedID) }
                    selectedID = nil
                } label: { Image(systemName: "minus").frame(width: 20, height: 20) }
                    .disabled(selectedID == nil)
                    .help(String(localized: "Remove Selected Application"))
                    .accessibilityLabel(String(localized: "Remove Selected Application"))
                Spacer()
            }.buttonStyle(.plain).padding(.horizontal, 8).padding(.vertical, 6)
            if let pickerError {
                Text(pickerError).font(.caption).foregroundStyle(.orange).padding(8)
            }
        }.frame(maxWidth: .infinity)
        .onChange(of: store.excludedApplicationIDs) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        }
    }

    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Add Ignored Applications")
        panel.prompt = String(localized: "Add")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { !$0.isEmpty }
            store.ignoreApplications(ids)
            selectedID = ids.last ?? selectedID
            pickerError = ids.count == panel.urls.count ? nil : String(localized: "Some applications could not be added because their bundle identifier is missing.")
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}

private struct IgnoredAppRow: View {
    let bundleID: String
    @State private var name: String?
    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            if let icon { Image(nsImage: icon).resizable().frame(width: 32, height: 32) }
            else { Image(systemName: "app.dashed").font(.system(size: 28)).frame(width: 32, height: 32).foregroundStyle(.secondary) }
            Text(name ?? bundleID).lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 4).contentShape(Rectangle()).help(bundleID)
        .task(id: bundleID) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "", options: [.anchored, .backwards], range: nil)
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }
    }
}
