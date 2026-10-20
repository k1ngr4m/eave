// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

struct ClipboardPanelView: View {
    @ObservedObject var controller: ClipboardPanelController
    @ObservedObject var store: ClipboardHistoryStore
    @Default(.accentColor) private var accentColor
    @FocusState private var searchFocused: Bool
    @State private var collectionName = ""
    @State private var editingCollectionID: UUID?
    @State private var pinToNewCollection: UUID?
    @State private var confirmClear = false

    private var entries: [ClipboardEntry] { controller.visibleEntries }

    var body: some View {
        VStack(spacing: 14) {
            toolbar
            if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: controller.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                        .font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
                    Text(controller.query.isEmpty ? String(localized: "Copy something to see it here") : String(localized: "No matching items"))
                        .font(.headline)
                    Text(String(localized: "Text, links, images, and files · Stored only on this Mac")).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 16) {
                            ForEach(entries) { entry in
                                ClipboardCard(entry: entry, selected: controller.selectedID == entry.id,
                                              accent: accentColor, disk: store.disk)
                                    .id(entry.id)
                                    .onTapGesture(count: 2) { controller.paste(entry.id) }
                                    .simultaneousGesture(TapGesture().onEnded {
                                        controller.selectedID = entry.id
                                        searchFocused = true
                                    })
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction { controller.paste(entry.id) }
                                    .contextMenu { itemMenu(entry) }
                            }
                        }.padding(4)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: controller.keyboardSelectionID) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
            HStack(spacing: 10) {
                if let message = store.message {
                    Text(message).lineLimit(2).foregroundStyle(.orange)
                } else {
                    Circle().fill(store.paused ? Color.orange : Color.green).frame(width: 5, height: 5)
                    Text(store.paused ? String(localized: "Recording paused") : String(localized: "\(store.history.entries.count) items"))
                    if store.busy { ProgressView().controlSize(.mini) }
                    Spacer()
                    Text(store.pasteTarget == .clipboard ? String(localized: "← → Select   ↩ Copy   ⇧↩ Plain text   esc Close") : String(localized: "← → Select   ↩ Paste   ⇧↩ Plain text   esc Close"))
                }
            }.font(.system(size: 11)).foregroundStyle(.secondary).frame(height: 20)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 24).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 24).fill(Color.black.opacity(0.52)))
        }
        .preferredColorScheme(.dark)
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .tint(accentColor)
        .onAppear { searchFocused = true }
        .onChange(of: controller.settingsPresented) { _, presented in if !presented { searchFocused = true } }
        .onChange(of: controller.collectionPresented) { _, presented in if !presented { searchFocused = true } }
        .onChange(of: controller.query) { _, _ in controller.selectFirstIfNeeded() }
        .onChange(of: controller.sourceID) { _, _ in controller.selectFirstIfNeeded() }
        .onChange(of: store.history.entries) { _, _ in controller.selectFirstIfNeeded() }
        .sheet(item: $controller.itemPresentation) { presentation in
            if let entry = store.history.entries.first(where: { $0.id == presentation.id }) {
                ClipboardItemSheet(entry: entry, action: presentation.action, store: store) { id in
                    controller.selectedID = id
                    controller.itemPresentation = nil
                }
            }
        }
        .onChange(of: controller.itemPresentation?.id) { _, id in if id == nil { searchFocused = true } }
        .sheet(isPresented: $controller.settingsPresented) { settings }
        .sheet(isPresented: $controller.collectionPresented) { collectionEditor }
        .alert(String(localized: "Clear all clipboard history?"), isPresented: $confirmClear) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Clear"), role: .destructive) { store.clear() }
        } message: { Text(String(localized: "This includes favorites and cannot be undone. Collection names will be kept.")) }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(String(localized: "Search clipboard"), text: $controller.query)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel(String(localized: "Search clipboard history"))
                if !controller.query.isEmpty {
                    Button { controller.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(String(localized: "Clear search"))
                }
            }.frame(width: 190)
            Divider().frame(height: 18)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    tab(String(localized: "Clipboard"), icon: "clock.arrow.circlepath", active: controller.collectionID == nil && !controller.favoritesOnly) {
                        controller.collectionID = nil; controller.favoritesOnly = false
                    }
                    tab(String(localized: "Favorites"), icon: "star.fill", active: controller.favoritesOnly) {
                        controller.collectionID = nil; controller.favoritesOnly = true
                    }
                    ForEach(store.history.collections) { collection in
                        tab(collection.name, icon: "circle.fill", color: (collection.color ?? .red).tint, active: controller.collectionID == collection.id) {
                            controller.collectionID = collection.id; controller.favoritesOnly = false
                        }.contextMenu {
                            Button(String(localized: "Rename…"), systemImage: "pencil") {
                                editingCollectionID = collection.id
                                collectionName = collection.name
                                controller.collectionPresented = true
                            }.disabled(store.busy)
                            Button(String(localized: "Delete Collection"), role: .destructive) {
                                if controller.collectionID == collection.id { controller.collectionID = nil }
                                store.deleteCollection(collection.id)
                            }.disabled(store.busy)
                            Divider()
                            Picker(String(localized: "Color"), selection: Binding(
                                get: { collection.color ?? .red },
                                set: { store.setCollectionColor(collection.id, to: $0) }
                            )) {
                                ForEach(ClipboardCollection.Tint.allCases, id: \.self) { color in
                                    Image(nsImage: color.swatch).renderingMode(.original)
                                        .accessibilityLabel(color.title)
                                        .tag(color)
                                }
                            }.pickerStyle(.palette).disabled(store.busy)
                        }
                    }
                    Button { pinToNewCollection = nil; editingCollectionID = nil; collectionName = ""; controller.collectionPresented = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain).help(String(localized: "New Collection")).accessibilityLabel(String(localized: "New Collection"))
                }
            }.scrollIndicators(.hidden)
            Menu {
                Button(String(localized: "All Sources")) { controller.sourceID = "" }
                let sources = Dictionary(store.history.entries.map { ($0.sourceBundleID, $0.sourceName) }, uniquingKeysWith: { first, _ in first })
                ForEach(sources.keys.sorted(), id: \.self) { id in
                    Button(sources[id] ?? id) { controller.sourceID = id }
                }
            } label: {
                Image(systemName: controller.sourceID.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }.menuStyle(.borderlessButton).fixedSize().help(String(localized: "Filter by source app"))
            Menu {
                Toggle(String(localized: "Pause recording"), isOn: $store.paused)
                Button(String(localized: "Clipboard Settings…")) { controller.settingsPresented = true }
                Divider()
                Button(String(localized: "Clear History…"), role: .destructive) { confirmClear = true }.disabled(store.busy)
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize().help(String(localized: "More actions"))
        }.frame(height: 30)
    }

    private func tab(_ title: String, icon: String, color: Color? = nil, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action(); controller.selectFirstIfNeeded(); searchFocused = true
        } label: {
            Label { Text(title) } icon: {
                Image(systemName: icon).foregroundStyle(color ?? .primary)
            }.font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(active ? Color.primary.opacity(0.10) : .clear, in: Capsule())
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func itemMenu(_ entry: ClipboardEntry) -> some View {
        Button(controller.pasteActionTitle, systemImage: "return") { controller.paste(entry.id) }
            .keyboardShortcut(.return, modifiers: []).disabled(controller.pasting)
        Button(String(localized: "Paste as Plain Text"), systemImage: "textformat") { controller.paste(entry.id, plain: true) }
            .keyboardShortcut(.return, modifiers: .shift).disabled(entry.kind == .files || entry.text.isEmpty || controller.pasting)
        Button(String(localized: "Copy"), systemImage: "doc.on.doc") { Task { _ = await store.copy(entry.id, plain: false) } }
            .keyboardShortcut("c")
        if store.ocrEnabled, let text = entry.recognizedText, !text.isEmpty {
            Button(String(localized: "Copy Recognized Text"), systemImage: "text.viewfinder") { store.copyRecognizedText(entry.id) }
        }
        if entry.kind == .files {
            Button(String(localized: "Show in Finder"), systemImage: "folder") { Task { await store.revealFiles(entry.id) } }
            Button(String(localized: "Copy File Paths"), systemImage: "link") { Task { await store.copyFilePaths(entry.id) } }
        }
        Divider()
        Button(String(localized: "Edit…"), systemImage: "pencil") { controller.presentItem(entry.id, action: .edit) }
            .keyboardShortcut("e").disabled(store.busy || !entry.isEditable)
        Button(String(localized: "Rename…"), systemImage: "rectangle.and.pencil.and.ellipsis") { controller.presentItem(entry.id, action: .rename) }
            .keyboardShortcut("r").disabled(store.busy)
        Button(String(localized: "Delete"), systemImage: "trash", role: .destructive) { store.delete(entry.id) }
            .keyboardShortcut(.delete, modifiers: []).disabled(store.busy)
        Divider()
        Menu {
            Button {
                store.update(entry.id) { $0.isFavorite.toggle() }
            } label: {
                Label(String(localized: "Favorites"), systemImage: entry.isFavorite ? "checkmark" : "star")
            }
            ForEach(store.history.collections) { collection in
                Toggle(isOn: Binding(
                    get: { entry.collectionIDs.contains(collection.id) },
                    set: { pinned in
                        store.update(entry.id) {
                            if pinned { $0.collectionIDs.insert(collection.id) }
                            else { $0.collectionIDs.remove(collection.id) }
                        }
                    }
                )) {
                    Label {
                        Text(collection.name)
                    } icon: {
                        Image(nsImage: (collection.color ?? .red).swatch).renderingMode(.original)
                    }
                }
            }
            Divider()
            Button(String(localized: "New Collection…")) { pinToNewCollection = entry.id; editingCollectionID = nil; collectionName = ""; controller.collectionPresented = true }
        } label: { Label(String(localized: "Pin"), systemImage: "pin") }
            .disabled(store.busy)
        Button(String(localized: "Preview"), systemImage: "eye") { controller.presentItem(entry.id, action: .preview) }
            .keyboardShortcut(.space, modifiers: [])
        Divider()
        Button(String(localized: "Exclude This App")) {
            if !entry.sourceBundleID.isEmpty { store.ignoreApplications([entry.sourceBundleID]) }
        }.disabled(entry.sourceBundleID.isEmpty)
    }

    private var collectionEditor: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(editingCollectionID == nil ? String(localized: "New Collection") : String(localized: "Rename Collection")).font(.headline)
            TextField(String(localized: "Collection name"), text: $collectionName).textFieldStyle(.roundedBorder)
                .onSubmit { saveCollection() }
            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { controller.collectionPresented = false }.keyboardShortcut(.cancelAction)
                Button(editingCollectionID == nil ? String(localized: "Create") : String(localized: "Save")) { saveCollection() }.keyboardShortcut(.defaultAction)
                    .disabled(!canSaveCollection || store.busy)
            }
        }.padding(24).frame(width: 340)
    }

    private var canSaveCollection: Bool {
        let name = String(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        return !name.isEmpty && !store.history.collections.contains { $0.id != editingCollectionID && $0.name == name }
    }

    private func saveCollection() {
        guard canSaveCollection, !store.busy else { return }
        if let editingCollectionID { store.renameCollection(editingCollectionID, to: collectionName) }
        else { store.addCollection(collectionName, pinning: pinToNewCollection) }
        controller.collectionPresented = false
    }

    private var settings: some View {
        VStack(spacing: 0) {
            ClipboardSettingsView(store: store)
            HStack {
                Spacer()
                Button(String(localized: "Done")) { controller.settingsPresented = false }
                    .keyboardShortcut(.defaultAction)
            }.padding(16)
        }.frame(width: 550, height: 650)
    }

}

private struct ClipboardCard: View {
    let entry: ClipboardEntry
    let selected: Bool
    let accent: Color
    let disk: ClipboardDiskStore
    @State private var thumbnail: NSImage?
    @State private var appIcon: NSImage?
    private var title: String { entry.name ?? (entry.kind == .files ? String(localized: "Files") : entry.kind == .pdf ? "PDF" : entry.kind == .image ? String(localized: "Image") : entry.kind == .link ? String(localized: "Link") : String(localized: "Text")) }
    private var sourceName: String {
        entry.sourceName.isEmpty || ["未知应用", "未知應用", "Unknown App"].contains(entry.sourceName)
            ? String(localized: "Unknown App") : entry.sourceName
    }
    private var headerColor: Color { entry.kind == .image ? Color(red: 0.02, green: 0.19, blue: 0.23) : entry.kind == .link ? Color(red: 0.26, green: 0.18, blue: 0.40) : Color(red: 0.04, green: 0.09, blue: 0.24) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(title).font(.system(size: 14, weight: .semibold))
                        if entry.isPinned { Image(systemName: "pin.fill").font(.system(size: 10)) }
                    }
                    Text(entry.timestamp.timeIntervalSinceNow > -60 ? String(localized: "Just now") : entry.timestamp.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))).font(.system(size: 10)).opacity(0.8).lineLimit(1)
                }
                Spacer()
                if let appIcon { Image(nsImage: appIcon).resizable().scaledToFit().frame(width: 36, height: 36) }
                else { Image(systemName: "app.dashed").font(.system(size: 26)).opacity(0.7) }
            }.foregroundStyle(.white).padding(.horizontal, 12).frame(height: 54).background(headerColor)
            ZStack(alignment: .topLeading) {
                Color(red: 0.07, green: 0.075, blue: 0.085)
                if entry.kind == .image {
                    if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit().padding(8).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
                } else if entry.kind == .pdf {
                    Image(systemName: "doc.richtext").font(.system(size: 64)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entry.kind == .files {
                    VStack(alignment: .leading, spacing: 12) {
                        if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit().frame(width: 48, height: 48) }
                        else { Image(systemName: "doc.on.doc").font(.largeTitle) }
                        Text(entry.text).font(.system(size: 13)).lineLimit(5)
                    }.padding(12)
                } else {
                    Text(String(entry.text.prefix(1800))).font(.system(size: 13)).lineSpacing(3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(12).clipped()
                }
            }.frame(maxHeight: .infinity)
            HStack {
                Text(sourceName).lineLimit(1)
                Spacer(minLength: 8)
                Text(entry.localizedDetail).lineLimit(1)
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 12)
                .frame(height: 27).background(Color(red: 0.07, green: 0.075, blue: 0.085))
        }
        .frame(width: 232, height: 236)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? accent : Color.primary.opacity(0.06), lineWidth: selected ? 3 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, sourceName, String(entry.text.prefix(160)), entry.localizedDetail].joined(separator: ", "))
        .accessibilityValue(selected ? String(localized: "Selected") : "")
        .task(id: entry.id) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.sourceBundleID) {
                appIcon = NSWorkspace.shared.icon(forFile: url.path)
            }
            if entry.kind == .files, let payload = try? await disk.payload(entry.id), let file = payload.files?.first {
                thumbnail = NSWorkspace.shared.icon(forFile: file.url.path)
            }
            if entry.kind == .image, let data = await disk.thumbnail(entry.id), !Task.isCancelled {
                thumbnail = NSImage(data: data)
            }
        }
    }
}

private extension ClipboardCollection.Tint {
    var swatch: NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor(self.tint).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    var tint: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .gray: .gray
        }
    }
}
