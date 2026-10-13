import AppKit
import Combine

/// Hosts Stats' original CPU/GPU module views and readers in Eave.
public final class ProcessorMonitor: NSObject, ObservableObject, NSWindowDelegate {
    public static let cpu = ProcessorMonitor(module: .CPU)
    public static let gpu = ProcessorMonitor(module: .GPU)
    public let module: ModuleType
    @Published public private(set) var utilization: Double?
    @Published public private(set) var isEnabled = false
    @Published public private(set) var settingsVisible = false
    @Published public private(set) var panelSize = NSSize(width: 280, height: 600)
    public var shortcutHandler: (() -> Void)?
    private let processorWidgets: ProcessorWidgets
    public var widgets: StatsWidgets { processorWidgets }
    let popup: PopupWrapper
    let settings: Settings_v
    private let notifications: NotificationsWrapper
    private let preview: PreviewWrapper
    private var settingsWindow: NSWindow?
    private var visible = false
    private var eventMonitors: [Any] = []
    private var latestGPUs: GPUs?
    private lazy var host: PopupView = {
        let view = PopupView(frame: NSRect(origin: .zero, size: panelSize), module: module)
        view.setTitle(module.stringValue)
        view.sizeChanged = { [weak self] in self?.panelSize = $0 }
        view.setView(popup)
        panelSize = view.frame.size
        return view
    }()
    public var panel: NSView { host }

    lazy var loadReader = CPULoadReader(.CPU) { [weak self] value in self?.deliver { $0.receive(value) } }
    lazy var processReader = CPUProcessReader(.CPU) { [weak self] value in self?.deliver {
        guard $0.visible else { return }
        ($0.popup as? CPUPopup)?.processCallback(value)
    } }
    private lazy var temperatureReader = CPUTemperatureReader(.CPU, popup: true) { [weak self] value in self?.deliver {
        ($0.popup as? CPUPopup)?.temperatureCallback(value)
    } }
    private lazy var frequencyReader = CPUFrequencyReader(.CPU) { [weak self] value in self?.deliver {
        ($0.popup as? CPUPopup)?.frequencyCallback(value)
        ($0.preview as? CPUPreview)?.frequencyCallback(value)
    } }
    private lazy var averageReader = CPUAverageLoadReader(.CPU, popup: true, preview: true) { [weak self] value in self?.deliver {
        ($0.popup as? CPUPopup)?.averageCallback(value)
        ($0.preview as? CPUPreview)?.averageCallback(value)
    } }
    private lazy var limitReader = CPULimitReader(.CPU, popup: true) { [weak self] value in self?.deliver {
        ($0.popup as? CPUPopup)?.limitCallback(value)
    } }
    lazy var infoReader = GPUInfoReader(.GPU) { [weak self] value in self?.deliver { $0.receive(value) } }

    private var readers: [Reader_p] {
        if module == .GPU { return [infoReader] }
        #if arch(x86_64)
        return [loadReader, processReader, temperatureReader, averageReader, limitReader]
        #else
        return [loadReader, processReader, temperatureReader, averageReader, frequencyReader]
        #endif
    }

    init(module: ModuleType) {
        precondition(module == .CPU || module == .GPU)
        self.module = module
        processorWidgets = ProcessorWidgets(module: module)
        popup = module == .CPU ? CPUPopup(module) : GPUPopup(module)
        settings = module == .CPU ? CPUSettings(module) : GPUSettings(module)
        notifications = module == .CPU ? CPUNotifications(module) : GPUNotifications(module)
        preview = module == .CPU ? CPUPreview(module) : GPUPreview(module)
        super.init()
        _ = host
        configureSettings()
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings(_:)), name: .toggleSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(terminate), name: NSApplication.willTerminateNotification, object: nil)
        if let token = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] in self?.handleKey($0) }) { eventMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in self?.handleKey(event); return event }) { eventMonitors.append(token) }
    }

    private func deliver(_ action: @escaping (ProcessorMonitor) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEnabled else { return }
            action(self)
        }
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled { reconcileReaders() }
        else { readers.forEach { $0.stop() } }
    }

    private func reconcileReaders() {
        guard isEnabled else { return }
        for reader in readers {
            reader.initStoreValues(title: module.stringValue)
            if (reader.popup || reader.preview) && !visible && !(reader.preview && settingsVisible) {
                reader.lock(); reader.pause()
            } else { reader.unlock(); reader.start() }
        }
    }

    public func setVisible(_ visible: Bool) {
        self.visible = visible
        if visible { host.appear() } else { host.disappear() }
        reconcileReaders()
    }

    func receive(_ value: CPU_Load?) {
        guard let value else { return }
        (popup as? CPUPopup)?.loadCallback(value)
        (notifications as? CPUNotifications)?.loadCallback(value)
        (preview as? CPUPreview)?.loadCallback(value)
        processorWidgets.receive(value)
        utilization = value.totalUsage
    }

    func receive(_ value: GPUs?) {
        guard let value else { return }
        latestGPUs = value
        (settings as? GPUSettings)?.setList(value)
        let active = value.active()
        let name = Store.shared.string(key: "GPU_gpu", defaultValue: "automatic")
        guard let gpu = active.first(where: { $0.model == name }) ?? active.first,
              let utilization = gpu.utilization else { self.utilization = nil; return }
        (popup as? GPUPopup)?.loadCallback(gpu)
        (notifications as? GPUNotifications)?.usageCallback(utilization)
        (preview as? GPUPreview)?.loadCallback(gpu)
        processorWidgets.receive(gpu)
        self.utilization = utilization
    }

    private func configureSettings() {
        if let settings = settings as? CPUSettings {
            settings.callback = { [weak self] in self?.readUsage() }
            settings.callbackWhenUpdateNumberOfProcesses = { [weak self] in
                guard let self else { return }
                (self.popup as? CPUPopup)?.numberOfProcessesUpdated()
                if self.isEnabled && self.visible { DispatchQueue.global(qos: .utility).async { self.processReader.read() } }
            }
            settings.setInterval = { [weak self] in self?.loadReader.setInterval($0) }
            settings.setTopInterval = { [weak self] in self?.processReader.setInterval($0) }
        }
        if let settings = settings as? GPUSettings {
            settings.callback = { [weak self] in self?.readUsage() }
            settings.selectedGPUHandler = { [weak self] _ in
                guard let self else { return }
                self.receive(self.latestGPUs)
                self.readUsage()
            }
            settings.setInterval = { [weak self] in self?.infoReader.setInterval($0) }
        }
    }

    private func readUsage() {
        guard isEnabled else { return }
        let reader: Reader_p = module == .CPU ? loadReader : infoReader
        DispatchQueue.global(qos: .utility).async { reader.read() }
    }

    @objc private func openSettings(_ note: Notification) {
        if note.userInfo?["module"] as? String == module.stringValue { showSettings() }
    }

    public func showSettings() {
        if let window = settingsWindow { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let reload = { [weak self] in
            guard let self else { return }
            self.settings.load(widgets: self.widgets.active.map(\.type))
            if let list = self.latestGPUs { (self.settings as? GPUSettings)?.setList(list) }
        }
        reload()
        let panes: [(String, NSView)] = [("Module", settings), ("Widgets", widgets.settings()), ("Popup", popup.settings()!), ("Notifications", notifications), ("Overview", preview)]
        let window = makeStatsSettingsWindow(module: module.stringValue, widgets: widgets, panes: panes, selectionChanged: reload)
        window.delegate = self
        settingsWindow = window
        settingsVisible = true
        reconcileReaders()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        settingsWindow = nil
        settingsVisible = false
        reconcileReaders()
    }

    private func handleKey(_ event: NSEvent) {
        guard isEnabled, settingsWindow?.isKeyWindow != true, !event.isARepeat else { return }
        var codes: [UInt16] = []
        if event.modifierFlags.contains(.control) { codes.append(59) }
        if event.modifierFlags.contains(.shift) { codes.append(60) }
        if event.modifierFlags.contains(.command) { codes.append(55) }
        if event.modifierFlags.contains(.option) { codes.append(58) }
        codes.append(event.keyCode)
        if codes == popup.keyboardShortcut { shortcutHandler?() }
    }

    @objc private func terminate() {
        readers.forEach { $0.stop(); $0.terminate() }
        notifications.willTerminate()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        eventMonitors.forEach(NSEvent.removeMonitor)
    }
}
