import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

/// Local images only. The WebKit resource handler exposes hash filenames, never source paths.
enum DesktopEmoteLibrary {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.eave.app")
            .appendingPathComponent("DesktopEmotes", isDirectory: true)
    }

    static func importImage(_ url: URL, existing: [DesktopEmoteConfiguration.Custom], directory: URL = directory) throws -> DesktopEmoteConfiguration.Custom {
        guard existing.count < 24 else { throw ImportError.full }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8_388_608 else { throw ImportError.size }
        let data = try Data(contentsOf: url)
        guard data.count <= 8_388_608,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.gif.identifier, UTType.webP.identifier].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, max(width, height) <= 8192 else { throw ImportError.format }
        let animated = CGImageSourceGetCount(source) > 1 && [UTType.gif.identifier, UTType.webP.identifier].contains(type)
        if animated && (data.count > 5_242_880 || max(width, height) > 1024) { throw ImportError.animation }
        if animated {
            guard CGImageSourceGetCount(source) <= 300 else { throw ImportError.animation }
            for index in 0..<CGImageSourceGetCount(source) {
                guard let frame = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                      let w = frame[kCGImagePropertyPixelWidth] as? Int, let h = frame[kCGImagePropertyPixelHeight] as? Int,
                      w > 0, h > 0, max(w, h) <= 1024 else { throw ImportError.animation }
            }
        }
        let hash = SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
        guard !existing.contains(where: { $0.id == "c:" + hash }) else { throw ImportError.duplicate }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 160,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw ImportError.format }
        let ext = animated ? (type == UTType.gif.identifier ? "gif" : "webp") : nil
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let still = directory.appendingPathComponent(hash + ".png")
        let animation = ext.map { directory.appendingPathComponent(hash + "." + $0) }
        do {
            if let animation { try data.write(to: animation, options: .atomic) }
            try png.write(to: still, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: still)
            if let animation { try? FileManager.default.removeItem(at: animation) }
            throw error
        }
        let name = String(url.deletingPathExtension().lastPathComponent.filter { !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }.prefix(24))
        return .init(id: "c:" + hash, name: name.isEmpty ? hash : name, animation: ext)
    }

    static func remove(_ item: DesktopEmoteConfiguration.Custom, directory: URL = directory) {
        guard item.valid else { return }
        for ext in ["png", "gif", "webp"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(item.id.dropFirst(2)).\(ext)"))
        }
    }

    enum ImportError: LocalizedError {
        case full, size, format, animation, duplicate
        var errorDescription: String? {
            switch self {
            case .full: return String(localized: "You can import up to 24 emotes.")
            case .size: return String(localized: "Choose an image no larger than 8 MB.")
            case .format: return String(localized: "Choose a PNG, JPEG, GIF or WebP image up to 8192 pixels per side.")
            case .animation: return String(localized: "Animated emotes must be no larger than 5 MB, 1024 pixels per side and 300 frames.")
            case .duplicate: return String(localized: "This image is already in your emote library.")
            }
        }
    }
}
