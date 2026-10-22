// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import CryptoKit
import ImageIO
import Vision

struct ClipboardEntry: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case text, link, image, files, pdf }
    var id = UUID()
    var timestamp = Date()
    var sourceBundleID: String
    var sourceName: String
    var kind: Kind
    var text: String
    var detail: String
    var checksum: String
    var byteCount: Int
    var isEditable: Bool { kind == .text || kind == .link }
    var fileCount: Int?
    var recognizedText: String? // nil = pending; empty = processed with no text
    func matches(_ query: String, includeOCR: Bool = true) -> Bool {
        query.isEmpty || text.localizedStandardContains(query) || (name ?? "").localizedStandardContains(query) || sourceName.localizedStandardContains(query) || (includeOCR && (recognizedText ?? "").localizedStandardContains(query))
    }
    var localizedDetail: String {
        if kind == .files { let count = fileCount ?? 1; return String(localized: "\(count) files") }
        return kind == .image || kind == .pdf ? detail : String(localized: "\(text.count) characters")
    }
    var name: String?
    var isPinned: Bool { isFavorite || !collectionIDs.isEmpty }
    var isFavorite = false
    var collectionIDs: Set<UUID> = []
}

struct ClipboardCollection: Codable, Identifiable, Equatable, Sendable {
    enum Tint: String, Codable, CaseIterable, Sendable {
        case red = "红色", orange = "橙色", yellow = "黄色", green = "绿色"
        case blue = "蓝色", purple = "紫色", pink = "粉色", gray = "灰色"

        var title: String {
            switch self {
            case .red: String(localized: "Red")
            case .orange: String(localized: "Orange")
            case .yellow: String(localized: "Yellow")
            case .green: String(localized: "Green")
            case .blue: String(localized: "Blue")
            case .purple: String(localized: "Purple")
            case .pink: String(localized: "Pink")
            case .gray: String(localized: "Gray")
            }
        }
    }
    var id = UUID()
    var name: String
    var color: Tint? // Older histories have no color; display them in red.
}

enum ClipboardRetention: Int, CaseIterable, Sendable {
    // Keep the original five stored values so existing settings retain their meaning.
    case day = 0, week = 1, month = 2, year = 3, forever = 4
    case days2 = 5, days3, days4, days5, days6
    case weeks2, weeks3
    case months2, months3, months4, months5, months6, months7, months8, months9, months10, months11

    static let allCases: [Self] = [
        .day, .days2, .days3, .days4, .days5, .days6,
        .week, .weeks2, .weeks3,
        .month, .months2, .months3, .months4, .months5, .months6,
        .months7, .months8, .months9, .months10, .months11, .year, .forever
    ]
    private var index: Int { Self.allCases.firstIndex(of: self)! }
    var title: String {
        switch index {
        case 0...5: return String(localized: "\(index + 1) days")
        case 6...8: return String(localized: "\(index - 5) weeks")
        case 9...19: return String(localized: "\(index - 8) months")
        case 20: return String(localized: "1 year")
        default: return String(localized: "Forever")
        }
    }
    // Five equally spaced landmarks; each unit range has its own finer steps.
    var sliderPosition: Double {
        switch index {
        case 0...5: return Double(index) / 6
        case 6...8: return 1 + Double(index - 6) / 3
        case 9...19: return 2 + Double(index - 9) / 11
        case 20: return 3
        default: return 4
        }
    }
    static func atSliderPosition(_ position: Double) -> Self {
        let value = min(4, max(0, position))
        let index: Int
        switch value {
        case ..<1: index = Int((value * 6).rounded())
        case ..<2: index = 6 + Int(((value - 1) * 3).rounded())
        case ..<3: index = 9 + Int(((value - 2) * 11).rounded())
        default: index = 20 + Int((value - 3).rounded())
        }
        return allCases[index]
    }
    func cutoff(now: Date, calendar: Calendar = .current) -> Date? {
        switch index {
        case 0...5: return calendar.date(byAdding: .day, value: -(index + 1), to: now)
        case 6...8: return calendar.date(byAdding: .day, value: -(index - 5) * 7, to: now)
        case 9...19: return calendar.date(byAdding: .month, value: -(index - 8), to: now)
        case 20: return calendar.date(byAdding: .year, value: -1, to: now)
        default: return nil
        }
    }
}

enum ClipboardPasteTarget: String { case activeApplication, clipboard }

struct ClipboardHistory: Codable, Sendable {
    var entries: [ClipboardEntry] = []
    var collections: [ClipboardCollection] = []

    mutating func expire(retention: ClipboardRetention, now: Date = Date()) {
        guard let cutoff = retention.cutoff(now: now) else { return }
        entries.removeAll { !$0.isPinned && $0.timestamp < cutoff }
    }

    // Favorites are never evicted automatically. Refuse new content if they fill the budget.
    mutating func trim(limit: Int, bytes: Int) -> Bool {
        // ponytail: bounded history uses a linear eviction scan; index it if the cap grows substantially.
        while entries.filter({ !$0.isPinned }).count > limit || entries.reduce(0, { $0 + $1.byteCount }) > bytes {
            guard let index = entries.lastIndex(where: { !$0.isPinned }) else { return false }
            entries.remove(at: index)
        }
        return true
    }
}

struct ClipboardFileReference: Codable, Sendable {
    var url: URL
    var bookmark: Data?

    init(url: URL) {
        self.url = url
        bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolve() throws -> URL {
        var stale = false
        let resolved = bookmark.flatMap {
            try? URL(resolvingBookmarkData: $0, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
        } ?? url
        guard resolved.isFileURL, FileManager.default.isReadableFile(atPath: resolved.path) else {
            throw NSError(domain: "Eave.Clipboard", code: 1, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "File is missing or unavailable: \(url.lastPathComponent)")])
        }
        return resolved
    }
}

struct ClipboardPayload: Codable, Sendable {
    var items: [[String: Data]]
    var files: [ClipboardFileReference]?
    static let supported: [NSPasteboard.PasteboardType] = [.string, .URL, .rtf, .rtfd, .html, .png, .tiff, .pdf, .init("public.jpeg"), .init("public.heic"), .init("com.compuserve.gif")]
    static let privateTypes: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword", "de.petermaurer.TransientPasteboardType"
    ]
    static let ownType = NSPasteboard.PasteboardType("app.eave.clipboard.restore")
    static let maxBytes = 20 * 1024 * 1024

    @MainActor
    static func read(from pasteboard: NSPasteboard) -> ClipboardPayload? {
        guard let originals = pasteboard.pasteboardItems, !originals.isEmpty,
              originals.count <= 32,
              !originals.contains(where: { item in
                  item.types.contains { privateTypes.contains($0.rawValue) || $0 == ownType }
              }) else { return nil }
        if originals.contains(where: { $0.types.contains(.fileURL) }) {
            var files: [ClipboardFileReference] = []
            var formats: [[String: Data]] = []
            var total = 0
            for item in originals {
                guard let data = item.data(forType: .fileURL), data.count <= maxBytes - total,
                      let value = item.string(forType: .fileURL), let url = URL(string: value), url.isFileURL else { return nil }
                let reference = ClipboardFileReference(url: url)
                total += data.count + (reference.bookmark?.count ?? 0)
                guard total <= maxBytes else { return nil }
                files.append(reference)
                formats.append([NSPasteboard.PasteboardType.fileURL.rawValue: data])
            }
            return ClipboardPayload(items: formats, files: files)
        }
        var items: [[String: Data]] = []
        var total = 0
        for original in originals {
            var formats: [String: Data] = [:]
            for type in supported where original.types.contains(type) {
                guard let data = original.data(forType: type) else { continue }
                total += data.count
                guard total <= maxBytes else { return nil }
                formats[type.rawValue] = data
            }
            guard !formats.isEmpty else { return nil }
            items.append(formats)
        }
        return ClipboardPayload(items: items)
    }

    var byteCount: Int { items.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } } }
    var checksum: String {
        var hash = SHA256()
        // Length-prefix both keys and values so item/format boundaries are unambiguous.
        for item in items {
            hash.update(data: Data("item:\(item.count):".utf8))
            for key in item.keys.sorted() {
                let data = item[key]!
                hash.update(data: Data("\(key.utf8.count):\(key):\(data.count):".utf8))
                hash.update(data: data)
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    var plainText: String {
        items.compactMap { item in
            for type in [NSPasteboard.PasteboardType.string, .URL] {
                if let data = item[type.rawValue], let text = String(data: data, encoding: .utf8) { return text }
            }
            // HTML is preserved verbatim, but never imported for previews: its external
            // resources must not cause network requests during background collection.
            for (type, format) in [(NSPasteboard.PasteboardType.rtf, NSAttributedString.DocumentType.rtf), (.rtfd, .rtfd)] {
                if let data = item[type.rawValue],
                   let value = try? NSAttributedString(data: data, options: [.documentType: format], documentAttributes: nil) {
                    return value.string
                }
            }
            if let data = item[NSPasteboard.PasteboardType.html.rawValue], let html = String(data: data, encoding: .utf8) {
                return Self.htmlText(html)
            }
            return nil
        }.joined(separator: "\n")
    }

    // Extract text without loading HTML into WebKit or fetching external resources.
    static func htmlText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "(?is)<(script|style|head)\\b[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<(?:br\\b[^>]*|/(?:p|div|li|h[1-6]|tr)\\s*)>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?s)<!--.*?-->|<[^>]*>", with: "", options: .regularExpression)
        let regex = try! NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);")
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range(at: 1), in: text), let whole = Range(match.range, in: text) else { continue }
            let number = String(text[range])
            if let value = UInt32(number.hasPrefix("x") ? String(number.dropFirst()) : number, radix: number.hasPrefix("x") ? 16 : 10), let scalar = UnicodeScalar(value) { text.replaceSubrange(whole, with: String(scalar)) }
        }
        for (entity, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")] { text = text.replacingOccurrences(of: entity, with: value) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var imageData: Data? {
        for item in items {
            for type in ["public.png", "public.tiff", "public.jpeg", "public.heic", "com.compuserve.gif"] {
                if let data = item[type] { return data }
            }
        }
        return nil
    }
    var previewData: Data? { imageData ?? items.compactMap { $0[NSPasteboard.PasteboardType.pdf.rawValue] }.first }


    func entry(sourceID: String, sourceName: String) -> ClipboardEntry {
        let text = files?.map { $0.url.lastPathComponent }.joined(separator: "\n") ?? plainText
        var kind: ClipboardEntry.Kind = .text
        var detail = String(localized: "\(text.count) characters")
        if let files, !files.isEmpty {
            kind = .files
        } else if let data = imageData, let source = CGImageSourceCreateWithData(data as CFData, nil) {
            kind = .image
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int { detail = "\(width) × \(height)" }
        } else if items.contains(where: { $0[NSPasteboard.PasteboardType.pdf.rawValue] != nil }) {
            kind = .pdf; detail = "PDF"
        } else if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
                  !text.contains(where: { $0.isWhitespace }) { kind = .link }
        var entry = ClipboardEntry(sourceBundleID: sourceID, sourceName: sourceName, kind: kind,
                                   text: text, detail: detail, checksum: checksum, byteCount: 0)
        entry.fileCount = files?.count
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        // Budget encoded content plus searchable metadata, with room for collection IDs and JSON framing.
        entry.byteCount = ((try? encoder.encode(self).count) ?? byteCount)
            + ((try? JSONEncoder().encode(entry).count) ?? text.utf8.count) + 1024
        return entry
    }

    func preparedEntry(sourceID: String, sourceName: String) async throws -> ClipboardEntry {
        let work = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let entry = self.entry(sourceID: sourceID, sourceName: sourceName)
            try Task.checkCancellation()
            return entry
        }
        return try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
    }

    func resolvedFileURLs() throws -> [URL] {
        try (files ?? []).map { try $0.resolve() }
    }

    @MainActor
    func write(to pasteboard: NSPasteboard, plain: Bool) -> Bool {
        if let files, !files.isEmpty {
            guard let urls = try? resolvedFileURLs() else { return false }
            let restored = urls.map { url in
                let item = NSPasteboardItem()
                item.setString(url.absoluteString, forType: .fileURL)
                return item
            }
            restored[0].setString("1", forType: Self.ownType)
            pasteboard.clearContents()
            return pasteboard.writeObjects(restored)
        }
        let restored: [NSPasteboardItem]
        if plain {
            let text = plainText
            guard !text.isEmpty else { return false }
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            restored = [item]
        } else {
            restored = items.map { formats in
                let item = NSPasteboardItem()
                for (type, data) in formats { item.setData(data, forType: .init(type)) }
                return item
            }
        }
        guard !restored.isEmpty else { return false }
        restored[0].setString("1", forType: Self.ownType)
        pasteboard.clearContents()
        return pasteboard.writeObjects(restored)
    }
}

actor ClipboardDiskStore {
    let directory: URL
    private let thumbnails = NSCache<NSUUID, NSData>()
    private var thumbnailVersions: [UUID: UUID] = [:]

    init(directory: URL) {
        self.directory = directory
        thumbnails.totalCostLimit = 16 * 1024 * 1024
        thumbnails.countLimit = 64
    }

    func load() throws -> ClipboardHistory {
        let url = directory.appendingPathComponent("history.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return ClipboardHistory() }
        return try JSONDecoder().decode(ClipboardHistory.self, from: Data(contentsOf: url))
    }

    func payload(_ id: UUID) throws -> ClipboardPayload {
        try PropertyListDecoder().decode(ClipboardPayload.self, from: Data(contentsOf: payloadURL(id)))
    }

    @discardableResult
    func save(_ history: ClipboardHistory, newPayload: (UUID, ClipboardPayload)? = nil) throws -> String? {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        if let (id, payload) = newPayload {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(payload).write(to: payloadURL(id), options: .atomic)
        }
        // Commit metadata before deleting content. Failed saves leave the previous history readable.
        try JSONEncoder().encode(history).write(to: directory.appendingPathComponent("history.json"), options: .atomic)
        let retainedIDs = Set(history.entries.map(\.id))
        for id in Array(thumbnailVersions.keys) where !retainedIDs.contains(id) || newPayload?.0 == id {
            thumbnails.removeObject(forKey: id as NSUUID)
            thumbnailVersions.removeValue(forKey: id)
        }
        let retained = Set(history.entries.map { $0.id.uuidString + ".plist" })
        do {
            for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "plist" && !retained.contains(url.lastPathComponent) {
                try fm.removeItem(at: url)
            }
        } catch {
            return String(localized: "History was saved, but some old content files could not be removed: \(error.localizedDescription)")
        }
        return nil
    }

    func thumbnail(_ id: UUID) async -> Data? {
        guard !Task.isCancelled else { return nil }
        if let cached = thumbnails.object(forKey: id as NSUUID) { return cached as Data }
        guard let data = try? payload(id).imageData, !Task.isCancelled else { return nil }
        let version = thumbnailVersions[id] ?? UUID()
        thumbnailVersions[id] = version
        let work = Task.detached(priority: .utility) { Self.makeThumbnail(data) }
        let result = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
        guard !Task.isCancelled, thumbnailVersions[id] == version, let result else { return nil }
        thumbnails.setObject(result as NSData, forKey: id as NSUUID, cost: result.count)
        return result
    }

    private nonisolated static func makeThumbnail(_ data: Data) -> Data? {
        guard !Task.isCancelled,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 640,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        guard !Task.isCancelled else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), !Task.isCancelled else { return nil }
        return output as Data
    }

    private func payloadURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".plist") }
}

// One bounded image at a time, independent of the disk actor and the UI thread.
enum ClipboardOCR {
    static func recognize(_ data: Data) throws -> String {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"].filter { supported.contains($0) }
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        try Task.checkCancellation()
        return String((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n").prefix(100_000))
    }
}
