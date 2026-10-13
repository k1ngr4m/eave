import AppKit
import Combine

/// Hosts Stats' RAM and Disk modules using Eave's windows and lifecycle.
public final class MemoryDiskMonitor: NSObject, ObservableObject, NSWindowDelegate {
    public static let memory = MemoryDiskMonitor(module: .RAM)
    public static let disk = MemoryDiskMonitor(module: .disk)
    public let module: ModuleType
    @Published public private(set) var utilization: Double?
    @Published public private(set) var rates: (read: Double, write: Double) = (0, 0)
    @Published public private(set) var isEnabled = false
    @Published public private(set) var settingsVisible = false
    @Published public private(set) var panelSize = NSSize(width: 280, height: 600)
    public var shortcutHandler: (() -> Void)?
    private let moduleWidgets: MemoryDiskWidgets
    public var widgets: StatsWidgets { moduleWidgets }
    let popup: PopupWrapper
    let settings: Settings_v
    private let notifications: NotificationsWrapper
    private let preview: PreviewWrapper
    private var settingsWindow: NSWindow?
    private var visible = false
    private var eventMonitors: [Any] = []
    private var latestCapacity: Disks?
    private var latestActivity: Disks?
    private lazy var host: PopupView = {
        let view = PopupView(frame: NSRect(origin: .zero, size: panelSize), module: module)
        view.setTitle(module.stringValue)
        view.sizeChanged = { [weak self] in self?.panelSize = $0 }
        view.setView(popup)
        panelSize = view.frame.size
        return view
    }()
    public var panel: NSView { host }

    lazy var usageReader = RAMUsageReader(.RAM) { [weak self] value in
        self?.deliver { if let value { $0.receive(value) } }
    }
    lazy var memoryProcessReader = RAMProcessReader(.RAM) { [weak self] value in
        self?.deliver { if $0.visible, let value { ($0.popup as? RAMPopup)?.processCallback(value) } }
    }
    lazy var capacityReader = DiskCapacityReader(.disk) { [weak self] value in
        guard let value else { return }
        let snapshot = Disks(); snapshot.array = value.array
        self?.deliver { $0.receiveCapacity(snapshot) }
    }
    lazy var activityReader = DiskActivityReader(.disk) { [weak self] value in
        guard let value else { return }
        let snapshot = Disks(); snapshot.array = value.array
        self?.deliver { $0.receiveActivity(snapshot) }
    }
    lazy var diskProcessReader = DiskProcessReader(.disk) { [weak self] value in
        self?.deliver { if $0.visible, let value { ($0.popup as? DiskPopup)?.processCallback(value) } }
    }
    lazy var smartReader = DiskSMARTReader(.disk) { [weak self] value in
        guard let value else { return }
        let snapshot = Disks(); snapshot.array = value.array
        self?.deliver {
            ($0.popup as? DiskPopup)?.smartCallback(snapshot)
            ($0.preview as? DiskPreview)?.smartCallback(snapshot)
        }
    }
    private var readers: [Reader_p] {
        module == .RAM ? [usageReader, memoryProcessReader] : [capacityReader, activityReader, diskProcessReader, smartReader]
    }

    init(module: ModuleType) {
        precondition(module == .RAM || module == .disk)
        self.module = module
        moduleWidgets = MemoryDiskWidgets(module: module)
        popup = module == .RAM ? RAMPopup(module) : DiskPopup(module)
        settings = module == .RAM ? RAMSettings(module) : DiskSettings(module)
        notifications = module == .RAM ? RAMNotifications(module) : DiskNotifications(module)
        preview = module == .RAM ? RAMPreview(module) : DiskPreview(module)
        super.init()
        _ = host
        configureSettings()
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings(_:)), name: .toggleSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(terminate), name: NSApplication.willTerminateNotification, object: nil)
        if let token = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] in self?.handleKey($0) }) { eventMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in self?.handleKey(event); return event }) { eventMonitors.append(token) }
    }

    private func deliver(_ action: @escaping (MemoryDiskMonitor) -> Void) {
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
            if reader.popup && !visible { reader.lock(); reader.pause() }
            else { reader.unlock(); reader.start() }
        }
    }

    public func setVisible(_ visible: Bool) {
        self.visible = visible
        if visible { host.appear() } else { host.disappear() }
        reconcileReaders()
    }

    func receive(_ value: RAM_Usage) {
        (popup as? RAMPopup)?.loadCallback(value)
        (notifications as? RAMNotifications)?.loadCallback(value)
        (preview as? RAMPreview)?.loadCallback(value)
        moduleWidgets.receive(value)
        utilization = value.usage
    }

    private func selected(_ value: Disks) -> drive? {
        let name = Store.shared.string(key: "Disk_disk", defaultValue: "")
        return value.first(where: { $0.mediaName == name }) ?? value.first(where: { $0.root })
    }

    func receiveCapacity(_ value: Disks) {
        latestCapacity = value
        (popup as? DiskPopup)?.capacityCallback(value)
        (preview as? DiskPreview)?.capacityCallback(value)
        (settings as? DiskSettings)?.setList(value)
        guard let drive = selected(value) else { utilization = nil; return }
        (notifications as? DiskNotifications)?.utilizationCallback(drive.percentage)
        moduleWidgets.receiveCapacity(drive)
        utilization = drive.percentage
    }

    func receiveActivity(_ value: Disks, appendHistory: Bool = true) {
        latestActivity = value
        if appendHistory {
            (popup as? DiskPopup)?.activityCallback(value)
            (preview as? DiskPreview)?.activityCallback(value)
        }
        guard let drive = selected(value) else { rates = (0, 0); return }
        moduleWidgets.receiveActivity(drive, appendHistory: appendHistory)
        rates = (Double(drive.activity.read), Double(drive.activity.write))
    }

    public func formattedSpeed(_ value: Double) -> String {
        Units(bytes: Int64(max(0, min(value.isFinite ? value : 0, Double(Int64.max / 2)))))
            .getReadableSpeed(base: DataSizeBase(rawValue: Store.shared.string(key: "Disk_base", defaultValue: "byte")) ?? .byte,
                              unit: Store.shared.string(key: "Disk_speedUnit", defaultValue: NetworkSpeedUnitAuto))
    }

    private func configureSettings() {
        if let settings = settings as? RAMSettings {
            settings.callback = { [weak self] in self?.readUsage() }
            settings.setInterval = { [weak self] in self?.usageReader.setInterval($0) }
            settings.setTopInterval = { [weak self] in self?.memoryProcessReader.setInterval($0) }
            settings.callbackWhenUpdateNumberOfProcesses = { [weak self] in
                guard let self else { return }
                (self.popup as? RAMPopup)?.numberOfProcessesUpdated()
                self.readProcesses()
            }
        }
        if let settings = settings as? DiskSettings {
            settings.callback = { [weak self] in self?.readUsage() }
            settings.setInterval = { [weak self] in self?.capacityReader.setInterval($0) }
            settings.setSMARTInterval = { [weak self] in self?.smartReader.setInterval($0) }
            settings.selectedDiskHandler = { [weak self] _ in
                guard let self else { return }
                if let value = self.latestCapacity { self.receiveCapacity(value) }
                if let value = self.latestActivity { self.receiveActivity(value, appendHistory: false) }
                self.readUsage()
            }
            settings.callbackWhenUpdateNumberOfProcesses = { [weak self] in
                guard let self else { return }
                (self.popup as? DiskPopup)?.numberOfProcessesUpdated()
                self.readProcesses()
            }
        }
    }

    private func readUsage() {
        guard isEnabled else { return }
        let readers: [Reader_p] = module == .RAM ? [usageReader] : [capacityReader, smartReader]
        DispatchQueue.global(qos: .utility).async { readers.forEach { $0.read() } }
    }

    private func readProcesses() {
        guard isEnabled, visible else { return }
        let reader: Reader_p = module == .RAM ? memoryProcessReader : diskProcessReader
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
            if let list = self.latestCapacity { (self.settings as? DiskSettings)?.setList(list) }
        }
        reload()
        let panes: [(String, NSView)] = [("Module", settings), ("Widgets", widgets.settings()), ("Popup", popup.settings()!), ("Notifications", notifications), ("Overview", preview)]
        let window = makeStatsSettingsWindow(module: module.stringValue, widgets: widgets, panes: panes, selectionChanged: reload)
        window.delegate = self
        settingsWindow = window
        settingsVisible = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        settingsWindow = nil
        settingsVisible = false
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
