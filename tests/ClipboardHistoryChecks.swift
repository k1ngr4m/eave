// Run with scripts/test-clipboard.sh. Uses a private pasteboard and temporary history only.
import AppKit
import ImageIO

// Standalone store checks do not create windows or register global shortcuts.
@MainActor
final class ClipboardPanelController {
    static let shared = ClipboardPanelController()
    private(set) var dismissals = 0
    func dismiss() { dismissals += 1 }
}

@main
struct ClipboardHistoryChecks {
    @MainActor
    static func main() async throws {
        let pasteboard = NSPasteboard(name: .init("app.eave.clipboard.test.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("你好 Eave", forType: .string)
        let rtf = Data("{\\rtf1\\ansi rich text}".utf8)
        item.setData(rtf, forType: .rtf)
        pasteboard.writeObjects([item])
        let payload = ClipboardPayload.read(from: pasteboard)!
        assert(payload.plainText == "你好 Eave")
        assert(payload.items[0][NSPasteboard.PasteboardType.rtf.rawValue] == rtf)
        assert(payload.write(to: pasteboard, plain: false))
        assert(pasteboard.data(forType: .rtf) == rtf)
        assert(ClipboardPayload.read(from: pasteboard) == nil, "Restores must not create a recording loop")
        assert(payload.write(to: pasteboard, plain: true))
        assert(pasteboard.string(forType: .string) == "你好 Eave")
        assert(pasteboard.data(forType: .rtf) == nil)
        for type in ClipboardPayload.privateTypes.union([NSPasteboard.PasteboardType.fileURL.rawValue]) {
            pasteboard.clearContents()
            let sensitive = NSPasteboardItem()
            sensitive.setString("secret", forType: .string)
            sensitive.setString("1", forType: .init(type))
            pasteboard.writeObjects([sensitive])
            assert(ClipboardPayload.read(from: pasteboard) == nil, "Must reject \(type) before reading content")
        }
        let fileDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: fileDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fileDirectory) }
        let fileURL = fileDirectory.appendingPathComponent("你好.txt")
        try Data("original".utf8).write(to: fileURL)
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL, fileDirectory as NSURL])
        let filePayload = ClipboardPayload.read(from: pasteboard)!
        let fileEntry = filePayload.entry(sourceID: "Finder", sourceName: "Finder")
        assert(fileEntry.kind == .files && fileEntry.fileCount == 2 && !fileEntry.isEditable)
        assert(fileEntry.text.contains("你好.txt"))
        assert(filePayload.write(to: pasteboard, plain: true), "Always-plain must preserve file semantics")
        assert(pasteboard.pasteboardItems?.count == 2)
        let restoredFile = URL(string: pasteboard.pasteboardItems!.first!.string(forType: .fileURL)!)!
        assert(restoredFile.resolvingSymlinksInPath() == fileURL.resolvingSymlinksInPath())
        let encodedFiles = try PropertyListEncoder().encode(filePayload)
        let decodedFiles = try PropertyListDecoder().decode(ClipboardPayload.self, from: encodedFiles)
        let resolvedFiles = try decodedFiles.resolvedFileURLs()
        assert(resolvedFiles.count == 2)
        let movedFile = fileDirectory.appendingPathComponent("renamed.txt")
        try FileManager.default.moveItem(at: fileURL, to: movedFile)
        let movedReferences = try decodedFiles.resolvedFileURLs()
        assert(movedReferences.first?.resolvingSymlinksInPath() == movedFile.resolvingSymlinksInPath(), "Bookmarks must follow a renamed file")
        try FileManager.default.removeItem(at: movedFile)
        let beforeMissingCopy = pasteboard.changeCount
        assert(!decodedFiles.write(to: pasteboard, plain: false))
        assert(pasteboard.changeCount == beforeMissingCopy, "Missing files must not destroy the current clipboard")
        print("File reference checks passed: multiple files, folder, serialization, plain-mode bypass, and missing-file atomicity.")
        let reordered = ClipboardPayload(items: [[NSPasteboard.PasteboardType.rtf.rawValue: rtf,
                                                  NSPasteboard.PasteboardType.string.rawValue: Data("你好 Eave".utf8)]])
        assert(payload.checksum == reordered.checksum)
        assert(payload.checksum != ClipboardPayload(items: [["public.utf8-plain-text": Data("other".utf8)]]).checksum)
        let multi = ClipboardPayload(items: [["public.utf8-plain-text": Data("one".utf8)], ["public.utf8-plain-text": Data("two".utf8)]])
        assert(multi.plainText == "one\ntwo")
        assert(multi.write(to: pasteboard, plain: false))
        assert(pasteboard.pasteboardItems?.count == 2)
        let urlPayload = ClipboardPayload(items: [[NSPasteboard.PasteboardType.URL.rawValue: Data("https://example.com".utf8)]])
        assert(urlPayload.entry(sourceID: "app", sourceName: "App").kind == .link)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = bitmap.representation(using: .png, properties: [:])!
        let imagePayload = ClipboardPayload(items: [[NSPasteboard.PasteboardType.png.rawValue: png]])
        let imageEntry = imagePayload.entry(sourceID: "app", sourceName: "App")
        assert(imageEntry.kind == .image && imageEntry.detail == "8 × 4")
        assert(!imagePayload.write(to: pasteboard, plain: true), "Images without text must not clear the clipboard")
        assert(pasteboard.pasteboardItems?.count == 2)
        let html = "<html><head><style>hidden</style></head><body><p>Hello &amp; &#x4E2D;&#25991;</p><script>bad()</script><img src='https://invalid.example/image'></body></html>"
        let htmlPayload = ClipboardPayload(items: [[NSPasteboard.PasteboardType.html.rawValue: Data(html.utf8)]])
        assert(htmlPayload.plainText == "Hello & 中文")
        assert(htmlPayload.write(to: pasteboard, plain: false))
        assert(pasteboard.data(forType: .html) == Data(html.utf8))
        let jpeg = bitmap.representation(using: .jpeg, properties: [:])!
        let jpegPayload = ClipboardPayload(items: [["public.jpeg": jpeg]])
        assert(jpegPayload.entry(sourceID: "app", sourceName: "App").kind == .image)
        assert(jpegPayload.write(to: pasteboard, plain: false))
        assert(pasteboard.data(forType: .init("public.jpeg")) == jpeg)
        let codecBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for type in ["com.compuserve.gif", "public.heic"] {
            let encoded = NSMutableData()
            let destination = CGImageDestinationCreateWithData(encoded, type as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, codecBitmap.cgImage!, nil)
            assert(CGImageDestinationFinalize(destination))
            let input = NSPasteboardItem(); input.setData(encoded as Data, forType: .init(type))
            pasteboard.clearContents(); pasteboard.writeObjects([input])
            let captured = ClipboardPayload.read(from: pasteboard)!
            assert(captured.entry(sourceID: "test", sourceName: "Test").kind == .image)
            assert(NSImage(data: captured.previewData!) != nil)
            assert(captured.write(to: pasteboard, plain: false))
            assert(pasteboard.data(forType: .init(type)) == encoded as Data)
        }
        let rich = NSAttributedString(string: "Rich 中文", attributes: [.font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: NSColor.red])
        let rtfd = try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
        let rtfdPayload = ClipboardPayload(items: [[NSPasteboard.PasteboardType.rtfd.rawValue: rtfd]])
        assert(rtfdPayload.plainText == "Rich 中文")
        assert(rtfdPayload.write(to: pasteboard, plain: false))
        assert(pasteboard.data(forType: .rtfd) == rtfd)
        let nativeEditor = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        nativeEditor.isRichText = true
        assert(nativeEditor.readSelection(from: pasteboard, type: .rtfd))
        assert(nativeEditor.string == "Rich 中文")
        assert(nativeEditor.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == NSColor.red)

        let pdfData = NSMutableData()
        var pdfBounds = CGRect(x: 0, y: 0, width: 240, height: 120)
        let pdfContext = CGContext(consumer: CGDataConsumer(data: pdfData)!, mediaBox: &pdfBounds, nil)!
        pdfContext.beginPDFPage(nil)
        pdfContext.setFillColor(NSColor.red.cgColor)
        pdfContext.fill(CGRect(x: 10, y: 10, width: 80, height: 50))
        pdfContext.endPDFPage(); pdfContext.closePDF()
        let pdfItem = NSPasteboardItem()
        pdfItem.setData(pdfData as Data, forType: .pdf)
        pasteboard.clearContents(); pasteboard.writeObjects([pdfItem])
        let pdfPayload = ClipboardPayload.read(from: pasteboard)!
        assert(pdfPayload.entry(sourceID: "test", sourceName: "Test").kind == .pdf)
        assert(NSImage(data: pdfPayload.previewData!) != nil)
        assert(pdfPayload.write(to: pasteboard, plain: false))
        assert(pasteboard.data(forType: .pdf) == pdfData as Data)
        assert(!pdfPayload.write(to: pasteboard, plain: true))
        for (type, data) in [(NSPasteboard.PasteboardType.init("public.jpeg"), jpeg), (.rtfd, rtfd), (.html, Data(html.utf8))] {
            let input = NSPasteboardItem(); input.setData(data, forType: type)
            pasteboard.clearContents(); pasteboard.writeObjects([input])
            let captured = ClipboardPayload.read(from: pasteboard)!
            let decoded = try PropertyListDecoder().decode(ClipboardPayload.self, from: PropertyListEncoder().encode(captured))
            assert(decoded.write(to: pasteboard, plain: false))
            assert(pasteboard.data(forType: type) == data)
        }
        // Render an actual text image and run Vision, rather than mocking OCR results.
        let ocrImage = NSImage(size: NSSize(width: 1000, height: 220))
        ocrImage.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1000, height: 220).fill()
        ("EAVE CLIPBOARD 2026" as NSString).draw(at: NSPoint(x: 30, y: 110), withAttributes: [.font: NSFont.systemFont(ofSize: 54), .foregroundColor: NSColor.black])
        ("剪贴板文字搜索" as NSString).draw(at: NSPoint(x: 30, y: 30), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
        ocrImage.unlockFocus()
        let ocrData = ocrImage.tiffRepresentation!
        let recognized = try await Task.detached { try ClipboardOCR.recognize(ocrData) }.value
        assert(recognized.contains("EAVE") && recognized.contains("2026") && recognized.contains("文字"), recognized)
        var ocrEntry = imageEntry
        ocrEntry.recognizedText = recognized
        assert(ocrEntry.matches("EAVE") && !ocrEntry.matches("EAVE", includeOCR: false))
        var legacyEntry = try JSONSerialization.jsonObject(with: JSONEncoder().encode(imageEntry)) as! [String: Any]
        legacyEntry.removeValue(forKey: "fileCount"); legacyEntry.removeValue(forKey: "recognizedText")
        let oldEntry = try JSONDecoder().decode(ClipboardEntry.self, from: JSONSerialization.data(withJSONObject: legacyEntry))
        assert(oldEntry.recognizedText == nil && oldEntry.fileCount == nil && oldEntry.id == imageEntry.id)
        print("Format and OCR checks passed: HTML extraction, JPEG/RTFD round trips, real bilingual Vision recognition, search switch, and legacy entry decoding.")
        var first = payload.entry(sourceID: "app", sourceName: "App")
        first.isFavorite = true
        let second = multi.entry(sourceID: "app", sourceName: "App")
        let third = urlPayload.entry(sourceID: "app", sourceName: "App")
        var history = ClipboardHistory(entries: [third, second, first])
        assert(history.trim(limit: 1, bytes: 1_000_000))
        assert(history.entries.map(\.id) == [third.id, first.id], "Oldest ordinary history is evicted, favorites retained")
        var full = ClipboardHistory(entries: [first])
        assert(!full.trim(limit: 100, bytes: 1), "Never silently evict favorites")
        assert(full.entries.count == 1)
        let now = ISO8601DateFormatter().date(from: "2024-03-31T12:00:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        assert(ClipboardRetention.allCases.count == 22)
        assert(Set(ClipboardRetention.allCases.map(\.title)).count == 22)
        for value in ClipboardRetention.allCases {
            assert(ClipboardRetention.atSliderPosition(value.sliderPosition) == value)
            assert(ClipboardRetention(rawValue: value.rawValue) == value)
        }
        assert((0...4).compactMap(ClipboardRetention.init(rawValue:)) == [.day, .week, .month, .year, .forever])
        assert(ClipboardRetention.atSliderPosition(1.67) == .weeks3)
        assert(ClipboardRetention.atSliderPosition(2.55) == .months7)
        assert(ClipboardRetention.weeks3.cutoff(now: now, calendar: calendar) == calendar.date(byAdding: .day, value: -21, to: now))
        assert(ClipboardRetention.months11.cutoff(now: now, calendar: calendar) == calendar.date(byAdding: .month, value: -11, to: now))
        let monthCutoff = ClipboardRetention.month.cutoff(now: now, calendar: calendar)!
        assert(calendar.component(.day, from: monthCutoff) == 29, "Month retention must handle leap-year boundaries")
        assert(ClipboardRetention.forever.cutoff(now: now) == nil)
        for retention in ClipboardRetention.allCases where retention != .forever {
            let cutoff = retention.cutoff(now: now)!
            var old = second
            old.timestamp = cutoff.addingTimeInterval(-1)
            var boundary = third
            boundary.timestamp = cutoff
            var pinned = first
            pinned.timestamp = Date.distantPast
            var expiring = ClipboardHistory(entries: [boundary, old, pinned])
            expiring.expire(retention: retention, now: now)
            assert(expiring.entries.map(\.id) == [boundary.id, pinned.id])
            expiring = ClipboardHistory(entries: [old])
            expiring.expire(retention: .forever, now: now)
            assert(expiring.entries.count == 1)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("eave-clipboard-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = ClipboardDiskStore(directory: directory)
        let empty = try await disk.load()
        assert(empty.entries.isEmpty)
        let collection = ClipboardCollection(name: "参考")
        first.collectionIDs.insert(collection.id)
        let saved = ClipboardHistory(entries: [first], collections: [collection])
        try await disk.save(saved, newPayload: (first.id, payload))
        let loaded = try await disk.load()
        assert(loaded.entries == saved.entries && loaded.collections == saved.collections)
        let restored = try await disk.payload(first.id)
        assert(restored.items == payload.items)
        try await disk.save(ClipboardHistory(entries: [first, imageEntry], collections: [collection]),
                            newPayload: (imageEntry.id, imagePayload))
        let thumbnail = await disk.thumbnail(imageEntry.id)
        assert(thumbnail != nil)
        try await disk.save(ClipboardHistory())
        assert(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(first.id.uuidString + ".plist").path))
        try Data("corrupt".utf8).write(to: directory.appendingPathComponent("history.json"))
        do { _ = try await disk.load(); fatalError("Corruption must be reported, never silently replace history") }
        catch is DecodingError { }
        let suite = "app.eave.clipboard.tests.\(UUID())"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(false, forKey: "clipboardEnabled")
        let store = ClipboardHistoryStore(defaults: preferences, directory: directory.appendingPathComponent("settings"))
        assert(!store.enabled)
        store.soundEffects = false
        store.pasteTarget = .clipboard
        store.alwaysPlainText = true
        store.retention = .forever
        store.enabled = false
        assert(ClipboardPanelController.shared.dismissals > 0)
        let copied = await store.copy(first.id, plain: false)
        assert(!copied, "Disabled clipboard must reject copy before reading/writing payloads")
        store.excludedApps = "com.example.first, com.example.second\ncom.example.first"
        assert(store.excludedApplicationIDs == ["com.example.first", "com.example.second"])
        store.ignoreApplications(["com.example.second", "com.example.third", ""])
        assert(store.excludedApplicationIDs == ["com.example.first", "com.example.second", "com.example.third"])
        store.removeIgnoredApplication("com.example.second")
        assert(store.excludedApplicationIDs == ["com.example.first", "com.example.third"])
        let reopened = ClipboardHistoryStore(defaults: preferences, directory: directory)
        assert(reopened.excludedApplicationIDs == store.excludedApplicationIDs)
        assert(!reopened.enabled && !reopened.soundEffects && reopened.alwaysPlainText)
        assert(reopened.pasteTarget == .clipboard && reopened.retention == .forever)
        let ocrDirectory = directory.appendingPathComponent("ocr")
        let ocrDisk = ClipboardDiskStore(directory: ocrDirectory)
        let ocrPayload = ClipboardPayload(items: [[NSPasteboard.PasteboardType.tiff.rawValue: ocrData]])
        let pendingOCR = ocrPayload.entry(sourceID: "test", sourceName: "Test")
        try await ocrDisk.save(ClipboardHistory(entries: [pendingOCR]), newPayload: (pendingOCR.id, ocrPayload))
        let ocrStore = ClipboardHistoryStore(defaults: preferences, directory: ocrDirectory)
        ocrStore.start() // disabled recorder: no general pasteboard access
        for _ in 0..<100 where ocrStore.history.entries.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        ocrStore.ocrEnabled = false
        ocrStore.processOCR()
        assert(ocrStore.history.entries.first?.recognizedText == nil)
        ocrStore.ocrEnabled = true
        for _ in 0..<600 where ocrStore.history.entries.first?.recognizedText == nil || ocrStore.busy {
            ocrStore.processOCR()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        assert(ocrStore.history.entries.first?.recognizedText?.contains("EAVE") == true)
        let indexedHistory = try await ocrDisk.load()
        assert(indexedHistory.entries.first?.recognizedText?.contains("文字") == true)
        let retainedPayload = try await ocrDisk.payload(pendingOCR.id)
        assert(retainedPayload.imageData == ocrData, "OCR must not replace the image payload")
        ocrStore.clear()
        for _ in 0..<100 where ocrStore.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        ocrStore.processOCR()
        assert(ocrStore.history.entries.isEmpty)
        ocrStore.stop()
        print("OCR integration passed: old-image backfill, opt-out, persisted index, original image retained, and deletion.")
        // Legacy collection metadata remains readable, and edits preserve membership/payloads.
        let legacy = Data("{\"id\":\"\(collection.id.uuidString)\",\"name\":\"参考\"}".utf8)
        let decoded = try JSONDecoder().decode(ClipboardCollection.self, from: legacy)
        assert(decoded.color == nil && decoded.id == collection.id)
        let collectionDirectory = directory.appendingPathComponent("collections")
        let collectionDisk = ClipboardDiskStore(directory: collectionDirectory)
        try await collectionDisk.save(saved, newPayload: (first.id, payload))
        let collectionStore = ClipboardHistoryStore(defaults: preferences, directory: collectionDirectory)
        collectionStore.start()
        for _ in 0..<100 where collectionStore.history.collections.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        collectionStore.stop()
        assert(collectionStore.history.collections.count == 1)
        collectionStore.renameCollection(collection.id, to: "  实用链接  ")
        while collectionStore.busy { try await Task.sleep(for: .milliseconds(10)) }
        collectionStore.setCollectionColor(collection.id, to: .purple)
        while collectionStore.busy { try await Task.sleep(for: .milliseconds(10)) }
        let edited = try await collectionDisk.load()
        assert(edited.collections[0].name == "实用链接" && edited.collections[0].color == .purple)
        assert(edited.entries == saved.entries)
        collectionStore.renameCollection(collection.id, to: "   ")
        assert(!collectionStore.busy && collectionStore.history.collections[0].name == "实用链接")
        collectionStore.deleteCollection(collection.id)
        while collectionStore.busy { try await Task.sleep(for: .milliseconds(10)) }
        let deleted = try await collectionDisk.load()
        assert(deleted.collections.isEmpty && deleted.entries.count == saved.entries.count)
        assert(deleted.entries[0].collectionIDs.isEmpty)
        let preservedPayload = try await collectionDisk.payload(first.id)
        assert(preservedPayload.items == payload.items)
        let menuDirectory = directory.appendingPathComponent("item-menu")
        let menuDisk = ClipboardDiskStore(directory: menuDirectory)
        try await menuDisk.save(saved, newPayload: (first.id, payload))
        let menuStore = ClipboardHistoryStore(defaults: preferences, directory: menuDirectory)
        menuStore.start()
        for _ in 0..<100 where menuStore.history.entries.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        menuStore.stop()
        menuStore.update(first.id) { $0.name = "My reference" }
        while menuStore.busy { try await Task.sleep(for: .milliseconds(10)) }
        let renamedPayload = try await menuDisk.payload(first.id)
        assert(renamedPayload.items == payload.items, "Renaming must not alter copied content")
        let editedID = await menuStore.editText(first.id, text: "https://example.com/edited")
        assert(editedID != nil && editedID != first.id)
        let editedHistory = try await menuDisk.load()
        let editedEntry = editedHistory.entries[0]
        assert(editedEntry.name == "My reference" && editedEntry.kind == .link)
        assert(editedEntry.timestamp == first.timestamp && editedEntry.collectionIDs == first.collectionIDs)
        assert(editedEntry.isFavorite == first.isFavorite)
        let editedPayload = try await menuDisk.payload(editedEntry.id)
        assert(editedPayload.write(to: pasteboard, plain: false))
        assert(pasteboard.string(forType: .string) == "https://example.com/edited")
        assert(pasteboard.data(forType: .rtf) == nil, "Editing must not leave stale rich-text data")
        let oversized = await menuStore.editText(editedEntry.id, text: String(repeating: "a", count: ClipboardPayload.maxBytes + 1))
        assert(oversized == nil && menuStore.history.entries[0] == editedEntry)
        // Simulate a metadata write failure: the old payload and in-memory item must survive.
        let metadataURL = menuDirectory.appendingPathComponent("history.json")
        try FileManager.default.removeItem(at: metadataURL)
        try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: false)
        let failed = await menuStore.editText(editedEntry.id, text: "must not replace the original")
        assert(failed == nil && menuStore.history.entries[0] == editedEntry && !menuStore.busy)
        let intactPayload = try await menuDisk.payload(editedEntry.id)
        assert(intactPayload.items == editedPayload.items)
        var pinned = first
        pinned.isFavorite = false
        pinned.timestamp = now.addingTimeInterval(-10 * 86400)
        var pinnedHistory = ClipboardHistory(entries: [pinned], collections: [collection])
        pinnedHistory.expire(retention: .day, now: now)
        assert(pinnedHistory.entries.count == 1)
        assert(!pinnedHistory.trim(limit: 0, bytes: 1), "Collection pins must survive expiry and capacity cleanup")
        print("Item menu checks passed: rename, editable payloads, pin retention, size limits, and failed-save recovery.")
        let usageDirectory = directory.appendingPathComponent("recent-use")
        let usageDisk = ClipboardDiskStore(directory: usageDirectory)
        let usagePayloads = ["first", "second", "third"].map {
            ClipboardPayload(items: [[NSPasteboard.PasteboardType.string.rawValue: Data($0.utf8)]])
        }
        var usageHistory = ClipboardHistory(collections: [collection])
        for payload in usagePayloads {
            var entry = payload.entry(sourceID: "test", sourceName: "Test")
            entry.isFavorite = true
            entry.collectionIDs = [collection.id]
            usageHistory.entries.append(entry)
            try await usageDisk.save(usageHistory, newPayload: (entry.id, payload))
        }
        let usageStore = ClipboardHistoryStore(defaults: preferences, directory: usageDirectory)
        usageStore.start()
        for _ in 0..<100 where usageStore.history.entries.count != 3 { try await Task.sleep(for: .milliseconds(10)) }
        usageStore.paused = true
        usageStore.enabled = true
        usageStore.stop()
        let ids = usageHistory.entries.map(\.id)
        let used = await usageStore.copy(ids[2], plain: false, to: pasteboard)
        assert(used && pasteboard.string(forType: .string) == "third")
        while usageStore.busy { try await Task.sleep(for: .milliseconds(10)) }
        assert(usageStore.history.entries.map(\.id) == [ids[2], ids[0], ids[1]])
        assert(usageStore.history.entries[0] == usageHistory.entries[2], "Using an item must preserve its metadata")
        let plainUsed = await usageStore.copy(ids[1], plain: true, to: pasteboard)
        let reused = await usageStore.copy(ids[0], plain: false, to: pasteboard)
        assert(plainUsed && reused)
        while usageStore.busy { try await Task.sleep(for: .milliseconds(10)) }
        let persistedUsage = try await usageDisk.load()
        assert(persistedUsage.entries.map(\.id) == [ids[0], ids[1], ids[2]], "Persist the order of successive uses")
        let cancelledUse = await usageStore.copy(ids[2], plain: false, to: pasteboard, ifCurrent: { false })
        let missingUse = await usageStore.copy(UUID(), plain: false, to: pasteboard)
        assert(!cancelledUse && !missingUse)
        assert(usageStore.history.entries == persistedUsage.entries, "Failed or cancelled copies must not reorder history")
        usageStore.enabled = false
        print("Recent-use checks passed: normal/plain copies, metadata, successive uses, persistence and failed-copy ordering.")
        print("Collection checks passed: legacy metadata, rename, color persistence, and deletion preserving entries.")
        print("Clipboard settings checks passed: calendar retention, expiry boundary, favorites, permanent history, disabled copy and persisted preferences.")
        print("Clipboard checks passed: formats, private types, restore suppression, multi-item, dedup key, retention, persistence and deletion.")
    }
}
