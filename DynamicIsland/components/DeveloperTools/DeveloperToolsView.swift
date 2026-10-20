import AppKit
import SwiftUI
import Defaults
import UniformTypeIdentifiers

@MainActor func developerToolsSize(screenName: String?) -> CGSize {
    let screen = NSScreen.screens.first { $0.localizedName == screenName } ?? NSScreen.main
    let frame = screen?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
    let state = DynamicIslandViewCoordinator.shared
    let editing = state.developerToolOpen
    let width = editing ? (state.developerToolExpanded ? 1120.0 : 900.0) : max(560, openNotchSize.width)
    return CGSize(width: min(width, maxAllowedNotchWidth(for: screenName)), height: min(editing ? (state.developerToolExpanded ? 740 : 570) : 280, frame.height - 40))
}

struct DeveloperToolsSettings: View {
    @Default(.enableDeveloperTools) private var enabled
    @Default(.enableJSONTool) private var jsonEnabled
    @Default(.jsonIndent) private var indent
    @Default(.jsonSort) private var sort
    @Default(.jsonAutoValidate) private var autoValidate
    var body: some View {
        Form {
            Section {
                Toggle("启用开发工具", isOn: $enabled)
            } footer: { Text("在刘海中显示开发工具标签页。所有 JSON 操作均在本地完成。") }
            Section("工具") {
                HStack(spacing: 12) {
                    Image(systemName: "curlybraces").font(.title2).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("JSON 美化")
                        Text("格式化、校验、转义与结构化浏览").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("启用 JSON 美化", isOn: $jsonEnabled).labelsHidden()
                }
            }.disabled(!enabled)
            Section("JSON 默认设置") {
                Picker("缩进", selection: $indent) {
                    Text("2 空格").tag(2)
                    Text("4 空格").tag(4)
                }
                Picker("键名排序", selection: $sort) {
                    Text("保持原序").tag("original")
                    Text("升序").tag("ascending")
                    Text("降序").tag("descending")
                }
                Toggle("输入时自动校验", isOn: $autoValidate)
            }.disabled(!enabled || !jsonEnabled)
        }.formStyle(.grouped)
    }
}

/// Session-only state deliberately survives notch/tab view reconstruction without writing payloads to disk.
@MainActor final class JSONWorkspace: ObservableObject {
    static let shared = JSONWorkspace()
    @Published var input = ""
    @Published var output = ""
    @Published var root: JSONValue?
    @Published var status = "粘贴或导入 JSON 开始处理"
    @Published var error: JSONToolError?
    @Published var busy = false
    @Published var mode = "代码"
    @Published var vertical = false
    @Published var autoDecode = false
    @Published var nested = false
    @Published var selection: NSRange? = nil
    private var work: Task<Void, Never>?
    private var revision = 0

    func changed() {
        revision += 1
        work?.cancel()
        root = nil; output = ""; error = nil; busy = false
        status = input.isEmpty ? "粘贴或导入 JSON 开始处理" : "尚未校验"
        guard Defaults[.jsonAutoValidate], !input.isEmpty else { return }
        process("格式化", debounce: true)
    }
    func process(_ operation: String, debounce: Bool = false) {
        work?.cancel(); revision += 1
        let current = revision
        let text = input, indent = Defaults[.jsonIndent], sort = Defaults[.jsonSort]
        let decode = autoDecode, nesting = nested
        busy = true
        work = Task {
            if debounce { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) { () -> Result<(String, JSONValue?), JSONToolError> in
                do {
                    guard text.utf8.count <= JSONParser.maximumBytes else { throw JSONToolError("内容超过 2 MB，请缩小后再处理") }
                    if operation == "转义" { return .success((JSONValue.quote(text), nil)) }
                    if operation == "反转义" || operation == "Unicode 解码" {
                        let source = text.hasPrefix("\"") ? text : "\"" + text.replacingOccurrences(of: "\"", with: "\\\"") + "\""
                        guard case .string(let decoded) = try JSONParser.parse(source) else { throw JSONToolError("请输入 JSON 字符串或带转义的文本") }
                        return .success((decoded, try? JSONParser.parse(decoded)))
                    }
                    if operation == "Unicode 编码" {
                        let quoted = JSONValue.quote(text)
                        let encoded = quoted.utf16.map { $0 > 127 ? String(format: "\\u%04x", $0) : String(UnicodeScalar($0)!) }.joined()
                        return .success((encoded, nil))
                    }
                    if operation == "URL 解码" {
                        guard let decoded = text.removingPercentEncoding else { throw JSONToolError("URL 编码无效") }
                        return .success((decoded, try? JSONParser.parse(decoded)))
                    }
                    var source = text
                    if decode {
                        if let decoded = source.removingPercentEncoding, (try? JSONParser.parse(decoded)) != nil { source = decoded }
                        if case .string(let decoded) = try? JSONParser.parse(source), (try? JSONParser.parse(decoded)) != nil { source = decoded }
                    }
                    var value = try JSONParser.parse(source)
                    if nesting { value = value.nestedDecoded() }
                    return .success((value.rendered(indent: operation == "压缩" ? 0 : indent, sort: sort), value))
                } catch let error as JSONToolError { return .failure(error) }
                catch { return .failure(JSONToolError(error.localizedDescription)) }
            }.value
            guard !Task.isCancelled, current == revision else { return }
            busy = false
            switch result {
            case .success(let (text, value)):
                output = text; root = value; error = nil
                status = value == nil ? "\(operation)完成" : "JSON 有效 · \(input.utf8.count) 字节"
            case .failure(let failure):
                error = failure; root = nil; output = ""; status = failure.message
            }
        }
    }
    func replaceOutput(_ value: JSONValue) {
        work?.cancel(); revision += 1; busy = false
        root = value; error = nil
        output = value.rendered(indent: Defaults[.jsonIndent], sort: Defaults[.jsonSort])
        status = "结果已更新 · 原始输入保留"
    }
}

struct DeveloperToolsView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var document = JSONWorkspace.shared
    @State private var token = UUID()
    @Default(.jsonWorkspacePinned) private var pinned
    @Default(.enableJSONTool) private var jsonEnabled
    @State private var cardHovered = false
    @State private var fileDialogOpen = false
    @State private var sheet: JSONSheet?
    @State private var sheetText = ""
    @State private var pointer = ""
    @State private var sheetMessage = ""
    @State private var search = ""
    @State private var collapsed = Set<String>()
    @Default(.jsonIndent) private var indent
    @Default(.jsonSort) private var sort
    @Default(.jsonAutoValidate) private var autoValidate

    enum JSONSheet: String, Identifiable {
        case schema = "离线 Schema 校验", extract = "提取字段", edit = "节点编辑", metadata = "元数据"
        var id: String { rawValue }
    }
    var body: some View {
        VStack(spacing: 12) {
            if coordinator.developerToolOpen && jsonEnabled { workspace } else { toolList }
        }
        .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { inside in vm.setScrollGestureSuppression(inside, token: token) }
        .onAppear { updatePin() }
        .onChange(of: vm.notchState) { _, state in if state == .open { updatePin() } }
        .onChange(of: autoValidate) { _, _ in document.changed() }
        .onChange(of: sheet) { _, _ in updatePin() }
        .onChange(of: fileDialogOpen) { _, _ in updatePin() }
        .onChange(of: jsonEnabled) { _, enabled in
            if !enabled { sheet = nil }
            updatePin()
        }
        .onChange(of: pinned) { _, _ in updatePin() }
        .onChange(of: coordinator.developerToolOpen) { _, _ in updatePin() }
        .onDisappear {
            vm.setScrollGestureSuppression(false, token: token)
            vm.setAutoCloseSuppression(false, token: token)
        }
        .sheet(item: $sheet) { item in detailSheet(item) }
    }
    private func updatePin() { vm.setAutoCloseSuppression(coordinator.developerToolOpen && jsonEnabled && (pinned || sheet != nil || fileDialogOpen), token: token) }
    private var toolList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("开发工具").font(.system(size: 18, weight: .semibold))
                Spacer()
                Label("本地处理", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.vertical) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 210))], alignment: .leading, spacing: 12) {
                    if jsonEnabled {
                        Button {
                            coordinator.developerToolOpen = true
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: "curlybraces").font(.system(size: 27, weight: .medium)).foregroundStyle(.blue)
                                Text("JSON 美化").font(.system(size: 15, weight: .semibold))
                                Text("格式化 · 校验 · 转义").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                            .background(.primary.opacity(cardHovered ? 0.09 : 0.045), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.blue.opacity(cardHovered ? 0.8 : 0.45), lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).help("打开 JSON 美化")
                        .onHover { cardHovered = $0 }
                        .animation(.easeOut(duration: 0.15), value: cardHovered)
                    }
                }
            }.scrollIndicators(.hidden)
            .overlay {
                if !jsonEnabled {
                    VStack(spacing: 8) {
                        Image(systemName: "curlybraces").font(.title2)
                        Text("暂无启用的工具").font(.subheadline)
                        Text("在设置的开发工具页中启用 JSON 美化").font(.caption)
                    }.foregroundStyle(.secondary)
                }
            }
        }
    }
    private var workspace: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { coordinator.developerToolOpen = false } label: { Image(systemName: "chevron.left") }.help("返回开发工具")
                Text("JSON 美化").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { pinned.toggle() } label: { Image(systemName: pinned ? "pin.fill" : "pin") }.foregroundStyle(pinned ? .blue : .secondary).help("保持面板打开")
                Button { coordinator.developerToolExpanded.toggle() } label: { Image(systemName: coordinator.developerToolExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }.help("切换工作区大小")
            }.buttonStyle(.plain)
            toolbar
            GeometryReader { geometry in
                let stacked = document.vertical || geometry.size.width < 700
                if stacked {
                    VStack(spacing: 8) { inputPane; outputPane }
                } else {
                    HStack(spacing: 10) { inputPane; outputPane }
                }
            }
            HStack(spacing: 6) {
                if document.busy { ProgressView().controlSize(.mini) }
                else { Circle().fill(document.error == nil ? (document.root == nil ? Color.secondary : .green) : .red).frame(width: 6, height: 6) }
                Button {
                    if let offset = document.error?.offset { document.selection = NSRange(location: offset, length: 0) }
                } label: {
                    Text(document.status).lineLimit(1).foregroundStyle(document.error == nil ? Color.secondary : .red)
                }.buttonStyle(.plain).help(document.status)
                Spacer(minLength: 4)
                Text("UTF-8 · 本地处理").foregroundStyle(.tertiary)
            }.font(.system(size: 10))
        }
    }
    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { actions; options }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { actions; Spacer() }
                HStack(spacing: 6) { options; Spacer() }
            }
        }.controlSize(.small)
    }
    private var actions: some View {
        Group {
            Button("格式化") { document.process("格式化") }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
            ForEach(["压缩", "转义", "反转义"], id: \.self) { title in
                Button(title) { document.process(title) }.buttonStyle(.bordered)
            }
        }
    }
    private var options: some View {
        Group {
            Menu {
                Picker("键名排序", selection: $sort) { Text("保持原序").tag("original"); Text("升序").tag("ascending"); Text("降序").tag("descending") }
                Picker("缩进", selection: $indent) { Text("2 空格").tag(2); Text("4 空格").tag(4) }
            } label: { Text("排序 / 缩进") }.fixedSize()
            Button { document.vertical.toggle() } label: { Image(systemName: document.vertical ? "rectangle.split.1x2" : "rectangle.split.2x1") }.help("切换左右 / 上下布局")
            Spacer(minLength: 0)
            Menu {
                Toggle("自动校验", isOn: $autoValidate)
                Toggle("自动解码", isOn: $document.autoDecode)
                Toggle("嵌套解析", isOn: $document.nested)
                Button("校验 JSON") { document.process("格式化") }
                Divider()
                ForEach(["Unicode 编码", "Unicode 解码", "URL 解码"], id: \.self) { title in Button(title) { document.process(title) } }
                Divider()
                Button("离线 Schema 校验…") { present(.schema) }.disabled(document.root == nil)
                Button("提取字段…") { present(.extract) }.disabled(document.root == nil)
                Button("节点编辑…") { present(.edit) }.disabled(document.root == nil)
                Button("元数据…") { present(.metadata) }.disabled(document.root == nil)
            } label: { Image(systemName: "ellipsis") }.menuIndicator(.hidden).fixedSize().help("更多 JSON 工具")
        }
        .onChange(of: indent) { _, _ in if !document.input.isEmpty { document.process("格式化") } }
        .onChange(of: sort) { _, _ in if !document.input.isEmpty { document.process("格式化") } }
        .onChange(of: document.autoDecode) { _, _ in document.changed() }
        .onChange(of: document.nested) { _, _ in document.changed() }
    }
    private var inputPane: some View {
        pane {
            HStack {
                Text("输入").fontWeight(.medium)
                Spacer()
                Button("粘贴") { if let text = NSPasteboard.general.string(forType: .string) { document.input = text; document.changed() } }
                Button { importFile() } label: { Image(systemName: "folder") }.help("导入 JSON 文件")
                Button { document.input = ""; document.changed() } label: { Image(systemName: "xmark.circle") }.help("清空输入")
            }
        } content: {
            JSONCodeEditor(text: $document.input, selection: $document.selection, editable: true) { document.changed() }
        }
    }
    private var outputPane: some View {
        pane {
            HStack(spacing: 6) {
                Text("结果").fontWeight(.medium)
                Picker("结果视图", selection: $document.mode) {
                    ForEach(["代码", "树形", "表格"], id: \.self) { Text($0) }
                }.labelsHidden().pickerStyle(.segmented).frame(maxWidth: 160)
                Spacer(minLength: 0)
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(document.output, forType: .string) } label: { Image(systemName: "doc.on.doc") }.help("复制结果").disabled(document.output.isEmpty)
                Button { exportFile() } label: { Image(systemName: "square.and.arrow.up") }.help("导出结果").disabled(document.output.isEmpty)
            }
        } content: {
            if document.output.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "curlybraces").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text(document.error == nil ? "格式化后的 JSON 将显示在这里" : "修正输入后重试").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if document.mode == "树形", let root = document.root {
                tree(root)
            } else if document.mode == "表格", let root = document.root {
                table(root)
            } else {
                JSONCodeEditor(text: .constant(document.output), selection: .constant(nil), editable: false, changed: {})
            }
        }
    }
    private func pane<H: View, C: View>(@ViewBuilder header: () -> H, @ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) {
            header().font(.system(size: 11)).buttonStyle(.plain).padding(.horizontal, 10).frame(height: 35)
            Divider().opacity(0.5)
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.09), lineWidth: 1))
    }
    private struct TreeRow: Identifiable {
        let id: String
        let pointer: String
        let name: String
        let value: JSONValue
        let depth: Int
    }
    private func rows(_ root: JSONValue) -> [TreeRow] {
        var result: [TreeRow] = []
        func visit(_ value: JSONValue, id: String, pointer: String, name: String, depth: Int) {
            guard result.count < 5000 else { return }
            result.append(TreeRow(id: id, pointer: pointer, name: name, value: value, depth: depth))
            guard !collapsed.contains(id) || !search.isEmpty else { return }
            for (index, child) in value.children.enumerated() {
                visit(child.1, id: id + "/\(index)", pointer: pointer + "/" + JSONValue.pointerToken(child.0), name: child.0, depth: depth + 1)
            }
        }
        visit(root, id: "root", pointer: "", name: "$", depth: 0)
        return result
    }
    private func tree(_ root: JSONValue) -> some View {
        let visibleRows = rows(root)
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let contentWidth = visibleRows.reduce(CGFloat(0)) { width, row in
            let text = row.name + ": " + row.value.summary
            return max(width, (text as NSString).size(withAttributes: [.font: font]).width + CGFloat(row.depth) * 15 + 50)
        }
        return VStack(spacing: 0) {
            HStack {
                TextField("筛选字段或值", text: $search).textFieldStyle(.plain)
                Button(collapsed.isEmpty ? "折叠" : "展开") { if collapsed.isEmpty { collapsed = Set(rows(root).filter { !$0.value.children.isEmpty }.map(\.id)) } else { collapsed.removeAll() } }
            }.font(.caption).padding(10)
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleRows.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.value.summary.localizedCaseInsensitiveContains(search) }) { row in
                        HStack(spacing: 6) {
                            Button { if collapsed.contains(row.id) { collapsed.remove(row.id) } else { collapsed.insert(row.id) } } label: {
                                Image(systemName: collapsed.contains(row.id) ? "chevron.right" : "chevron.down").frame(width: 10).opacity(row.value.children.isEmpty ? 0 : 1)
                            }.buttonStyle(.plain).disabled(row.value.children.isEmpty)
                            Text(row.name + ":").foregroundStyle(.blue).fixedSize()
                            Text(row.value.summary).foregroundStyle(jsonColor(row.value)).fixedSize().textSelection(.enabled)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .font(.system(size: 12, design: .monospaced)).padding(.leading, CGFloat(row.depth) * 15).padding(.vertical, 3)
                        .contextMenu {
                            Button("复制路径") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(row.pointer, forType: .string) }
                            Button("编辑节点…") { present(.edit); pointer = row.pointer; sheetText = row.value.rendered() }
                            Button("提取此节点") { document.replaceOutput(row.value) }
                        }
                    }
                    if visibleRows.count >= 5000 { Text("树形预览最多显示 5000 个节点，完整内容可在代码视图查看。").font(.caption) }
                }.frame(width: contentWidth, alignment: .leading).padding(10)
            }
        }
    }
    private func jsonColor(_ value: JSONValue) -> Color {
        switch value {
        case .string: return .green
        case .number: return .orange
        case .bool, .null: return .purple
        default: return .secondary
        }
    }
    private func table(_ root: JSONValue) -> some View {
        // Objects are field/value records; only arrays of objects become columnar tables.
        let records: [JSONValue] = { if case .array(let items) = root { return items }; return [] }()
        let columnar = !records.isEmpty && records.allSatisfy { $0.typeName == "object" }
        var keys: [String] = []
        if columnar {
            var seen = Set<String>()
            for record in records.prefix(200) {
                for (key, _) in record.children where seen.insert(key).inserted { keys.append(key) }
            }
        }
        let fields = root.typeName == "object" || root.typeName == "array" ? root.children : [("$", root)]
        let headings = columnar ? ["#"] + keys : [root.typeName == "array" ? "索引" : "字段", "值"]
        let count = columnar ? records.count : fields.count
        return GeometryReader { geometry in
            let keyWidth = min(220.0, max(150.0, geometry.size.width * 0.35))
            let widths: [CGFloat] = columnar ? [44] + keys.map { _ in CGFloat(220) } : [keyWidth, max(240, geometry.size.width - keyWidth)]
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(0..<min(count, 200), id: \.self) { index in
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(headings.indices, id: \.self) { column in
                                    if columnar {
                                        if column == 0 {
                                            tableCell(String(index), width: widths[column], color: .secondary)
                                        } else {
                                            let value = records[index].children.first { $0.0 == keys[column - 1] }?.1
                                            tableCell(value.map(tableText) ?? "—", width: widths[column], color: value.map(jsonColor) ?? .secondary)
                                        }
                                    } else if column == 0 {
                                        tableCell(fields[index].0, width: widths[column], color: .blue)
                                    } else {
                                        tableCell(tableText(fields[index].1), width: widths[column], color: jsonColor(fields[index].1))
                                    }
                                }
                            }
                            .background(.primary.opacity(index.isMultiple(of: 2) ? 0.025 : 0))
                            .overlay { tableGridLines(widths) }
                            .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.08)).frame(height: 1) }
                        }
                    } header: {
                        HStack(spacing: 0) {
                            ForEach(headings.indices, id: \.self) { index in
                                tableCell(headings[index], width: widths[index], color: .primary).fontWeight(.semibold)
                            }
                        }.background(Color(nsColor: .controlBackgroundColor))
                        .overlay { tableGridLines(widths) }
                    }
                    if count == 0 { Text("没有可显示的数据").foregroundStyle(.secondary).padding(12) }
                    if count > 200 { Text("预览前 200 行，复制和导出包含完整结果。").foregroundStyle(.secondary).padding(12) }
                }
                .frame(width: widths.reduce(0, +), alignment: .leading)
                .font(.system(size: 12, design: .monospaced))
            }
        }
    }
    private func tableText(_ value: JSONValue) -> String {
        if case .string(let text) = value { return text }
        return value.rendered(indent: value.children.isEmpty ? 0 : 2)
    }
    private func tableCell(_ text: String, width: CGFloat, color: Color) -> some View {
        Text(text)
            .foregroundStyle(color)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width - 24, alignment: .leading)
            .padding(12)
    }
    private func tableGridLines(_ widths: [CGFloat]) -> some View {
        GeometryReader { geometry in
            Path { path in
                var x: CGFloat = 0
                for width in widths.dropLast() {
                    x += width
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }
            }.stroke(.primary.opacity(0.08), lineWidth: 1)
        }.allowsHitTesting(false)
    }
    private func present(_ item: JSONSheet) { pointer = ""; sheetText = item == .edit ? document.output : ""; sheetMessage = ""; sheet = item }
    private func detailSheet(_ item: JSONSheet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.rawValue).font(.title3.bold())
            if item == .metadata {
                Text("输入：\(document.input.utf8.count) 字节\n输出：\(document.output.utf8.count) 字节\n根类型：\(document.root?.typeName ?? "—")\n根节点子项：\(document.root?.children.count ?? 0)\n输出行数：\(document.output.components(separatedBy: "\n").count)\n编码：UTF-8\n数字：保留原始精度和表示法")
                    .font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
            } else {
                if item == .schema {
                    Text("支持 type、properties、required、items、enum、const、additionalProperties 和长度限制；不支持的关键字会明确报错。").font(.caption).foregroundStyle(.secondary)
                } else {
                    TextField("JSON Pointer，例如 /data/0/name；留空表示根节点", text: $pointer)
                    if item == .edit {
                        Button("读取节点") { do { sheetText = try document.root?.at(JSONValue.pointerParts(pointer)).rendered() ?? "" } catch { sheetMessage = error.localizedDescription } }
                    }
                }
                if item != .extract {
                    TextEditor(text: $sheetText).font(.system(size: 12, design: .monospaced)).frame(height: 220).border(.secondary.opacity(0.2))
                }
                if !sheetMessage.isEmpty { ScrollView { Text(sheetMessage).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 100) }
            }
            HStack {
                Spacer()
                Button("关闭") { sheet = nil }.keyboardShortcut(.cancelAction)
                if item != .metadata { Button(item == .schema ? "校验" : "应用到结果") { applySheet(item) }.buttonStyle(.borderedProminent) }
            }
        }.padding(22).frame(width: 520)
    }
    private func applySheet(_ item: JSONSheet) {
        guard let root = document.root else { return }
        do {
            switch item {
            case .schema:
                let errors = try JSONSchemaValidator.validate(root, schema: JSONParser.parse(sheetText))
                sheetMessage = errors.isEmpty ? "校验通过" : errors.joined(separator: "\n")
            case .extract: document.replaceOutput(try root.at(JSONValue.pointerParts(pointer))); sheet = nil
            case .edit: document.replaceOutput(try root.replacing(JSONValue.pointerParts(pointer), with: JSONParser.parse(sheetText))); sheet = nil
            case .metadata: break
            }
        } catch { sheetMessage = error.localizedDescription }
    }
    private func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json, .plainText]; panel.allowsMultipleSelection = false
        fileDialogOpen = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        panel.begin { response in
            fileDialogOpen = false
            guard response == .OK, let url = panel.url else { return }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= JSONParser.maximumBytes else { throw JSONToolError("文件超过 2 MB") }
                document.input = try String(contentsOf: url, encoding: .utf8); document.changed()
            } catch { document.error = JSONToolError(error.localizedDescription); document.status = error.localizedDescription }
        }
    }
    private func exportFile() {
        let panel = NSSavePanel(); panel.allowedContentTypes = document.root == nil ? [.plainText] : [.json]
        panel.nameFieldStringValue = document.root == nil ? "result.txt" : "formatted.json"
        let text = document.output
        fileDialogOpen = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        panel.begin { response in
            fileDialogOpen = false
            guard response == .OK, let url = panel.url else { return }
            do { try text.write(to: url, atomically: true, encoding: .utf8) }
            catch { document.status = error.localizedDescription; document.error = JSONToolError(error.localizedDescription) }
        }
    }
}
