import AppKit
import ApplicationServices
import Combine

@MainActor
final class DesktopPingManager: ObservableObject {
    static let shared = DesktopPingManager()
    private static let settingsKey = "desktopPingConfiguration"
    @Published var configuration: DesktopPingConfiguration {
        didSet {
            if let data = try? JSONEncoder().encode(configuration.normalized) { UserDefaults.standard.set(data, forKey: Self.settingsKey) }
            if configuration != oldValue { reconcile() }
        }
    }
    @Published private(set) var status = String(localized: "Disabled")
    @Published private(set) var needsPermission = false
    @Published private(set) var failure: String?
    private var process: Process?
    private var input: Pipe?
    private var overlays: [DesktopPingOverlay] = []
    private var wheelOverlay: DesktopPingOverlay?
    private var previewSurface: DesktopPingOverlay?
    private var previewTimeout: Task<Void, Never>?
    private var sounds: [String: NSSound] = [:]
    private var observers = Set<AnyCancellable>()
    private var accessTimer: Timer?
    private var overlayTimeout: Task<Void, Never>?
    private var restarts = 0
    private var sleeping = false
    private var locked = false
    private var started = false
    private var root: URL? { Bundle.main.resourceURL?.appendingPathComponent("DesktopPing") }

    private init() {
        configuration = UserDefaults.standard.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(DesktopPingConfiguration.self, from: $0) }?.normalized ?? .init()
    }

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.resetSurfaces() }.store(in: &observers)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.sleeping = true; self?.reconcile() }.store(in: &observers)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.sleeping = false; self?.reconcile() }.store(in: &observers)
        for (name, isLocked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            DistributedNotificationCenter.default().publisher(for: Notification.Name(name))
                .receive(on: RunLoop.main).sink { [weak self] _ in self?.locked = isLocked; self?.reconcile() }.store(in: &observers)
        }
        reconcile()
    }

    func stop() {
        started = false
        observers.removeAll()
        accessTimer?.invalidate(); accessTimer = nil
        closeSurfaces()
    }

    func retry() {
        failure = nil
        restarts = 0
        resetSurfaces()
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        retry()
    }

    func togglePause() { configuration.paused.toggle() }

    private func reconcile() {
        guard started else { return }
        guard configuration.enabled, !sleeping, !locked else {
            closeSurfaces()
            accessTimer?.invalidate(); accessTimer = nil
            needsPermission = false
            status = configuration.enabled ? String(localized: "Suspended") : String(localized: "Disabled")
            if !configuration.enabled { failure = nil; restarts = 0 }
            return
        }
        let previouslyNeededPermission = needsPermission
        needsPermission = !AXIsProcessTrusted()
        guard !needsPermission else {
            // Permission polling must not interrupt an explicit settings preview.
            if !previouslyNeededPermission { closeSurfaces() }
            status = String(localized: "Accessibility permission required")
            if accessTimer == nil {
                accessTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.reconcile() }
                }
            }
            return
        }
        accessTimer?.invalidate(); accessTimer = nil
        guard failure == nil else { return }
        if overlays.isEmpty { createSurfaces() }
        guard !overlays.isEmpty, overlays.allSatisfy(\.ready) else { return }
        overlayTimeout?.cancel(); overlayTimeout = nil
        for overlay in overlays { overlay.send("settings", configuration.overlaySettings) }
        status = configuration.paused ? String(localized: "Paused") : String(localized: "Ready")
        if configuration.paused { clear() }
        if process == nil { launchHelper() }
        else { send(configuration.helperCommand) }
    }

    private func createSurfaces() {
        guard let root, FileManager.default.fileExists(atPath: root.appendingPathComponent("overlay/index.html").path) else {
            fail(String(localized: "Desktop ping resources are missing. Rebuild Eave.")); return
        }
        status = String(localized: "Starting…")
        for screen in NSScreen.screens {
            let overlay = DesktopPingOverlay(screen: screen, root: root)
            overlay.onReady = { [weak self] in self?.reconcile() }
            overlay.onSound = { [weak self] in self?.play($0) }
            overlay.onFailure = { [weak self] in self?.fail($0) }
            overlays.append(overlay)
        }
        overlayTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.fail(String(localized: "Could not load the desktop ping overlay."))
        }
    }

    private func launchHelper() {
        let child = Process()
        child.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/EavePingHelper")
        let stdin = Pipe(), stdout = Pipe()
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self, weak child] _ in
            Task { @MainActor in
                guard let self, let child, self.process === child else { return }
                self.process = nil; self.input = nil
                self.clear()
                if child.terminationStatus == 3 {
                    self.needsPermission = true
                    self.fail(String(localized: "Accessibility access was refused. Re-enable Eave in System Settings, then try again."))
                } else if self.restarts < 3 {
                    self.restarts += 1
                    self.status = String(localized: "Restarting input helper…")
                    try? await Task.sleep(for: .seconds(1))
                    self.reconcile()
                } else { self.fail(String(localized: "The desktop ping input helper stopped. Try again.")) }
            }
        }
        process = child; input = stdin
        do { try child.run() } catch { fail(error.localizedDescription); return }
        // Read off the main thread; only complete JSON lines reach the UI.
        DispatchQueue.global(qos: .userInteractive).async { [weak self, weak child] in
            var pending = Data()
            let reader = stdout.fileHandleForReading
            defer { try? reader.close() }
            while let data = try? reader.read(upToCount: 8192), !data.isEmpty {
                pending.append(data)
                if pending.count > 65536 { break }
                while let newline = pending.firstIndex(of: 10) {
                    let line = Data(pending[..<newline])
                    pending.removeSubrange(...newline)
                    Task { @MainActor [weak self, weak child] in
                        guard let self, let child, self.process === child else { return }
                        self.receive(line)
                    }
                }
            }
        }
    }

    private func send(_ command: [String: Any]) {
        guard let input, let data = try? JSONSerialization.data(withJSONObject: command) else { return }
        do { try input.fileHandleForWriting.write(contentsOf: data + Data([10])) }
        catch { fail(error.localizedDescription) }
    }

    private func receive(_ line: Data) {
        guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let type = event["type"] as? String else { return }
        switch type {
        case "ready":
            send(configuration.helperCommand)
        case "toggled":
            if let enabled = event["enabled"] as? Bool { configuration.paused = !enabled }
        case "cancel":
            wheelOverlay?.send("cancel"); wheelOverlay = nil
        case "wheelOpen", "wheelMove", "wheelRelease", "click":
            let kind = event["wheel"] as? String ?? "ping"
            guard configuration.enabled, !configuration.paused, ["ping", "emote"].contains(kind),
                  kind != "emote" || (configuration.emote.enabled && configuration.emote.trigger != configuration.trigger),
                  let x = event["x"] as? Double, let y = event["y"] as? Double, x.isFinite, y.isFinite,
                  let primary = NSScreen.screens.first else { return }
            let point = CGPoint(x: x, y: y)
            let underPointer = overlays.first {
                let local = DesktopPingConfiguration.localPoint(point, screen: $0.screen.frame, primaryHeight: primary.frame.height)
                return CGRect(origin: .zero, size: $0.screen.frame.size).contains(local)
            }
            if type == "wheelOpen" { wheelOverlay = underPointer }
            let overlay = type == "click" ? underPointer : wheelOverlay
            guard let overlay else { return }
            if kind == "emote", type == "click" || type == "wheelRelease" {
                for other in overlays where other !== overlay { other.send("clearEmote") }
            }
            let local = DesktopPingConfiguration.localPoint(point, screen: overlay.screen.frame, primaryHeight: primary.frame.height)
            overlay.send(type, ["x": local.x, "y": local.y, "wheel": kind,
                                "id": kind == "emote" ? configuration.normalized.emote.center : configuration.normalized.clickPingID])
            if type == "wheelRelease" { wheelOverlay = nil }
        default: break
        }
        if failure == nil { status = configuration.paused ? String(localized: "Paused") : String(localized: "Ready") }
    }

    func preview(_ id: String) { preview(id, emote: false) }
    func previewEmote(_ id: String) { preview(id, emote: true) }

    private func preview(_ id: String, emote: Bool) {
        guard !sleeping, !locked, emote ? configuration.emote.contains(id) : DesktopPingConfiguration.pingIDs.contains(id), let screen = NSScreen.main, let root else { return }
        closePreview()
        // An explicit settings preview needs no global input access and never starts the helper.
        let overlay = DesktopPingOverlay(screen: screen, root: root)
        previewSurface = overlay
        overlay.onSound = { [weak self] in self?.play($0, preview: true) }
        overlay.onFailure = { [weak self] _ in self?.closePreview() }
        overlay.onReady = { [weak self, weak overlay] in
            guard let self, let overlay else { return }
            overlay.send("settings", self.configuration.overlaySettings)
            overlay.send("click", ["id": id, "wheel": emote ? "emote" : "ping", "x": screen.frame.width / 2, "y": screen.frame.height / 2])
            self.expirePreview(after: emote ? 3.5 : self.configuration.normalized.duration + 0.3)
        }
        expirePreview(after: 10)
    }

    private func expirePreview(after seconds: Double) {
        previewTimeout?.cancel()
        previewTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.closePreview()
        }
    }

    private func closePreview() {
        previewTimeout?.cancel(); previewTimeout = nil
        previewSurface?.close(); previewSurface = nil
    }

    private func play(_ name: String, preview: Bool = false) {
        guard (preview || (configuration.enabled && !configuration.paused)), !configuration.muted, let root else { return }
        let file: URL
        if name.hasPrefix("emote:") {
            let id = String(name.dropFirst(6))
            guard configuration.emote.sound, DesktopEmote.ids.contains(id) else { return }
            file = root.appendingPathComponent("emotes/\(id).wav")
        } else {
            guard DesktopPingConfiguration.sounds.contains(name) else { return }
            file = root.appendingPathComponent("sounds/\(name).wav")
        }
        if sounds[name] == nil { sounds[name] = NSSound(contentsOf: file, byReference: false) }
        guard let sound = sounds[name], sounds.values.filter(\.isPlaying).count < 8 else { return }
        sound.stop()
        sound.volume = Float(configuration.normalized.volume / 100)
        sound.play()
    }

    private func clear() {
        closePreview()
        wheelOverlay = nil
        for overlay in overlays { overlay.send("clear") }
        sounds.values.forEach { $0.stop() }
    }

    private func stopHelper() {
        let child = process
        process = nil
        child?.terminationHandler = nil
        try? input?.fileHandleForWriting.close()
        input = nil
        // EOF normally exits the helper; terminate if its run loop stopped responding.
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            if let child, child.isRunning { child.terminate() }
        }
    }

    private func closeSurfaces() {
        closePreview()
        stopHelper()
        overlayTimeout?.cancel(); overlayTimeout = nil
        wheelOverlay = nil
        overlays.forEach { $0.close() }; overlays.removeAll()
        sounds.values.forEach { $0.stop() }; sounds.removeAll()
    }

    private func resetSurfaces() { closeSurfaces(); reconcile() }
    private func fail(_ message: String) {
        failure = message
        status = String(localized: "Unavailable")
        closeSurfaces()
    }
}
