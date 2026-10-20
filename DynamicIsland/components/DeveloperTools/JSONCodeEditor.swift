import AppKit
import SwiftUI

/// Native text system supplies selection, undo, find, accessibility and IME handling.
struct JSONCodeEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange?
    let editable: Bool
    let changed: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        let view = JSONNativeTextView()
        view.isEditable = editable
        view.isSelectable = true
        view.isRichText = false
        view.allowsUndo = true
        view.usesFindBar = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.drawsBackground = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textContainerInset = NSSize(width: 10, height: 10)
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.delegate = context.coordinator
        view.string = text
        view.setAccessibilityLabel(editable ? "JSON 输入，支持 Command F 搜索" : "JSON 结果，支持 Command F 搜索")
        scroll.documentView = view
        let ruler = JSONLineRuler(textView: view, scrollView: scroll)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.highlight(view)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text {
            view.string = text
            context.coordinator.highlight(view)
            scroll.verticalRulerView?.needsDisplay = true
        }
        if context.coordinator.scheme != colorScheme {
            context.coordinator.scheme = colorScheme
            context.coordinator.highlight(view)
        }
        if let selection, selection != context.coordinator.lastSelection {
            let range = NSRange(location: min(selection.location, view.string.utf16.count), length: 0)
            view.setSelectedRange(range)
            view.scrollRangeToVisible(range)
            view.window?.makeFirstResponder(view)
            context.coordinator.lastSelection = selection
        } else if selection == nil { context.coordinator.lastSelection = nil }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONCodeEditor
        var scheme: ColorScheme?
        var lastSelection: NSRange?
        private var pending: DispatchWorkItem?
        init(_ parent: JSONCodeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            parent.selection = nil
            parent.changed()
            view.enclosingScrollView?.verticalRulerView?.needsDisplay = true
            pending?.cancel()
            let item = DispatchWorkItem { [weak self, weak view] in if let view { self?.highlight(view) } }
            pending = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
        }
        func highlight(_ view: NSTextView) {
            guard !view.hasMarkedText(), let storage = view.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttributes([.foregroundColor: NSColor.labelColor, .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)], range: range)
            // Large payloads stay fully editable; skip costly color scans above the preview threshold.
            if storage.length < 200_000 {
                let pattern = #""(?:\\.|[^"\\])*"\s*(?=:)|"(?:\\.|[^"\\])*"|\b(?:true|false|null)\b|-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?"#
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let ns = view.string as NSString
                    for match in regex.matches(in: view.string, range: range) {
                        let token = ns.substring(with: match.range)
                        let color: NSColor
                        if token.hasPrefix("\"") {
                            let end = NSMaxRange(match.range)
                            let isKey = end < ns.length && ns.character(at: end) == 58
                            color = isKey ? .systemBlue : .systemGreen
                        } else if ["true", "false", "null"].contains(token) { color = .systemPurple }
                        else { color = .systemOrange }
                        storage.addAttribute(.foregroundColor, value: color, range: match.range)
                    }
                }
            }
            storage.endEditing()
            view.insertionPointColor = .labelColor
            view.typingAttributes = [.foregroundColor: NSColor.labelColor, .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]
        }
    }
}

private final class JSONLineRuler: NSRulerView {
    weak var textView: NSTextView?
    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 38
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.025).setFill()
        dirtyRect.fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let view = textView, let layout = view.layoutManager, let container = view.textContainer else { return }
        let ns = view.string as NSString
        let visible = layout.glyphRange(forBoundingRect: view.visibleRect, in: container)
        let characters = layout.characterRange(forGlyphRange: visible, actualGlyphRange: nil)
        var location = 0, number = 1
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
        while location < ns.length {
            if location >= characters.location || (location < ns.length && NSMaxRange(ns.lineRange(for: NSRange(location: location, length: 0))) > characters.location) {
                let glyph = layout.glyphIndexForCharacter(at: min(location, max(0, ns.length - 1)))
                if glyph < layout.numberOfGlyphs {
                    let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                    let y = line.minY + view.textContainerInset.height - view.visibleRect.minY
                    if y > bounds.maxY { break }
                    let label = "\(number)" as NSString
                    label.draw(at: NSPoint(x: 30 - label.size(withAttributes: attributes).width, y: y), withAttributes: attributes)
                }
            }
            guard location < ns.length else { break }
            location = NSMaxRange(ns.lineRange(for: NSRange(location: location, length: 0))); number += 1
        }
    }
}

private final class JSONNativeTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "f" {
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            performFindPanelAction(item)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
