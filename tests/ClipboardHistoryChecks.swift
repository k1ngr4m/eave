// Run with scripts/test-clipboard.sh. Uses a private pasteboard and temporary history only.
import AppKit

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
        assert(ClipboardRetention.allCases.map(\.title) ==
            (1...6).map { "\($0)天" } + (1...3).map { "\($0)周" } +
            (1...11).map { "\($0)个月" } + ["1年", "永久"])
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
        let reopened = ClipboardHistoryStore(defaults: preferences, directory: directory)
        assert(!reopened.enabled && !reopened.soundEffects && reopened.alwaysPlainText)
        assert(reopened.pasteTarget == .clipboard && reopened.retention == .forever)
        print("Clipboard settings checks passed: calendar retention, expiry boundary, favorites, permanent history, disabled copy and persisted preferences.")
        print("Clipboard checks passed: formats, private types, restore suppression, multi-item, dedup key, retention, persistence and deletion.")
    }
}
