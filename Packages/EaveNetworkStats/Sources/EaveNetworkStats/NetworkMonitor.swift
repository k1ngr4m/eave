import AppKit
import Combine

/// Embeds Stats' network module in Eave without creating Stats menu-bar items.
public final class NetworkMonitor: NSObject, ObservableObject, NSWindowDelegate {
    public static let shared = NetworkMonitor()
    @Published public private(set) var rates: (download: Double, upload: Double) = (0, 0)
    @Published public private(set) var isEnabled = false
    @Published public private(set) var panelSize = NSSize(width: 280, height: 800)
    public var shortcutHandler: (() -> Void)?

    public let widgets = NetworkWidgets()
    let popup = Popup(.network)
    private lazy var settings = Settings(.network)
    private lazy var notifications = Notifications(.network)
    private lazy var preview = Preview(.network)
    private lazy var host: PopupView = {
        let view = PopupView(frame: NSRect(x: 0, y: 0, width: 280, height: 800), module: .network)
        view.setTitle("Network")
        view.sizeChanged = { [weak self] size in self?.panelSize = size }
        view.setView(popup)
        panelSize = view.frame.size
        return view
    }()
    public var panel: NSView { host }
    private var settingsWindow: NSWindow?
    private let ipUpdater = NSBackgroundActivityScheduler(identifier: "app.eave.network.public-ip")
    private var visible = false
    private var started = false
    private var eventMonitors: [Any] = []

    lazy var usageReader = UsageReader(.network) { [weak self] value in
        guard let value else { return }
        DispatchQueue.main.async { [weak self] in self?.receive(value) }
    }
    lazy var processReader = ProcessReader(.network) { [weak self] value in
        guard let value else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEnabled, self.visible else { return }
            self.popup.processCallback(value)
        }
    }
    lazy var connectivityReader = ConnectivityReader(.network) { [weak self] value in
        guard let value else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEnabled else { return }
            self.popup.connectivityCallback(value)
            self.notifications.connectivityCallback(value)
            self.preview.connectivityCallback(value)
            self.widgets.receive(value)
        }
    }

    public override init() {
        super.init()
        _ = host
        popup.locationPermissionAction = { [weak self] in self?.usageReader.requestWiFiLocationAuthorization() }
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings(_:)), name: .toggleSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(terminate), name: NSApplication.willTerminateNotification, object: nil)
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] in self?.handleKey($0) }) {
            eventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.handleKey(event)
            return event
        }) { eventMonitors.append(monitor) }
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            for reader in [usageReader as Reader_p, processReader, connectivityReader] {
                reader.initStoreValues(title: "Network")
                if reader.popup && !visible { reader.lock() } else { reader.unlock() }
                reader.start()
            }
            if !started {
                started = true
                resetAtStart()
            }
            setIPUpdater()
        } else {
            usageReader.stop()
            processReader.stop()
            connectivityReader.stop()
            ipUpdater.invalidate()
        }
    }

    public func setVisible(_ visible: Bool) {
        self.visible = visible
        if visible {
            host.appear()
            processReader.unlock()
            if isEnabled { processReader.start() }
        } else {
            host.disappear()
            processReader.lock()
            processReader.pause()
        }
    }

    private func receive(_ value: Network_Usage) {
        guard isEnabled else { return }
        popup.usageCallback(value)
        notifications.usageCallback(value)
        preview.usageCallback(value)
        widgets.receive(value)
        let bandwidth = widgets.bandwidth(value.bandwidth)
        rates = (Double(bandwidth.download), Double(bandwidth.upload))
    }

    public func formattedSpeed(_ value: Double) -> String {
        Units(bytes: Int64(max(0, min(value.isFinite ? value : 0, Double(Int64.max / 2)))))
            .getReadableSpeed(base: DataSizeBase(rawValue: Store.shared.string(key: "Network_base", defaultValue: "byte")) ?? .byte,
                              unit: Store.shared.string(key: "Network_speedUnit", defaultValue: NetworkSpeedUnitAuto))
    }

    @objc private func openSettings(_ notification: Notification) {
        guard notification.userInfo?["module"] as? String == "Network" else { return }
        showSettings()
    }

    public func showSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        configureSettings()
        settings.load(widgets: widgets.active.map(\.type))
        let tabs = NSTabView(frame: NSRect(x: 0, y: 0, width: 580, height: 650))
        let panes: [(String, NSView)] = [("Module", settings), ("Widgets", widgets.settings()), ("Popup", popup.settings()!), ("Notifications", notifications), ("Overview", preview)]
        for (name, pane) in panes {
            let scroll = ScrollableStackView()
            scroll.stackView.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
            scroll.stackView.addArrangedSubview(pane)
            pane.translatesAutoresizingMaskIntoConstraints = false
            pane.widthAnchor.constraint(equalTo: scroll.stackView.widthAnchor, constant: -24).isActive = true
            let tab = NSTabViewItem(identifier: name)
            tab.label = localizedString(name)
            tab.view = scroll
            tabs.addTabViewItem(tab)
        }
        let window = NSWindow(contentRect: tabs.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = localizedString("Network") + " — " + localizedString("Settings")
        let content = NSView(frame: tabs.frame)
        let selector = widgets.selector { [weak self] in
            guard let self else { return }
            self.settings.load(widgets: self.widgets.active.map(\.type))
        }
        tabs.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(selector)
        content.addSubview(tabs)
        NSLayoutConstraint.activate([
            selector.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            selector.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            selector.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            tabs.topAnchor.constraint(equalTo: selector.bottomAnchor, constant: 8),
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            tabs.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
        ])
        window.contentView = content
        window.minSize = NSSize(width: 580, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureSettings() {
        settings.callbackWhenUpdateNumberOfProcesses = { [weak self] in
            guard let self else { return }
            self.popup.numberOfProcessesUpdated()
            if self.isEnabled { DispatchQueue.global(qos: .utility).async { self.processReader.read() } }
        }
        settings.callback = { [weak self] in
            guard let self, self.isEnabled else { return }
            DispatchQueue.global(qos: .utility).async { self.usageReader.getDetails(); self.usageReader.read() }
        }
        settings.usageResetCallback = { [weak self] in self?.resetAtStart() }
        settings.connectivityHostCallback = { [weak self] disabled in
            guard disabled, let self else { return }
            self.popup.resetConnectivityView()
            let value = Network_Connectivity(status: false)
            self.popup.connectivityCallback(value)
            self.notifications.connectivityCallback(value)
            self.preview.connectivityCallback(value)
            self.widgets.receive(value)
        }
        settings.setInterval = { [weak self] value in self?.connectivityReader.setInterval(value) }
        settings.publicIPRefreshIntervalCallback = { [weak self] in self?.setIPUpdater() }
    }

    private func resetAtStart() {
        if Store.shared.string(key: "Network_usageReset", defaultValue: "Never") == AppUpdateInterval.atStart.rawValue {
            NotificationCenter.default.post(name: .resetTotalNetworkUsage, object: nil)
        }
    }

    private func setIPUpdater() {
        ipUpdater.invalidate()
        guard isEnabled else { return }
        switch Store.shared.string(key: "Network_publicIPRefreshInterval", defaultValue: "never") {
        case "hour": ipUpdater.interval = 3600
        case "12": ipUpdater.interval = 43200
        case "24": ipUpdater.interval = 86400
        default: return
        }
        ipUpdater.repeats = true
        ipUpdater.schedule { [weak self] completion in
            defer { completion(.finished) }
            guard self?.isEnabled == true else { return }
            NotificationCenter.default.post(name: .refreshPublicIP, object: nil)
        }
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

    public func windowWillClose(_ notification: Notification) {
        settingsWindow = nil
    }

    @objc private func terminate() {
        guard started else { return }
        setEnabled(false)
        if let value = usageReader.value { usageReader.save(value) }
        usageReader.terminate()
        connectivityReader.terminate()
        notifications.willTerminate()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        eventMonitors.forEach(NSEvent.removeMonitor)
        ipUpdater.invalidate()
    }
}
