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
    private let defaults: UserDefaults
    let disk: ClipboardDiskStore
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private var ready = false
    private var loading = false
    private var limitsPending = false
    private var nextExpiryCheck = Date.distantPast
    private var unavailable = false
    private var observers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
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
                    message = "剪贴板历史无法读取，已停止记录以保护原数据：\(error.localizedDescription)"
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
        let change = pasteboard.changeCount
        guard change != lastChange else { return }
        if #available(macOS 15.4, *) {
            if pasteboard.accessBehavior == .alwaysDeny || pasteboard.accessBehavior == .ask {
                message = "需要允许读取剪贴板。请在设置中选择“允许读取”，或在系统设置中允许 Eave 从其他 App 粘贴。"
                return
            }
        }
        let app = NSWorkspace.shared.frontmostApplication
        let sourceID = app?.bundleIdentifier ?? ""
        let excluded = Set(excludedApps.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init))
        guard !excluded.contains(sourceID) else { lastChange = change; return }
        guard let payload = ClipboardPayload.read(from: pasteboard) else { lastChange = change; return }
        guard pasteboard.changeCount == change else { return }
        lastChange = change
        var candidate = history
        var entry = payload.entry(sourceID: sourceID, sourceName: app?.localizedName ?? "未知应用")
        var newPayload: (UUID, ClipboardPayload)? = (entry.id, payload)
        if let index = candidate.entries.firstIndex(where: { $0.checksum == entry.checksum }) {
            let previous = candidate.entries.remove(at: index)
            entry.id = previous.id
            entry.isFavorite = previous.isFavorite
            entry.collectionIDs = previous.collectionIDs
            newPayload = nil
        }
        candidate.entries.insert(entry, at: 0)
        candidate.expire(retention: retention)
        guard candidate.trim(limit: max(1, itemLimit), bytes: max(1, capacityMB) * 1024 * 1024),
              candidate.entries.contains(where: { $0.id == entry.id }) else {
            message = "剪贴板容量已满，请删除部分收藏或提高容量上限。"
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

    func delete(_ id: UUID) {
        var candidate = history
        candidate.entries.removeAll { $0.id == id }
        commit(candidate)
    }

    func clear() { commit(ClipboardHistory(entries: [], collections: history.collections)) }

    func addCollection(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !history.collections.contains(where: { $0.name == name }) else { return }
        var candidate = history
        candidate.collections.append(ClipboardCollection(name: String(name.prefix(40))))
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
            message = "收藏已超过容量上限，请先删除部分收藏。"
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
                message = "保存失败，已暂停记录：\(error.localizedDescription)"
            }
            busy = false
            if limitsPending { applyLimits() }
        }
    }

    func copy(_ id: UUID, plain: Bool, ifCurrent: () -> Bool = { true }) async -> Bool {
        guard enabled else { return false }
        do {
            let payload = try await disk.payload(id)
            guard enabled, ifCurrent() else { return false }
            guard payload.write(to: .general, plain: plain) else {
                message = plain ? "这条记录没有可粘贴的文字。" : "无法写入剪贴板。"
                return false
            }
            lastChange = NSPasteboard.general.changeCount
            message = nil
            if soundEffects { NSSound(named: "Tink")?.play() }
            return true
        } catch {
            message = "无法读取这条记录：\(error.localizedDescription)"
            return false
        }
    }
}
