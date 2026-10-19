import Foundation
import AppKit

@main
enum NoteMarkdownChecks {
    static func main() throws {
        let source = "# 计划\r\n\r\n- [ ] 中文 😀 **任务**\r\n- [x] 完成\r\n\r\n```text\r\n- [ ] 不可勾选\r\n```"
        let blocks = NoteMarkdown.markdownPreview(source)
        let tasks = blocks.compactMap { block -> Int? in
            if case .taskListItem(_, _, let box) = block.kind { return box }
            return nil
        }
        assert(tasks.count == 2, "Code fences must not produce tasks")
        let first = try require(NoteMarkdown.taskToggleEdit(box: tasks[0], in: source))
        let toggled = (source as NSString).replacingCharacters(in: first.range, with: first.replacement)
        assert(toggled == source.replacingOccurrences(of: "- [ ] 中文", with: "- [x] 中文"))
        let undo = try require(NoteMarkdown.taskToggleEdit(box: tasks[0], in: toggled))
        assert((toggled as NSString).replacingCharacters(in: undo.range, with: undo.replacement) == source)
        assert(NoteMarkdown.taskToggleEdit(box: -1, in: source) == nil)
        assert(NoteMarkdown.taskToggleEdit(box: (source as NSString).length, in: source) == nil)
        assert(NoteMarkdown.markdownPreview("- `[ ]` code\n- \\[ ] escaped").allSatisfy {
            if case .taskListItem = $0.kind { return false }; return true
        })
        for (input, expected) in [
            ("- [x] 买咖啡 😀", "- [x] 买咖啡 😀\n- [ ] "),
            ("  * 项目", "  * 项目\n  * "),
            ("> 9. 项目", "> 9. 项目\n> 10. "),
            ("- [ ] ", ""),
            ("plain", "plain\n")
        ] {
            let edit = NoteMarkdown.lineBreakEdit(in: input, selection: NSRange(location: (input as NSString).length, length: 0))
            assert((input as NSString).replacingCharacters(in: edit.range, with: edit.replacement) == expected)
        }
        let split = NoteMarkdown.lineBreakEdit(in: "- first second", selection: NSRange(location: 8, length: 0))
        assert(("- first second" as NSString).replacingCharacters(in: split.range, with: split.replacement) == "- first \n- second")
        let code = "```\n- literal\n```"
        let codeEdit = NoteMarkdown.lineBreakEdit(in: code, selection: NSRange(location: 13, length: 0))
        assert(codeEdit.replacement == "\n")

        // Exercise the production Apple Notes encoder, extracted by the runner.
        let note = NoteItem(id: UUID(), content: "# 标题\n- [ ] 中文 **任务**\n- [x] 完成\n\n<>&\"")
        let html = SyncEncodingProbe().htmlBody(for: note)
        assert(html.contains("<div>- [ ] 中文 **任务**</div>"))
        assert(html.contains("<div>- [x] 完成</div>"))
        assert(html.contains("<div><br></div>"))
        assert(html.contains("&lt;&gt;&amp;&quot;"))
        assert(html.hasSuffix("<!--eave:id=\(note.id.uuidString)-->") )
        let decoded = try NSAttributedString(data: Data(html.utf8), options: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ], documentAttributes: nil).string
        assert(decoded.contains("- [ ] 中文 **任务**"))
        assert(decoded.contains("- [x] 完成"))
        assert(decoded.contains("<>&\""))
        print("Note Markdown and Apple Notes encoding checks passed")
    }

    static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CocoaError(.validationMissingMandatoryProperty) }
        return value
    }
}
