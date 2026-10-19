// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted for Eave from vorssaint-utils at 98a56d27.
// Rendering and edits operate on the original text; Apple Notes receives that same text.
import Foundation

struct NoteMarkdownBlock: Equatable {
    enum Kind: Equatable {
        case paragraph
        case heading(Int)
        case unorderedListItem(depth: Int)
        /// A `- [ ]` or `- [x]` item; `box` is the UTF-16 offset of its `[`
        /// in the text, so a click edits the very box it was drawn from.
        case taskListItem(depth: Int, checked: Bool, box: Int)
        case orderedListItem(ordinal: Int, depth: Int)
        case quote(depth: Int)
        case code
        case thematicBreak
    }

    let kind: Kind
    let containerID: Int?
    let text: AttributedString
    /// The quotes around a list item, which its reading keeps ahead of its
    /// marker; a quote's own paragraphs carry their depth in `kind`.
    var quoteDepth = 0
}

enum NoteMarkdown {
    static func markdownPreview(_ text: String) -> [NoteMarkdownBlock] {
        guard !text.isEmpty else { return [] }
        // Source positions say where each task's box sits in the text. They
        // leave the blocks once read, so the reading never carries them.
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible,
            appliesSourcePositionAttributes: true)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return [NoteMarkdownBlock(kind: .paragraph,
                                            containerID: nil,
                                            text: AttributedString(text))]
        }

        var blocks: [NoteMarkdownBlock] = []
        var currentID: Int?
        var currentKind = NoteMarkdownBlock.Kind.paragraph
        var currentContainerID: Int?
        var currentQuoteDepth = 0
        var currentText = AttributedString()

        func finishBlock() {
            guard currentID != nil else { return }
            if currentKind == .code {
                while currentText.characters.last?.isNewline == true {
                    currentText.characters.removeLast()
                }
            }
            blocks.append(NoteMarkdownBlock(kind: currentKind,
                                                  containerID: currentContainerID,
                                                  text: currentText,
                                                  quoteDepth: currentQuoteDepth))
            currentText = AttributedString()
        }

        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let blockID = components.first?.identity ?? 0
            if blockID != currentID {
                finishBlock()
                currentID = blockID
                let presentation = markdownBlockPresentation(components)
                currentKind = presentation.kind
                currentContainerID = presentation.containerID
                currentQuoteDepth = presentation.quoteDepth
            }
            currentText.append(AttributedString(parsed[run.range]))
        }
        finishBlock()
        let lineStarts = lineStarts(in: text)
        blocks = blocks.map { withTask($0, in: text, lineStarts: lineStarts) }

        return blocks.isEmpty
            ? [NoteMarkdownBlock(kind: .paragraph,
                                       containerID: nil,
                                       text: AttributedString(text))]
            : blocks
    }

    /// The checkbox opening a list item's text: `[ ]`, `[x]` or `[X]`, and
    /// the bare `[]` that is easy to type, followed by a space or the end.
    private static func taskMarker(in text: String) -> (checked: Bool, length: Int)? {
        let characters = Array(text.prefix(4))
        func closes(_ at: Int) -> Bool { characters.count == at || characters[at] == " " || characters[at] == "\t" }
        guard characters.first == "[" else { return nil }
        if characters.count > 1, characters[1] == "]", closes(2) { return (false, 2) }
        if characters.count > 2, characters[2] == "]", closes(3) {
            if characters[1] == " " { return (false, 3) }
            if characters[1] == "x" || characters[1] == "X" { return (true, 3) }
        }
        return nil
    }

    /// Turns a list item that opens with a checkbox into a task that knows
    /// where its box is in `source`: the parser's own position of the item's
    /// first run, so the reading and a click can never disagree about which
    /// line a box belongs to. Source positions leave the block here.
    private static func withTask(_ block: NoteMarkdownBlock, in source: String,
                                 lineStarts: [String.Index]) -> NoteMarkdownBlock {
        var text = block.text
        let first = text.runs.first
        text.markdownSourcePosition = nil
        let plain = NoteMarkdownBlock(kind: block.kind, containerID: block.containerID, text: text,
                                            quoteDepth: block.quoteDepth)
        // The box has to open the item as plain text: `[ ]` in code or
        // emphasis is only text, and so is an escaped or encoded bracket,
        // which reads the same but leaves no box where its run starts.
        guard case .unorderedListItem(let depth) = block.kind,
              let first, first.inlinePresentationIntent == nil, first.link == nil,
              let position = first.markdownSourcePosition,
              // The parser's line and UTF-8 column, read against lines
              // counted here. Foundation's own conversion slips a line after
              // a lazy continuation line or a NUL, and its NSRange variant
              // after every CRLF.
              position.startLine >= 1, position.startLine <= lineStarts.count, position.startColumn >= 1,
              let start = source.utf8.index(lineStarts[position.startLine - 1],
                                            offsetBy: position.startColumn - 1,
                                            limitedBy: source.utf8.endIndex),
              let marker = taskMarker(in: String(text.characters))
        else { return plain }
        // A position that still lands elsewhere, as one after a NUL on the
        // item's own line does, must not reach a box of the same shape, so
        // the text there has to read as the run does, up to the first escape
        // or entity the parser resolved.
        let run = String(block.text[first.range].characters)
        guard run.hasPrefix(source[start...].prefix(run.count).prefix { !"\\&\u{0}".contains($0) })
        else { return plain }
        let box = NSRange(start..<start, in: source).location
        guard let written = taskBox(at: box, in: source),
              written.checked == marker.checked, written.length == marker.length else { return plain }
        let opening = text.characters.startIndex
        var end = text.characters.index(opening, offsetBy: marker.length)
        if end < text.characters.endIndex, text.characters[end] == " " || text.characters[end] == "\t" {
            end = text.characters.index(after: end)
        }
        text.removeSubrange(opening..<end)
        return NoteMarkdownBlock(kind: .taskListItem(depth: depth, checked: marker.checked, box: box),
                                       containerID: block.containerID, text: text, quoteDepth: block.quoteDepth)
    }

    /// Where each line of `text` starts, ending lines at \n, \r\n and a lone
    /// \r, as the Markdown parser does.
    private static func lineStarts(in text: String) -> [String.Index] {
        let bytes = text.utf8
        var starts = [bytes.startIndex]
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            index = bytes.index(after: index)
            guard byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") else { continue }
            if byte == UInt8(ascii: "\r"), index < bytes.endIndex, bytes[index] == UInt8(ascii: "\n") {
                index = bytes.index(after: index)
            }
            starts.append(index)
        }
        return starts
    }

    /// The box whose `[` sits at UTF-16 offset `box` of `text`: `[ ]`, `[x]`,
    /// `[X]` or the bare `[]`, or nil when no box starts there.
    private static func taskBox(at box: Int, in text: String) -> (checked: Bool, length: Int)? {
        let text = text as NSString
        func character(_ offset: Int) -> String? {
            box + offset < text.length ? text.substring(with: NSRange(location: box + offset, length: 1)) : nil
        }
        guard box >= 0, character(0) == "[" else { return nil }
        if character(1) == "]" { return (false, 2) }
        guard let mark = character(1), [" ", "x", "X"].contains(mark), character(2) == "]" else { return nil }
        return (mark != " ", 3)
    }

    /// The edit that checks or unchecks the box whose `[` sits at UTF-16
    /// offset `box`, or nil when the text holds no box there any more.
    static func taskToggleEdit(box: Int, in text: String) -> (range: NSRange, replacement: String)? {
        guard let current = taskBox(at: box, in: text) else { return nil }
        if current.length == 2 { return (NSRange(location: box + 1, length: 0), "x") }
        return (NSRange(location: box + 1, length: 1), current.checked ? " " : "x")
    }

    private static let listMarker = try? NSRegularExpression(
        pattern: #"^([ \t]*(?:>[ \t]*)*)([-*+]|\d+[.)])([ \t]+)(\[[ xX]?\](?:[ \t]+|$))?"#)

    /// What Shift-Return does with the caret at `caret`: in a list item it
    /// opens the next one, with the same marker, a fresh unchecked box for a
    /// task and the next number for a numbered item; on an empty item it ends
    /// the list instead; anywhere else it is a plain line break. `range` is
    /// what is replaced and `caret` the offset after the edit.
    static func lineBreakEdit(in text: String, selection: NSRange) -> (range: NSRange, replacement: String, caret: Int) {
        let plain = (range: selection, replacement: "\n", caret: selection.location + 1)
        let whole = text as NSString
        guard selection.length == 0, selection.location <= whole.length, let listMarker else { return plain }
        // A list-looking line inside a code block stays literal.
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full,
                                                              appliesSourcePositionAttributes: true)
        if let parsed = try? AttributedString(markdown: text, options: options) {
            let lineNumber = lineStarts(in: text).filter {
                NSRange(text.startIndex..<$0, in: text).length <= selection.location
            }.count
            if parsed.runs.contains(where: { run in
                guard let position = run.markdownSourcePosition,
                      position.startLine <= lineNumber, position.endLine >= lineNumber else { return false }
                return run.presentationIntent?.components.contains {
                    if case .codeBlock = $0.kind { return true }; return false
                } == true
            }) { return plain }
        }
        let line = whole.lineRange(for: NSRange(location: selection.location, length: 0))
        var content = line
        while content.length > 0, "\n\r".contains(whole.substring(with: NSRange(location: NSMaxRange(content) - 1, length: 1))) {
            content.length -= 1
        }
        let lineText = whole.substring(with: content)
        guard let match = listMarker.firstMatch(in: lineText, range: NSRange(location: 0, length: (lineText as NSString).length))
        else { return plain }
        let markerEnd = content.location + match.range.length
        guard selection.location >= markerEnd else { return plain }
        let lineNS = lineText as NSString
        let prefix = lineNS.substring(with: match.range(at: 1))
        let marker = lineNS.substring(with: match.range(at: 2))
        let spacing = lineNS.substring(with: match.range(at: 3))
        let hasBox = match.range(at: 4).location != NSNotFound
        if selection.location == NSMaxRange(content), match.range.length == lineNS.length || lineNS.substring(from: match.range.length).trimmingCharacters(in: .whitespaces).isEmpty {
            // An empty item: the list ends, and the marker goes.
            return (content, "", content.location)
        }
        var next = marker
        // The largest number has no next one; its item repeats it.
        if let digits = Int(marker.dropLast()), digits < Int.max, let delimiter = marker.last {
            next = "\(digits + 1)\(delimiter)"
        }
        let replacement = "\n" + prefix + next + spacing + (hasBox ? "[ ] " : "")
        return (selection, replacement, selection.location + (replacement as NSString).length)
    }

    private static func markdownBlockPresentation(
        _ components: [PresentationIntent.IntentType]
    ) -> (kind: NoteMarkdownBlock.Kind, containerID: Int?, quoteDepth: Int) {
        var listDepth = 0
        var listIsOrdered: Bool?
        var listOrdinal = 1
        var quoteDepth = 0
        // Components run from the innermost out, so a quote met after a list
        // holds that list, and its items keep the quote around their marker.
        var listQuoteDepth = 0
        var containerID: Int?

        for component in components {
            switch component.kind {
            case .header(let level):
                return (.heading(level), nil, 0)
            case .codeBlock:
                return (.code, nil, 0)
            case .thematicBreak:
                return (.thematicBreak, nil, 0)
            case .listItem(let ordinal):
                if listDepth == 0 { listOrdinal = ordinal }
            case .orderedList:
                listDepth += 1
                if listIsOrdered == nil { listIsOrdered = true }
                containerID = component.identity
            case .unorderedList:
                listDepth += 1
                if listIsOrdered == nil { listIsOrdered = false }
                containerID = component.identity
            case .blockQuote:
                quoteDepth += 1
                if listDepth > 0 { listQuoteDepth += 1 }
                containerID = component.identity
            case .paragraph, .table, .tableHeaderRow, .tableRow, .tableCell:
                break
            @unknown default:
                break
            }
        }

        if listIsOrdered == true {
            return (.orderedListItem(ordinal: listOrdinal, depth: max(1, listDepth)), containerID, listQuoteDepth)
        }
        if listIsOrdered == false {
            return (.unorderedListItem(depth: max(1, listDepth)), containerID, listQuoteDepth)
        }
        if quoteDepth > 0 { return (.quote(depth: quoteDepth), containerID, 0) }
        return (.paragraph, nil, 0)
    }

}
