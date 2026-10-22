import AppKit
import Combine

/// Hosts Stats' battery popup; readers run only while the detail panel is visible.
public final class BatteryMonitor: ObservableObject {
    @Published public private(set) var panelSize = NSSize(width: 280, height: 800)
    public private(set) var isVisible = false
    public var openSettings: (() -> Void)?
    let popup = BatteryPopup(.battery)
    private let host = PopupView(frame: NSRect(x: 0, y: 0, width: 280, height: 800), module: .battery)
    public var panel: NSView { host }
    private var settingsObserver: NSObjectProtocol?

    lazy var usageReader = BatteryUsageReader(.battery) { [weak self] value in
        DispatchQueue.main.async {
            guard let self, self.isVisible, let value else { return }
            self.popup.usageCallback(value)
        }
    }
    lazy var processReader = BatteryProcessReader(.battery) { [weak self] value in
        DispatchQueue.main.async {
            guard let self, self.isVisible, let value else { return }
            self.popup.processCallback(value)
        }
    }

    public init() {
        host.setTitle("Battery")
        host.sizeChanged = { [weak self] in self?.panelSize = $0 }
        host.setView(popup)
        panelSize = host.frame.size
        settingsObserver = NotificationCenter.default.addObserver(forName: .toggleSettings, object: nil, queue: .main) { [weak self] notification in
            guard notification.userInfo?["module"] as? String == "Battery" else { return }
            self?.openSettings?()
        }
        usageReader.initStoreValues(title: "Battery")
        processReader.setInterval(3)
    }

    deinit {
        usageReader.stop()
        processReader.stop()
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    public func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible {
            host.appear()
            usageReader.unlock()
            processReader.unlock()
            usageReader.start()
            processReader.start()
        } else {
            usageReader.stop()
            processReader.stop()
            host.disappear()
        }
    }
}
