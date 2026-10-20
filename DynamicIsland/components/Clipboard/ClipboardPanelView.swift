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
    @State private var confirmClear = false

    private var entries: [ClipboardEntry] { controller.visibleEntries }

    var body: some View {
        VStack(spacing: 14) {
            toolbar
            if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: controller.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                        .font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
                    Text(controller.query.isEmpty ? "复制一些内容，它们会出现在这里" : "没有找到匹配的记录")
                        .font(.headline)
                    Text("文本、链接与图片 · 仅保存在这台 Mac 上").font(.caption).foregroundStyle(.secondary)
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
                                    .onTapGesture { controller.selectedID = entry.id; searchFocused = true }
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction { controller.paste(entry.id) }
                                    .contextMenu { itemMenu(entry) }
                            }
                        }.padding(4)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: controller.selectedID) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
            HStack(spacing: 10) {
                if let message = store.message {
                    Text(message).lineLimit(2).foregroundStyle(.orange)
                } else {
                    Circle().fill(store.paused ? Color.orange : Color.green).frame(width: 5, height: 5)
                    Text(store.paused ? "记录已暂停" : "\(store.history.entries.count) 条记录")
                    if store.busy { ProgressView().controlSize(.mini) }
                    Spacer()
                    Text(store.pasteTarget == .clipboard ? "← → 选择   ↩ 复制   ⇧↩ 纯文本   esc 关闭" : "← → 选择   ↩ 粘贴   ⇧↩ 纯文本   esc 关闭")
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
        .sheet(isPresented: $controller.settingsPresented) { settings }
        .sheet(isPresented: $controller.collectionPresented) { collectionEditor }
        .alert("清空所有剪贴板历史？", isPresented: $confirmClear) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { store.clear() }
        } message: { Text("包括收藏的内容，删除后无法恢复。分类名称会保留。") }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索剪贴板", text: $controller.query)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("搜索剪贴板历史")
                if !controller.query.isEmpty {
                    Button { controller.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("清除搜索")
                }
            }.frame(width: 190)
            Divider().frame(height: 18)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    tab("剪贴板", icon: "clock.arrow.circlepath", active: controller.collectionID == nil && !controller.favoritesOnly) {
                        controller.collectionID = nil; controller.favoritesOnly = false
                    }
                    tab("收藏", icon: "star.fill", active: controller.favoritesOnly) {
                        controller.collectionID = nil; controller.favoritesOnly = true
                    }
                    ForEach(store.history.collections) { collection in
                        tab(collection.name, icon: "circle.fill", active: controller.collectionID == collection.id) {
                            controller.collectionID = collection.id; controller.favoritesOnly = false
                        }.contextMenu {
                            Button("删除分类", role: .destructive) {
                                if controller.collectionID == collection.id { controller.collectionID = nil }
                                store.deleteCollection(collection.id)
                            }.disabled(store.busy)
                        }
                    }
                    Button { collectionName = ""; controller.collectionPresented = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain).help("新建分类").accessibilityLabel("新建分类")
                }
            }.scrollIndicators(.hidden)
            Menu {
                Button("全部来源") { controller.sourceID = "" }
                let sources = Dictionary(store.history.entries.map { ($0.sourceBundleID, $0.sourceName) }, uniquingKeysWith: { first, _ in first })
                ForEach(sources.keys.sorted(), id: \.self) { id in
                    Button(sources[id] ?? id) { controller.sourceID = id }
                }
            } label: {
                Image(systemName: controller.sourceID.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }.menuStyle(.borderlessButton).fixedSize().help("按来源应用筛选")
            Menu {
                Toggle("暂停记录", isOn: $store.paused)
                Button("剪贴板设置…") { controller.settingsPresented = true }
                Divider()
                Button("清空历史…", role: .destructive) { confirmClear = true }.disabled(store.busy)
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize().help("更多操作")
        }.frame(height: 30)
    }

    private func tab(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action(); controller.selectFirstIfNeeded(); searchFocused = true
        } label: {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(active ? Color.primary.opacity(0.10) : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func itemMenu(_ entry: ClipboardEntry) -> some View {
        Button(store.pasteTarget == .clipboard ? "复制到剪贴板" : "粘贴") { controller.paste(entry.id) }.disabled(controller.pasting)
        Button(store.pasteTarget == .clipboard ? "复制为纯文本" : "粘贴为纯文本") { controller.paste(entry.id, plain: true) }.disabled(entry.text.isEmpty || controller.pasting)
        Button("复制") { Task { _ = await store.copy(entry.id, plain: false) } }
        Divider()
        Button(entry.isFavorite ? "取消收藏" : "收藏") { store.update(entry.id) { $0.isFavorite.toggle() } }.disabled(store.busy)
        Menu("加入分类") {
            ForEach(store.history.collections) { collection in
                Button {
                    store.update(entry.id) {
                        if $0.collectionIDs.contains(collection.id) { $0.collectionIDs.remove(collection.id) }
                        else { $0.collectionIDs.insert(collection.id) }
                    }
                } label: {
                    if entry.collectionIDs.contains(collection.id) { Label(collection.name, systemImage: "checkmark") }
                    else { Text(collection.name) }
                }
            }
            Button("新建分类…") { collectionName = ""; controller.collectionPresented = true }
        }.disabled(store.busy)
        Divider()
        Button("不记录此应用") {
            if !entry.sourceBundleID.isEmpty { store.excludedApps += "\n" + entry.sourceBundleID }
        }.disabled(entry.sourceBundleID.isEmpty)
        Button("删除", role: .destructive) { store.delete(entry.id) }.disabled(store.busy)
    }

    private var collectionEditor: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("新建分类").font(.headline)
            TextField("分类名称", text: $collectionName).textFieldStyle(.roundedBorder)
                .onSubmit { addCollection() }
            HStack {
                Spacer()
                Button("取消") { controller.collectionPresented = false }.keyboardShortcut(.cancelAction)
                Button("创建") { addCollection() }.keyboardShortcut(.defaultAction)
                    .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy)
            }
        }.padding(24).frame(width: 340)
    }

    private func addCollection() {
        store.addCollection(collectionName)
        controller.collectionPresented = false
    }

    private var settings: some View {
        VStack(spacing: 0) {
            ClipboardSettingsView(store: store)
            HStack {
                Spacer()
                Button("完成") { controller.settingsPresented = false }
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
    private var title: String { entry.kind == .image ? "图片" : entry.kind == .link ? "链接" : "文本" }
    private var headerColor: Color { entry.kind == .image ? Color(red: 0.02, green: 0.19, blue: 0.23) : entry.kind == .link ? Color(red: 0.26, green: 0.18, blue: 0.40) : Color(red: 0.04, green: 0.09, blue: 0.24) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(title).font(.system(size: 14, weight: .semibold))
                        if entry.isFavorite { Image(systemName: "star.fill").font(.system(size: 10)) }
                    }
                    Text(entry.timestamp.timeIntervalSinceNow > -60 ? "刚刚" : entry.timestamp.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))).font(.system(size: 10)).opacity(0.8).lineLimit(1)
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
                } else {
                    Text(String(entry.text.prefix(1800))).font(.system(size: 13)).lineSpacing(3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(12).clipped()
                }
            }.frame(maxHeight: .infinity)
            HStack {
                Text(entry.sourceName).lineLimit(1)
                Spacer(minLength: 8)
                Text(entry.detail).lineLimit(1)
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 12)
                .frame(height: 27).background(Color(red: 0.07, green: 0.075, blue: 0.085))
        }
        .frame(width: 232, height: 236)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? accent : Color.primary.opacity(0.06), lineWidth: selected ? 3 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(entry.sourceName)，\(entry.text.prefix(160))，\(entry.detail)")
        .accessibilityValue(selected ? "已选择" : "")
        .task(id: entry.id) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.sourceBundleID) {
                appIcon = NSWorkspace.shared.icon(forFile: url.path)
            }
            if entry.kind == .image, let data = await disk.thumbnail(entry.id), !Task.isCancelled {
                thumbnail = NSImage(data: data)
            }
        }
    }
}
