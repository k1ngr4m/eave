// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

struct ClipboardItemSheet: View {
    let entry: ClipboardEntry
    let action: ClipboardPanelController.ItemPresentation.Action
    @ObservedObject var store: ClipboardHistoryStore
    let onSaved: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var image: NSImage?
    @State private var saving = false
    @State private var error: String?

    private var title: String {
        switch action {
        case .edit: String(localized: "Edit Item")
        case .rename: String(localized: "Rename Item")
        case .preview: entry.name ?? String(localized: "Preview")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            switch action {
            case .rename:
                TextField(String(localized: "Item name"), text: $draft).textFieldStyle(.roundedBorder)
                    .onSubmit { save() }
                Text(String(localized: "The name is only a label; copied content stays unchanged. Leave it empty to restore the default name."))
                    .font(.caption).foregroundStyle(.secondary)
            case .edit:
                TextEditor(text: $draft).font(.body).frame(minHeight: 280)
                    .accessibilityLabel(String(localized: "Item content"))
                Text(String(localized: "Saving replaces this item's content with plain text."))
                    .font(.caption).foregroundStyle(.secondary)
            case .preview:
                if entry.kind == .image {
                    if let image {
                        ScrollView([.horizontal, .vertical]) { Image(nsImage: image) }
                            .frame(minHeight: 280, maxHeight: 420)
                    } else if error == nil { ProgressView().frame(maxWidth: .infinity, minHeight: 280) }
                } else {
                    ScrollView {
                        Text(entry.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }.frame(minHeight: 280, maxHeight: 420)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button(action == .preview ? String(localized: "Done") : String(localized: "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(saving)
                if action != .preview {
                    Button(String(localized: "Save")) { save() }.keyboardShortcut(.defaultAction)
                        .disabled(store.busy || saving)
                }
            }
        }
        .padding(24).frame(width: action == .rename ? 420 : 640)
        .interactiveDismissDisabled(saving)
        .task {
            draft = action == .rename ? (entry.name ?? "") : entry.text
            if action == .preview && entry.kind == .image {
                do {
                    let payload = try await store.disk.payload(entry.id)
                    guard let data = payload.imageData, let loaded = NSImage(data: data) else {
                        error = String(localized: "Could not preview this image.")
                        return
                    }
                    image = loaded
                } catch { self.error = error.localizedDescription }
            }
        }
    }

    private func save() {
        guard !store.busy, !saving else { return }
        if action == .rename {
            let name = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
            store.update(entry.id) { $0.name = name.isEmpty ? nil : name }
            onSaved(entry.id)
        } else if action == .edit {
            saving = true
            Task {
                defer { saving = false }
                if let id = await store.editText(entry.id, text: draft) { onSaved(id) }
                else { error = store.message ?? String(localized: "Could not save changes.") }
            }
        }
    }
}
