import AppKit
import Combine

/// Stats' actual widget views and controls, rendered once for every Eave display.
public final class NetworkWidgets: NSObject, ObservableObject {
    @Published public private(set) var image = NSImage(size: .zero)
    @Published public private(set) var size = NSSize.zero
    let items: [SWidget]
    private let canvas = NSView()
    private let editor = NSStackView()
    private let livePreview = NSImageView()
    private var lastUsage = Network_Usage()
    private var connectivity: Network_Connectivity?
    private var pendingRender = false

    var active: [SWidget] { items.filter(\.isActive).sorted { $0.position < $1.position } }

    public override init() {
        let url = Bundle.module.url(forResource: "NetworkWidgets", withExtension: "plist")!
        let config = NSDictionary(contentsOf: url)!["Widgets"] as! NSDictionary
        let types: [widget_t] = [.label, .speed, .networkChart, .state, .text, .icon]
        items = types.compactMap { $0.new(module: "Network", config: config, defaultWidget: .speed,
                                        icon: NSImage(systemSymbolName: "network", accessibilityDescription: nil)) }
        super.init()
        canvas.appearance = NSAppearance(named: .darkAqua)
        editor.orientation = .vertical
        editor.alignment = .centerX
        editor.spacing = 10
        for (position, widget) in items.enumerated() {
            if !Store.shared.exist(key: "Network_\(widget.type)_position") { widget.position = position }
            widget.sizeCallback = { [weak self] in self?.scheduleRender() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged(_:)), name: .networkPreferencesChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reordered), name: .widgetRearrange, object: nil)
        scheduleRender()
    }

    func selector(changed: @escaping () -> Void) -> NSView {
        WidgetSelectorView(module: "Network", widgets: items) { [weak self] in
            self?.reloadEditor()
            self?.scheduleRender()
            changed()
        }
    }

    func settings() -> NSView { reloadEditor(); return editor }

    private func reloadEditor() {
        editor.arrangedSubviews.forEach { $0.removeFromSuperview() }
        livePreview.identifier = NSUserInterfaceItemIdentifier("NetworkWidgetsPreview")
        livePreview.image = image
        livePreview.imageScaling = .scaleProportionallyDown
        livePreview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        livePreview.wantsLayer = true
        livePreview.layer?.backgroundColor = NSColor.black.cgColor
        livePreview.layer?.cornerRadius = 6
        livePreview.setAccessibilityLabel(localizedString("Network"))
        if livePreview.constraints.isEmpty { livePreview.heightAnchor.constraint(equalToConstant: 38).isActive = true }
        editor.addArrangedSubview(livePreview)
        if active.count > 1 {
            let toggle = NSSwitch()
            toggle.action = #selector(toggleMerge(_:))
            toggle.state = Store.shared.bool(key: "Network_oneView", defaultValue: false) ? .on : .off
            toggle.target = self
            editor.addArrangedSubview(PreferencesSection([PreferencesRow(localizedString("Merge widgets"), component: toggle)]))
        }
        for widget in active where widget.type != .label {
            editor.addArrangedSubview(WidgetSettings(title: widget.type.name(), image: widget.image, settingsView: widget.item.settings()))
        }
        for view in editor.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: editor.widthAnchor).isActive = true
        }
    }

    @objc private func toggleMerge(_ sender: NSControl) {
        Store.shared.set(key: "Network_oneView", value: controlState(sender))
    }

    @objc private func reordered() { reloadEditor(); scheduleRender() }

    @objc private func preferencesChanged(_ note: Notification) {
        guard let key = note.userInfo?["key"] as? String,
              key.hasPrefix("Network_speed") || key.hasPrefix("Network_network_chart") || key.hasPrefix("Network_widget") ||
              key.hasSuffix("_position") || ["Network_oneView", "Network_base", "Network_textWidgetValue"].contains(key) else { return }
        updateValues(appendHistory: false)
        scheduleRender()
    }

    func receive(_ value: Network_Usage) {
        lastUsage = value
        updateValues(appendHistory: true)
        scheduleRender()
    }

    func receive(_ value: Network_Connectivity) {
        connectivity = value
        updateValues(appendHistory: false)
        scheduleRender()
    }

    func bandwidth(_ value: Bandwidth) -> Bandwidth {
        var bandwidth = value
        if Store.shared.bool(key: "Network_widgetActivationThresholdState", defaultValue: false) {
            let size = SizeUnit.fromString(Store.shared.string(key: "Network_widgetActivationThresholdSize", defaultValue: "MB"))
            let threshold = size.toBytes(Store.shared.int(key: "Network_widgetActivationThreshold", defaultValue: 0))
            if bandwidth.upload < threshold && bandwidth.download < threshold { bandwidth = Bandwidth() }
        }
        return bandwidth
    }

    private func updateValues(appendHistory: Bool) {
        let bandwidth = bandwidth(lastUsage.bandwidth)
        for widget in active {
            switch widget.item {
            case let speed as SpeedWidget: speed.setValue(input: bandwidth.download, output: bandwidth.upload)
            case let chart as NetworkChart where appendHistory: chart.setValue(upload: Double(bandwidth.upload), download: Double(bandwidth.download))
            case let text as TextWidget: text.setValue(textValue(lastUsage, connectivity: connectivity))
            case let dot as DotWidget:
                let color = connectivity.map { $0.status ? SColor.secondGreen : SColor.secondRed }
                dot.setValue(color?.additional as? NSColor ?? .systemGray)
            default: break
            }
        }
    }

    private func scheduleRender() {
        guard !pendingRender else { return }
        pendingRender = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingRender = false
            self.render()
        }
    }

    private func render() {
        let list = active
        canvas.subviews.forEach { $0.removeFromSuperview() }
        guard !list.isEmpty else {
            if size != .zero { size = .zero }
            image = NSImage(size: .zero)
            livePreview.image = nil
            return
        }
        canvas.appearance!.performAsCurrentDrawingAppearance {
            let spacing: CGFloat = Store.shared.bool(key: "Network_oneView", defaultValue: false) ? Constants.Widget.spacing : 10
            var x: CGFloat = 4
            for widget in list {
                let view = widget.item
                canvas.addSubview(view)
                // Original draw methods determine their width. Measure before composing the strip.
                _ = view.dataWithPDF(inside: view.bounds)
                if let wrapper = view as? WidgetWrapper { view.setFrameSize(wrapper.shadowSize) }
                view.setFrameOrigin(NSPoint(x: x, y: Constants.Widget.margin.y))
                x += view.frame.width + spacing
            }
            let newSize = NSSize(width: x - spacing + 4, height: Constants.Widget.height)
            canvas.setFrameSize(newSize)
            if let rendered = NSImage(data: canvas.dataWithPDF(inside: canvas.bounds)) {
                image = rendered
                livePreview.image = rendered
            }
            if size != newSize { size = newSize }
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

extension Notification.Name {
    static let networkPreferencesChanged = Notification.Name("EaveNetworkPreferencesChanged")
}

// Template substitutions from Stats Modules/Net/main.swift.
extension NetworkWidgets {
    func textValue(_ value: Network_Usage, connectivity: Network_Connectivity?) -> String {
        var text = Store.shared.string(key: "Network_textWidgetValue", defaultValue: "$addr.public - $status")
        let pairs = TextWidget.parseText(text)
        pairs.forEach { pair in
            var replacement: String? = nil

            switch pair.key {
            case "$addr":
                switch pair.value {
                case "public": replacement = value.raddr.v4 ?? value.raddr.v6 ?? "-"
                case "publicV4": replacement = value.raddr.v4 ?? "-"
                case "publicV6": replacement = value.raddr.v6 ?? "-"
                case "private": replacement = value.laddr.v4 ?? value.laddr.v6 ?? "-"
                case "privateV4": replacement = value.laddr.v4 ?? "-"
                case "privateV6": replacement = value.laddr.v6 ?? "-"
                case "countryCode": replacement = value.raddr.countryCode ?? "-"
                case "flag": replacement = value.raddr.countryCode != nil ? countryFlag(value.raddr.countryCode!) : "-"
                default: return
                }
            case "$interface":
                switch pair.value {
                case "displayName": replacement = value.interface?.displayName ?? "-"
                case "BSDName": replacement = value.interface?.BSDName ?? "-"
                case "address": replacement = value.interface?.address ?? "-"
                case "transmitRate": replacement = "\(value.interface?.transmitRate ?? 0)"
                default: return
                }
            case "$wifi":
                switch pair.value {
                case "ssid": replacement = value.wifiDetails.ssid ?? "-"
                case "bssid": replacement = value.wifiDetails.bssid ?? "-"
                case "RSSI": replacement = "\(value.wifiDetails.RSSI ?? 0)"
                case "noise": replacement = "\(value.wifiDetails.noise ?? 0)"
                case "standard": replacement = value.wifiDetails.standard ?? "-"
                case "mode": replacement = value.wifiDetails.mode ?? "-"
                case "security": replacement = value.wifiDetails.security ?? "-"
                case "channel": replacement = value.wifiDetails.channel ?? "-"
                case "channelBand": replacement = value.wifiDetails.channelBand ?? "-"
                case "channelWidth": replacement = value.wifiDetails.channelWidth ?? "-"
                case "channelNumber": replacement = value.wifiDetails.channelNumber ?? "-"
                default: return
                }
            case "$status":
                replacement = localizedString(value.status ? "UP" : "DOWN")
            case "$upload":
                switch pair.value {
                case "total": replacement = Units(bytes: value.total.upload).getReadableMemory()
                default: replacement = Units(bytes: value.bandwidth.upload).getReadableMemory()
                }
            case "$download":
                switch pair.value {
                case "total": replacement = Units(bytes: value.total.download).getReadableMemory()
                default: replacement = Units(bytes: value.bandwidth.download).getReadableMemory()
                }
            case "$type":
                replacement = value.connectionType?.rawValue ?? "-"
            case "$icmp":
                guard let connectivity = connectivity else { return }
                switch pair.value {
                case "status": replacement = localizedString(connectivity.status ? "UP" : "DOWN")
                case "latency": replacement = "\(Int(connectivity.latency)) ms"
                default: return
                }
            default: return
            }

            if let replacement {
                let key = pair.value.isEmpty ? pair.key : "\(pair.key).\(pair.value)"
                text = text.replacingOccurrences(of: key, with: replacement)
            }
        }
        return text
    }
}
