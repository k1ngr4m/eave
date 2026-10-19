import SwiftUI

struct NoteMarkdownPreview: View {
    @Binding var content: String

    var body: some View {
        // Keep source offsets and their text together, so a stale button cannot edit a newer note.
        let source = content
        let blocks = NoteMarkdown.markdownPreview(source)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(blocks.indices, id: \.self) { index in
                    blockView(blocks[index], source: source)
                }
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func blockView(_ block: NoteMarkdownBlock, source: String) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(block.text).font(.system(size: CGFloat(max(14, 24 - level * 2)), weight: .bold))
        case .code:
            Text(block.text)
                .font(.system(size: 12, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        case .thematicBreak:
            Divider()
        case .taskListItem(let depth, let checked, let box):
            HStack(alignment: .top, spacing: 6) {
                Button {
                    guard content == source,
                          let edit = NoteMarkdown.taskToggleEdit(box: box, in: content) else { return }
                    content = (content as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
                } label: {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? Color.accentColor : .secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(block.text.characters)))
                .accessibilityValue(checked ? Text("Completed") : Text("Not completed"))
                .help(checked ? String(localized: "Mark incomplete") : String(localized: "Mark complete"))
                Text(block.text)
                    .strikethrough(checked)
                    .foregroundStyle(checked ? .secondary : .primary)
                    .padding(.top, 4)
            }
            .padding(.leading, CGFloat(depth - 1 + block.quoteDepth) * 14)
        case .unorderedListItem(let depth):
            HStack(alignment: .top) { Text("•"); Text(block.text) }
                .padding(.leading, CGFloat(depth - 1 + block.quoteDepth) * 14)
        case .orderedListItem(let ordinal, let depth):
            HStack(alignment: .top) { Text("\(ordinal)."); Text(block.text) }
                .padding(.leading, CGFloat(depth - 1 + block.quoteDepth) * 14)
        case .quote(let depth):
            Text(block.text)
                .foregroundStyle(.secondary)
                .padding(.leading, CGFloat(depth) * 14)
                .overlay(alignment: .leading) { Rectangle().fill(.secondary.opacity(0.4)).frame(width: 2) }
        case .paragraph:
            Text(block.text)
        }
    }
}
