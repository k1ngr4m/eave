// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Combine

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let shared = ClipboardHistoryStore()
    @Published private(set) var history = ClipboardHistory()
    @Published private(set) var busy = false
    @Published var message: String?
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "clipboardEnabled")
            if enabled { lastChange = NSPasteboard.general.changeCount; start() }
            else { stop(); ClipboardPanelController.shared.dismiss() }
        }
    }
    @Published var ocrEnabled: Bool {
        didSet {
            defaults.set(ocrEnabled, forKey: "clipboardOCREnabled")
            if !ocrEnabled { cancelOCR() }
        }
    }
    private var ocrTask: Task<Void, Never>?
    private var ocrGeneration = UUID()
    private var ocrEntryID: UUID?
    private var ocrResult: (UUID, String)?
    private var ocrFailures: Set<UUID> = []
    @Published var soundEffects: Bool { didSet { defaults.set(soundEffects, forKey: "clipboardSoundEffects") } }
    @Published var pasteTarget: ClipboardPasteTarget { didSet { defaults.set(pasteTarget.rawValue, forKey: "clipboardPasteTarget") } }
    @Published var alwaysPlainText: Bool { didSet { defaults.set(alwaysPlainText, forKey: "clipboardAlwaysPlainText") } }
    @Published var retention: ClipboardRetention {
        didSet { defaults.set(retention.rawValue, forKey: "clipboardRetention"); applyLimits() }
    }
    @Published var paused: Bool { didSet { defaults.set(paused, forKey: "clipboardPaused") } }
    @Published var itemLimit: Int { didSet { defaults.set(itemLimit, forKey: "clipboardItemLimit") } }
    @Published var capacityMB: Int { didSet { defaults.set(capacityMB, forKey: "clipboardCapacityMB") } }
    @Published var excludedApps: String { didSet { defaults.set(excludedApps, forKey: "clipboardExcludedApps") } }
    var excludedApplicationIDs: [String] {
        Array(Set(excludedApps.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init))).sorted()
    }

    func ignoreApplications(_ ids: [String]) {
        excludedApps = Array(Set(excludedApplicationIDs + ids.filter { !$0.isEmpty })).sorted().joined(separator: "\n")
    }

    func removeIgnoredApplication(_ id: String) {
        excludedApps = excludedApplicationIDs.filter { $0 != id }.joined(separator: "\n")
    }

    private let defaults: UserDefaults
    let disk: ClipboardDiskStore
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private var ready = false
    private var loading = false
    private var limitsPending = false
    private var pendingPromotions: [UUID] = []
    private var nextExpiryCheck = Date.distantPast
    private var unavailable = false
    private var observers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        ocrEnabled = defaults.object(forKey: "clipboardOCREnabled") as? Bool ?? true
        enabled = defaults.object(forKey: "clipboardEnabled") as? Bool ?? true
        soundEffects = defaults.object(forKey: "clipboardSoundEffects") as? Bool ?? true
        pasteTarget = ClipboardPasteTarget(rawValue: defaults.string(forKey: "clipboardPasteTarget") ?? "") ?? .activeApplication
        alwaysPlainText = defaults.bool(forKey: "clipboardAlwaysPlainText")
        retention = ClipboardRetention(rawValue: defaults.object(forKey: "clipboardRetention") as? Int ?? ClipboardRetention.month.rawValue) ?? .month
        paused = defaults.bool(forKey: "clipboardPaused")
        itemLimit = defaults.object(forKey: "clipboardItemLimit") as? Int ?? 500
        capacityMB = defaults.object(forKey: "clipboardCapacityMB") as? Int ?? 250
        excludedApps = defaults.string(forKey: "clipboardExcludedApps") ?? "com.1password.1password\ncom.agilebits.onepassword7\ncom.bitwarden.desktop"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        disk = ClipboardDiskStore(directory: directory ?? support.appendingPathComponent("Eave/Clipboard", isDirectory: true))
    }

    func start() {
        guard timer == nil else { return }
        if !ready && !loading {
            loading = true
            Task {
                defer { loading = false }
                do {
                    history = try await disk.load()
                    ready = true
                    if enabled { applyLimits() }
                } catch {
                    message = String(localized: "Clipboard history could not be read. Recording stopped to protect existing data: \(error.localizedDescription)")
                }
            }
        }
        guard enabled else { return }
        if ready { applyLimits() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer?.tolerance = 0.1
        let lockCenter = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservers.append(lockCenter.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.unavailable = locked
                    self?.lastChange = NSPasteboard.general.changeCount
                    if locked { ClipboardPanelController.shared.dismiss() }
                }
            })
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.unavailable = true
                    ClipboardPanelController.shared.dismiss()
                }
            })
        }
        for name in [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.lastChange = NSPasteboard.general.changeCount
                    self?.unavailable = false
                }
            })
        }
    }

    func stop() {
        cancelOCR()
        timer?.invalidate()
        timer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        for observer in lockObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        lockObservers.removeAll()
    }

    func requestReadAccess() {
        guard enabled else { return }
        // Explicit user action, never repeatedly trigger an access prompt from the polling timer.
        _ = NSPasteboard.general.string(forType: .string)
        lastChange = -1
        poll()
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard enabled, ready, !busy else { return }
        if Date() >= nextExpiryCheck {
            nextExpiryCheck = Date().addingTimeInterval(60)
            applyLimits()
            if busy { return }
        }
        guard !paused, !unavailable else { lastChange = pasteboard.changeCount; return }
        processOCR()
        if busy { return }
        let change = pasteboard.changeCount
        guard change != lastChange else { return }
        if #available(macOS 15.4, *) {
            if pasteboard.accessBehavior == .alwaysDeny || pasteboard.accessBehavior == .ask {
                message = String(localized: "Clipboard access is required. Grant access in clipboard settings, or allow Eave to paste from other apps in System Settings.")
                return
            }
        }
        let app = NSWorkspace.shared.frontmostApplication
        let sourceID = app?.bundleIdentifier ?? ""
        guard !excludedApplicationIDs.contains(sourceID) else { lastChange = change; return }
        guard let payload = ClipboardPayload.read(from: pasteboard) else { lastChange = change; return }
        guard pasteboard.changeCount == change else { return }
        lastChange = change
        var candidate = history
        var entry = payload.entry(sourceID: sourceID, sourceName: app?.localizedName ?? "")
        var newPayload: (UUID, ClipboardPayload)? = (entry.id, payload)
        if let index = candidate.entries.firstIndex(where: { $0.checksum == entry.checksum }) {
            let previous = candidate.entries.remove(at: index)
            entry.id = previous.id
            entry.name = previous.name
            entry.isFavorite = previous.isFavorite
            entry.collectionIDs = previous.collectionIDs
            entry.recognizedText = previous.recognizedText
            entry.byteCount += previous.recognizedText?.utf8.count ?? 0
            newPayload = payload.files == nil ? nil : (entry.id, payload)
        }
        candidate.entries.insert(entry, at: 0)
        candidate.expire(retention: retention)
        guard candidate.trim(limit: max(1, itemLimit), bytes: max(1, capacityMB) * 1024 * 1024),
              candidate.entries.contains(where: { $0.id == entry.id }) else {
            message = String(localized: "Clipboard storage is full. Delete some favorites or increase the storage limit.")
            return
        }
        commit(candidate, payload: newPayload, captureSound: true)
    }

    func update(_ id: UUID, _ edit: (inout ClipboardEntry) -> Void) {
        guard !busy else { return }
        var candidate = history
        guard let index = candidate.entries.firstIndex(where: { $0.id == id }) else { return }
        edit(&candidate.entries[index])
        commit(candidate)
    }

    func editText(_ id: UUID, text: String) async -> UUID? {
        guard ready, !busy, let index = history.entries.firstIndex(where: { $0.id == id }),
              history.entries[index].isEditable else { return nil }
        let data = Data(text.utf8)
        guard data.count <= ClipboardPayload.maxBytes else {
            message = String(localized: "Text exceeds the 20 MB limit.")
            return nil
        }
        let original = history.entries[index]
        let payload = ClipboardPayload(items: [[NSPasteboard.PasteboardType.string.rawValue: data]])
        // A new payload ID keeps the original readable if writing the metadata fails.
        var edited = payload.entry(sourceID: original.sourceBundleID, sourceName: original.sourceName)
        edited.timestamp = original.timestamp
        edited.name = original.name
        edited.isFavorite = original.isFavorite
        edited.collectionIDs = original.collectionIDs
        var candidate = history
        candidate.entries[index] = edited
        guard candidate.entries.reduce(0, { $0 + $1.byteCount }) <= max(1, capacityMB) * 1024 * 1024 else {
            message = String(localized: "Clipboard storage is full. Delete some favorites or increase the storage limit.")
            return nil
        }
        busy = true
        defer {
            busy = false
            promoteUsedEntries()
            if limitsPending { applyLimits() }
        }
        do {
            message = try await disk.save(candidate, newPayload: (edited.id, payload))
            history = candidate
            return edited.id
        } catch {
            message = String(localized: "Could not save changes: \(error.localizedDescription)")
            return nil
        }
    }

    func delete(_ id: UUID) {
        guard !busy else { return }
        if ocrEntryID == id || ocrResult?.0 == id { cancelOCR() }
        var candidate = history
        candidate.entries.removeAll { $0.id == id }
        commit(candidate)
    }

    func clear() {
        guard !busy else { return }
        cancelOCR()
        ocrFailures.removeAll()
        commit(ClipboardHistory(entries: [], collections: history.collections))
    }

    func addCollection(_ name: String, pinning entryID: UUID? = nil) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty, !history.collections.contains(where: { $0.name == name }) else { return }
        var candidate = history
        let collection = ClipboardCollection(name: name)
        candidate.collections.append(collection)
        if let entryID, let index = candidate.entries.firstIndex(where: { $0.id == entryID }) {
            candidate.entries[index].collectionIDs.insert(collection.id)
        }
        commit(candidate)
    }

    func renameCollection(_ id: UUID, to name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty,
              !history.collections.contains(where: { $0.id != id && $0.name == name }),
              let index = history.collections.firstIndex(where: { $0.id == id }) else { return }
        var candidate = history
        candidate.collections[index].name = name
        commit(candidate)
    }

    func setCollectionColor(_ id: UUID, to color: ClipboardCollection.Tint) {
        guard let index = history.collections.firstIndex(where: { $0.id == id }) else { return }
        var candidate = history
        candidate.collections[index].color = color
        commit(candidate)
    }

    func deleteCollection(_ id: UUID) {
        var candidate = history
        candidate.collections.removeAll { $0.id == id }
        for index in candidate.entries.indices { candidate.entries[index].collectionIDs.remove(id) }
        commit(candidate)
    }

    func applyLimits() {
        guard ready, !busy else { limitsPending = true; return }
        limitsPending = false
        var candidate = history
        candidate.expire(retention: retention)
        guard candidate.trim(limit: max(1, itemLimit), bytes: max(1, capacityMB) * 1024 * 1024) else {
            message = String(localized: "Favorites exceed the storage limit. Delete some favorites first.")
            return
        }
        if candidate.entries != history.entries { commit(candidate) }
    }

    private func commit(_ candidate: ClipboardHistory, payload: (UUID, ClipboardPayload)? = nil, captureSound: Bool = false) {
        guard ready, !busy else { return }
        busy = true
        Task {
            do {
                let cleanupWarning = try await disk.save(candidate, newPayload: payload)
                history = candidate
                message = cleanupWarning
                if captureSound && enabled && soundEffects { NSSound(named: "Pop")?.play() }
            } catch {
                paused = true
                message = String(localized: "Saving failed. Recording paused: \(error.localizedDescription)")
            }
            busy = false
            promoteUsedEntries()
            if limitsPending { applyLimits() }
        }
    }

    private func recordUse(_ id: UUID) {
        pendingPromotions.removeAll { $0 == id }
        pendingPromotions.append(id)
        promoteUsedEntries()
    }

    private func promoteUsedEntries() {
        guard ready, !busy, !pendingPromotions.isEmpty else { return }
        var candidate = history
        for id in pendingPromotions {
            if let index = candidate.entries.firstIndex(where: { $0.id == id }) {
                candidate.entries.insert(candidate.entries.remove(at: index), at: 0)
            }
        }
        pendingPromotions.removeAll()
        if candidate.entries != history.entries { commit(candidate) }
    }

    private func cancelOCR() {
        ocrGeneration = UUID()
        ocrTask?.cancel()
        ocrResult = nil
    }

    func processOCR() {
        guard ready, !busy, ocrEnabled else { return }
        if let (id, text) = ocrResult {
            ocrResult = nil
            guard let index = history.entries.firstIndex(where: { $0.id == id }) else { return }
            var candidate = history
            candidate.entries[index].recognizedText = text
            candidate.entries[index].byteCount += text.utf8.count
            guard candidate.trim(limit: max(1, itemLimit), bytes: max(1, capacityMB) * 1024 * 1024) else {
                ocrFailures.insert(id); return
            }
            commit(candidate)
            return
        }
        guard ocrTask == nil, let entry = history.entries.first(where: {
            $0.kind == .image && $0.recognizedText == nil && !ocrFailures.contains($0.id)
        }) else { return }
        let generation = ocrGeneration
        ocrEntryID = entry.id
        ocrTask = Task {
            defer { ocrTask = nil; ocrEntryID = nil }
            do {
                guard let data = try await disk.payload(entry.id).imageData, !Task.isCancelled else {
                    if generation == ocrGeneration { ocrFailures.insert(entry.id); ocrTask = nil }
                    return
                }
                let work = Task.detached(priority: .utility) { try ClipboardOCR.recognize(data) }
                let text = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                guard !Task.isCancelled, generation == ocrGeneration else { return }
                ocrResult = (entry.id, text)
                ocrTask = nil
            } catch {
                guard generation == ocrGeneration else { return }
                ocrFailures.insert(entry.id)
                ocrTask = nil
            }
        }
    }

    func copyRecognizedText(_ id: UUID) {
        guard enabled, let text = history.entries.first(where: { $0.id == id })?.recognizedText, !text.isEmpty else { return }
        let payload = ClipboardPayload(items: [[NSPasteboard.PasteboardType.string.rawValue: Data(text.utf8)]])
        if payload.write(to: .general, plain: true) {
            lastChange = NSPasteboard.general.changeCount
            recordUse(id)
        }
    }

    func revealFiles(_ id: UUID) async {
        do {
            let payload = try await disk.payload(id)
            let urls = try payload.resolvedFileURLs()
            if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        } catch { message = error.localizedDescription }
    }

    func copyFilePaths(_ id: UUID) async {
        do {
            let payload = try await disk.payload(id)
            let paths = try payload.resolvedFileURLs().map(\.path).joined(separator: "\n")
            guard enabled, !paths.isEmpty else { return }
            let text = ClipboardPayload(items: [[NSPasteboard.PasteboardType.string.rawValue: Data(paths.utf8)]])
            if text.write(to: .general, plain: true) {
                lastChange = NSPasteboard.general.changeCount
                recordUse(id)
            }
        } catch { message = error.localizedDescription }
    }

    func copy(_ id: UUID, plain: Bool, to pasteboard: NSPasteboard = .general, ifCurrent: () -> Bool = { true }) async -> Bool {
        guard enabled else { return false }
        do {
            let payload = try await disk.payload(id)
            if payload.files != nil { _ = try payload.resolvedFileURLs() }
            guard enabled, ifCurrent() else { return false }
            guard payload.write(to: pasteboard, plain: plain) else {
                message = plain ? String(localized: "This item has no text to paste.") : String(localized: "Could not write to the clipboard.")
                return false
            }
            if pasteboard.name == NSPasteboard.general.name { lastChange = pasteboard.changeCount }
            message = nil
            recordUse(id)
            if soundEffects { NSSound(named: "Tink")?.play() }
            return true
        } catch {
            message = String(localized: "Could not read this item: \(error.localizedDescription)")
            return false
        }
    }
}
