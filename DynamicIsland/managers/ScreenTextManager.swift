// SPDX-License-Identifier: GPL-3.0-or-later
// OCR request and clipboard completion adapted from Vorssaint (C) 2026.

import AppKit
import ScreenCaptureKit
import Vision
import OSLog

// Shared by the selection UI and the standalone regression check.
enum ScreenTextRecognition {
    enum Outcome: Equatable {
        case qr(String, URL?)
        case text(String)
    }

    static func openableURL(_ payload: String) -> URL? {
        guard !payload.contains(where: { $0.isWhitespace || $0.isNewline }),
              let url = URL(string: payload),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func joinedLines(_ lines: [String], removeLineBreaks: Bool) -> String {
        guard removeLineBreaks else { return lines.joined(separator: "\n") }
        func joinsTightly(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.value {
            case 0x3000...0x312F, 0x3190...0x9FFF, 0xF900...0xFAFF, 0xFF01...0xFF9F, 0x20000...0x2FA1F: return true
            default: return false
            }
        }
        return lines.reduce(into: "") { result, line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if let last = result.unicodeScalars.last, let first = trimmed.unicodeScalars.first {
                result += joinsTightly(last) && joinsTightly(first) ? "" : " "
            }
            result += trimmed
        }
    }

    static func outcome(in image: CGImage, detectQRCodes: Bool = true, removeLineBreaks: Bool = false) throws -> Outcome {
        if !detectQRCodes { return .text(try text(in: image, removeLineBreaks: removeLineBreaks)) }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let codes = (request.results ?? []).sorted {
            let a = Int(((1 - $0.boundingBox.midY) * 100).rounded())
            let b = Int(((1 - $1.boundingBox.midY) * 100).rounded())
            return a == b ? $0.boundingBox.minX < $1.boundingBox.minX : a < b
        }.compactMap { $0.payloadStringValue }.filter { !$0.isEmpty }
        if !codes.isEmpty {
            let payload = codes.joined(separator: "\n")
            return .qr(payload, codes.count == 1 ? openableURL(payload) : nil)
        }
        return .text(try text(in: image, removeLineBreaks: removeLineBreaks))
    }

    static func pixelRect(_ rect: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let clipped = rect.standardized.intersection(CGRect(origin: .zero, size: viewSize))
        guard !clipped.isNull, !clipped.isEmpty else { return .zero }
        return CGRect(x: clipped.minX * imageSize.width / viewSize.width,
                      y: clipped.minY * imageSize.height / viewSize.height,
                      width: clipped.width * imageSize.width / viewSize.width,
                      height: clipped.height * imageSize.height / viewSize.height)
            .integral.intersection(CGRect(origin: .zero, size: imageSize))
    }

    static func mayCopy(generation: Int, currentGeneration: Int, changeCount: Int, currentChangeCount: Int) -> Bool {
        generation == currentGeneration && changeCount == currentChangeCount
    }

    static func text(in image: CGImage, removeLineBreaks: Bool = false) throws -> String {
        for level: VNRequestTextRecognitionLevel in [.accurate, .fast] {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = level == .accurate
            let supported = try request.supportedRecognitionLanguages()
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"].filter(supported.contains)
            try VNImageRequestHandler(cgImage: image).perform([request])
            // ponytail: row buckets suit ordinary screen text; use column segmentation for document layouts.
            let lines = (request.results ?? []).sorted {
                let leftRow = Int(((1 - $0.boundingBox.midY) * 100).rounded())
                let rightRow = Int(((1 - $1.boundingBox.midY) * 100).rounded())
                return leftRow == rightRow ? $0.boundingBox.minX < $1.boundingBox.minX : leftRow < rightRow
            }.compactMap { $0.topCandidates(1).first?.string }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !lines.isEmpty { return joinedLines(lines, removeLineBreaks: removeLineBreaks) }
        }
        return ""
    }
}

@MainActor
final class ScreenTextManager {
    static let shared = ScreenTextManager()
    private let logger = os.Logger(subsystem: "com.eave.app", category: "ScreenText")
    private var qrPanel: ScreenQRResultPanel?
    private var panels: [NSPanel] = []
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var feedbackPanel: NSPanel?
    private var feedbackTask: Task<Void, Never>?

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "enableScreenText") as? Bool ?? true
    }

    func capture() {
        guard Self.isEnabled else { return }
        cancel()
        guard requestScreenRecordingPermission() else { return }
        for screen in NSScreen.screens {
            guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { continue }
            let panel = ScreenTextPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            let selection = ScreenTextSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            selection.setAccessibilityElement(true)
            selection.setAccessibilityLabel(String(localized: "Drag to copy screen text · Esc to cancel"))
            selection.onSelection = { [weak self] rect in
                self?.recognize(rect: rect, screen: screen, displayID: displayID)
            }
            panel.contentView = selection
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancel(); return nil }
            return event
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancel() }
        }
        panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.makeKey()
    }

    @discardableResult
    func requestScreenRecordingPermission() -> Bool {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            let alert = NSAlert()
            alert.messageText = String(localized: "Screen Recording permission required")
            alert.informativeText = String(localized: "Allow Eave in System Settings → Privacy & Security → Screen Recording, then try again. If macOS asks, restart Eave.")
            alert.addButton(withTitle: String(localized: "Open System Settings"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            return false
        }
        return true
    }

    func cancel() {
        qrPanel?.close()
        qrPanel = nil
        hideFeedback()
        generation += 1
        task?.cancel()
        task = nil
        closeSelection()
    }

    private func closeSelection() {
        panels.forEach { $0.close() }
        panels.removeAll()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    private func recognize(rect: CGRect, screen: NSScreen, displayID: CGDirectDisplayID) {
        let viewSize = screen.frame.size
        let scale = screen.backingScaleFactor
        let requestGeneration = generation
        let changeCount = NSPasteboard.general.changeCount
        let detectQRCodes = UserDefaults.standard.object(forKey: "screenOCRDetectQRCodes") as? Bool ?? true
        let removeLineBreaks = UserDefaults.standard.bool(forKey: "screenOCRRemoveLineBreaks")
        closeSelection()
        task = Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                try Task.checkCancellation()
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw CaptureError.displayUnavailable }
                let ownWindows = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
                let configuration = SCStreamConfiguration()
                let pixelRect = ScreenTextRecognition.pixelRect(rect, viewSize: viewSize,
                    imageSize: CGSize(width: viewSize.width * scale, height: viewSize.height * scale))
                guard pixelRect.width >= 2, pixelRect.height >= 2 else { return }
                configuration.sourceRect = CGRect(x: pixelRect.minX / scale, y: pixelRect.minY / scale,
                    width: pixelRect.width / scale, height: pixelRect.height / scale)
                configuration.width = Int(pixelRect.width)
                configuration.height = Int(pixelRect.height)
                configuration.showsCursor = false
                configuration.colorSpaceName = CGColorSpace.sRGB
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                try Task.checkCancellation()
                self?.showFeedback(String(localized: "Recognizing screen text…"), on: screen)
                let outcome = try await Task.detached(priority: .userInitiated) {
                    try ScreenTextRecognition.outcome(in: image, detectQRCodes: detectQRCodes, removeLineBreaks: removeLineBreaks)
                }.value
                try Task.checkCancellation()
                guard let self, requestGeneration == self.generation else { return }
                let text: String
                switch outcome {
                case .qr(let payload, let url):
                    self.hideFeedback()
                    let panel = ScreenQRResultPanel(payload: payload, url: url)
                    panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - panel.frame.width / 2,
                                                 y: screen.visibleFrame.midY - panel.frame.height / 2))
                    self.qrPanel = panel
                    panel.makeKeyAndOrderFront(nil)
                    self.logger.info("QR recognition completed")
                    return
                case .text(let recognized):
                    text = recognized
                    self.logger.info("Text recognition completed; characters: \(text.count)")
                }
                guard ScreenTextRecognition.mayCopy(generation: requestGeneration, currentGeneration: self.generation,
                    changeCount: changeCount, currentChangeCount: NSPasteboard.general.changeCount) else {
                    self.showFeedback(String(localized: "Clipboard changed; recognized text was not copied."), on: screen)
                    return
                }
                if text.isEmpty {
                    self.showFeedback(String(localized: "No text found in the selected area."), on: screen)
                } else {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    let copied = pasteboard.setString(text, forType: .string)
                    self.showFeedback(copied ? String(localized: "Screen text copied") : String(localized: "Could not copy screen text."), on: screen)
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, requestGeneration == self.generation else { return }
                self.logger.error("Screen recognition failed: \(String(describing: error), privacy: .public)")
                self.showFeedback(String(localized: "Could not read screen text. Check Screen Recording permission and try again."), on: screen)
            }
        }
    }

    private enum CaptureError: Error { case displayUnavailable }

    private func hideFeedback() {
        feedbackTask?.cancel()
        feedbackPanel?.close()
        feedbackPanel = nil
    }

    private func showFeedback(_ message: String, on screen: NSScreen) {
        hideFeedback()
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.alignment = .center
        label.frame = CGRect(x: 18, y: 16, width: 364, height: 46)
        let background = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 400, height: 78))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.addSubview(label)
        let panel = NSPanel(contentRect: background.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.contentView = background
        panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - 200, y: screen.visibleFrame.maxY - 110))
        panel.orderFrontRegardless()
        feedbackPanel = panel
        NSAccessibility.post(element: panel, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        feedbackTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            self?.feedbackPanel?.close()
            self?.feedbackPanel = nil
        }
    }
}

private final class ScreenTextPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class ScreenTextSelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    private var start: CGPoint?
    private var selection = CGRect.zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        start = nil
        if selection.width >= 2, selection.height >= 2 { onSelection?(selection) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()
        if !selection.isEmpty {
            NSColor.clear.setFill()
            selection.fill(using: .copy)
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        }
        let hint = String(localized: "Drag to copy screen text · Esc to cancel")
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.7)]
        let size = (hint as NSString).size(withAttributes: attributes)
        (hint as NSString).draw(at: CGPoint(x: max(8, (bounds.width - size.width) / 2), y: 60), withAttributes: attributes)
    }
}


@MainActor
private final class ScreenQRResultPanel: NSPanel {
    private let payload: String
    private let url: URL?
    private let status = NSTextField(labelWithString: "")

    init(payload: String, url: URL?) {
        self.payload = payload
        self.url = url
        super.init(contentRect: CGRect(x: 0, y: 0, width: 480, height: 300),
                   styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        title = String(localized: "QR code recognized")
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 480, height: 300))
        contentView = content
        let scroll = NSScrollView(frame: CGRect(x: 16, y: 82, width: 448, height: 202))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.font = .systemFont(ofSize: 14)
        text.string = payload
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainerInset = CGSize(width: 8, height: 8)
        text.setAccessibilityLabel(String(localized: "QR code content"))
        scroll.documentView = text
        content.addSubview(scroll)
        status.frame = CGRect(x: 16, y: 48, width: 448, height: 22)
        content.addSubview(status)
        let copy = NSButton(title: String(localized: "Copy"), target: self, action: #selector(copyPayload))
        copy.bezelStyle = .rounded
        copy.frame = CGRect(x: 16, y: 10, width: 100, height: 32)
        content.addSubview(copy)
        if url != nil {
            let open = NSButton(title: String(localized: "Open Link"), target: self, action: #selector(openLink))
            open.bezelStyle = .rounded
            open.frame = CGRect(x: 124, y: 10, width: 120, height: 32)
            content.addSubview(open)
        }
        let close = NSButton(title: String(localized: "Close"), target: self, action: #selector(dismissResult))
        close.bezelStyle = .rounded
        close.keyEquivalent = "\u{1b}"
        close.frame = CGRect(x: 364, y: 10, width: 100, height: 32)
        content.addSubview(close)
    }

    override var canBecomeKey: Bool { true }

    @objc private func copyPayload() {
        NSPasteboard.general.clearContents()
        status.stringValue = NSPasteboard.general.setString(payload, forType: .string)
            ? String(localized: "QR code copied") : String(localized: "Could not copy screen text.")
    }

    @objc private func openLink() {
        guard let url else { return }
        if !NSWorkspace.shared.open(url) { status.stringValue = String(localized: "Could not open link.") }
    }

    @objc private func dismissResult() { close() }
}
