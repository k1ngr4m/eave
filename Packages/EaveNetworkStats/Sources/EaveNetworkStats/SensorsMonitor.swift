import AppKit
import Combine

/// Hosts Stats' read-only sensors. All discovery and sampling run on one worker queue.
public final class SensorsMonitor: NSObject, ObservableObject, NSWindowDelegate {
    public static let shared = SensorsMonitor()
    @Published public private(set) var hottestTemperature: Double?
    @Published public private(set) var sensorDescription = "—"
    @Published public private(set) var isEnabled = false
    @Published public private(set) var settingsVisible = false
    @Published public private(set) var panelSize = NSSize(width: 280, height: 300)
    public var shortcutHandler: (() -> Void)?
    private let sensorWidgets = SensorsWidgets()
    public var widgets: StatsWidgets { sensorWidgets }
    let popup = SensorsPopup()
    let settings = SensorsSettings(.sensors)
    private let notifications = SensorsNotifications(.sensors)
    private var settingsWindow: NSWindow?
    private var latest: [Sensor_p] = []
    private var listKeys: [String]?
    private var generation = 0
    private var eventMonitors: [Any] = []
    private let queue = DispatchQueue(label: "app.eave.sensors", qos: .utility)
    // Worker-queue ownership includes the timer, reader and its HID/IOReport state.
    private var reader: SensorsReader?
    private var timer: DispatchSourceTimer?
    private lazy var host: PopupView = {
        let view = PopupView(frame: NSRect(origin: .zero, size: panelSize), module: .sensors)
        view.setTitle("Sensors")
        view.sizeChanged = { [weak self] in self?.panelSize = $0 }
        view.setView(popup)
        panelSize = view.frame.size
        return view
    }()
    public var panel: NSView { host }

    public override init() {
        super.init()
        _ = host
        settings.callback = { [weak self] in self?.refreshPresentation() }
        settings.selectedHandler = { [weak self] _ in self?.refreshPresentation() }
        settings.setInterval = { [weak self] _ in self?.reschedule() }
        settings.HIDcallback = { [weak self] in self?.rediscover() }
        settings.unknownCallback = { [weak self] in
            self?.listKeys = nil
            self?.refreshPresentation()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged(_:)), name: .statsPreferencesChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings(_:)), name: .toggleSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(terminate), name: NSApplication.willTerminateNotification, object: nil)
        if let token = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] in self?.handleKey($0) }) { eventMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in self?.handleKey(event); return event }) { eventMonitors.append(token) }
        refreshPresentation()
    }

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        generation += 1
        let session = generation
        isEnabled = enabled
        if !enabled {
            latest = latest.map { value in var sensor = value; sensor.value = .nan; return sensor }
            hottestTemperature = nil
            refreshPresentation()
        }
        queue.async { [weak self] in
            guard let self else { return }
            self.timer?.cancel()
            self.timer = nil
            self.reader?.terminate()
            guard enabled else { return }
            let reader: SensorsReader
            if let existing = self.reader {
                existing.resetSampling()
                reader = existing
            } else { reader = SensorsReader() }
            reader.callbackHandler = { [weak self] value in
                let sensors = value?.sensors ?? []
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isEnabled, self.generation == session else { return }
                    self.receive(sensors)
                }
            }
            self.reader = reader
            self.startTimer()
        }
    }

    private func startTimer() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let seconds = max(1, Store.shared.int(key: "Sensors_updateInterval", defaultValue: 3))
        timer.schedule(deadline: .now(), repeating: .seconds(seconds), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.reader?.read() }
        self.timer = timer
        timer.resume()
    }

    private func reschedule() {
        guard isEnabled else { return }
        queue.async { [weak self] in
            guard let self, self.reader != nil else { return }
            self.startTimer()
        }
    }

    private func rediscover() {
        guard isEnabled else { return }
        setEnabled(false)
        setEnabled(true)
    }

    func receive(_ sensors: [Sensor_p]) {
        latest = sensors
        refreshPresentation()
        popup.usageCallback(visibleSensors)
        notifications.usageCallback(visibleSensors)
        hottestTemperature = visibleSensors.filter { $0.type == .temperature && $0.value.isFinite }.map(\.value).max()
    }

    private var visibleSensors: [Sensor_p] {
        latest.filter { Store.shared.bool(key: "Sensors_unknown", defaultValue: false) || $0.group != .unknown }
    }

    private func refreshPresentation() {
        let values = visibleSensors
        let keys = values.map(\.key)
        if listKeys != keys {
            listKeys = keys
            popup.setup(values)
            settings.setList(values)
            notifications.setup(values)
        }
        sensorWidgets.receive(values)
        let selected = Store.shared.string(key: "Sensors_sensor", defaultValue: "Average System Total")
        sensorDescription = values.first { $0.key == selected }.map { "\($0.name): \($0.formattedPopupValue)" } ?? "—"
        popup.refreshValues(values)
    }

    @objc private func preferencesChanged(_ note: Notification) {
        guard let key = note.userInfo?["key"] as? String else { return }
        if key == "temperature_units" {
            popup.setup(visibleSensors)
            notifications.setup(visibleSensors)
        }
        if key.hasPrefix("Sensors_") || key.hasPrefix("sensor_") || key.hasPrefix("stack_") || key == "temperature_units" {
            refreshPresentation()
        }
    }

    public func setVisible(_ visible: Bool) {
        if visible { host.appear() } else { host.disappear() }
    }

    @objc private func openSettings(_ note: Notification) {
        if note.userInfo?["module"] as? String == "Sensors" { showSettings() }
    }

    public func showSettings() {
        if let window = settingsWindow { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let reload = { [weak self] in
            guard let self else { return }
            self.settings.load(widgets: self.widgets.active.map(\.type))
            self.sensorWidgets.receive(self.visibleSensors)
        }
        reload()
        let window = makeStatsSettingsWindow(module: "Sensors", widgets: widgets,
            panes: [("Module", settings), ("Widgets", widgets.settings()), ("Popup", popup.settings()!), ("Notifications", notifications)],
            selectionChanged: reload)
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
        setEnabled(false)
        notifications.willTerminate()
    }

    deinit {
        timer?.cancel()
        NotificationCenter.default.removeObserver(self)
        eventMonitors.forEach(NSEvent.removeMonitor)
    }
}

final class SensorsWidgets: StatsWidgets {
    private var latest: [Sensor_p] = []

    init() {
        super.init(module: .sensors)
        refreshValues = { [weak self] in
            guard let self else { return }
            self.receive(self.latest)
        }
    }

    func receive(_ sensors: [Sensor_p]) {
        latest = sensors
        let percentage = Store.shared.string(key: "Sensors_fanValue", defaultValue: "percentage") == "percentage"
        let selected = Store.shared.string(key: "Sensors_sensor", defaultValue: "Average System Total")
        for item in active {
            switch item.item {
            case let widget as Mini:
                let sensor = sensors.first { $0.key == selected }
                let fan = sensor as? Fan
                let value = percentage && fan != nil && fan!.value.isFinite ? Double(fan!.percentage) : sensor?.localValue
                widget.setValue((value ?? .nan) / 100)
                widget.setSuffix(percentage && fan != nil ? "%" : sensor?.miniUnit ?? "")
            case let widget as StackWidget:
                widget.setValues(sensors.filter(\.state).map { sensor in
                    let fan = sensor as? Fan
                    let value = percentage && fan != nil && fan!.value.isFinite ? "\(fan!.percentage)%" : sensor.formattedMiniValue
                    return Stack_t(key: sensor.key, value: value, label: sensor.name)
                })
            case let widget as BarChart:
                widget.setValue(sensors.compactMap { $0 as? Fan }.filter { $0.state && $0.value.isFinite }.map { [ColorValue(Double($0.percentage) / 100)] })
            default: break
            }
        }
        scheduleRender()
    }
}
