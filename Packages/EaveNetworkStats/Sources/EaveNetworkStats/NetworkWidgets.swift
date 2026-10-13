import AppKit

public final class NetworkWidgets: StatsWidgets {
    private var lastUsage = Network_Usage()
    private var connectivity: Network_Connectivity?

    public init() {
        super.init(module: .network)
        refreshValues = { [weak self] in self?.updateValues(appendHistory: false) }
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
