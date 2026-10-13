import AppKit

final class MemoryDiskWidgets: StatsWidgets {
    private var memory: RAM_Usage?
    private var capacity: drive?
    private var activity: drive?

    override init(module: ModuleType) {
        super.init(module: module)
        refreshValues = { [weak self] in
            guard let self else { return }
            if let value = self.memory { self.updateMemory(value, appendHistory: false) }
            if let value = self.capacity { self.updateCapacity(value) }
            if let value = self.activity { self.updateActivity(value, appendHistory: false) }
        }
    }

    func receive(_ value: RAM_Usage) {
        memory = value
        updateMemory(value, appendHistory: true)
        scheduleRender()
    }

    func receiveCapacity(_ value: drive) {
        capacity = value
        updateCapacity(value)
        scheduleRender()
    }

    func receiveActivity(_ value: drive, appendHistory: Bool = true) {
        activity = value
        updateActivity(value, appendHistory: appendHistory)
        scheduleRender()
    }

    private var splitValueState: Bool {
        return Store.shared.bool(key: "\(module)_splitValue", defaultValue: false)
    }
    private var appColor: NSColor {
        let color = SColor.secondBlue
        let key = Store.shared.string(key: "\(module)_appColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    private var wiredColor: NSColor {
        let color = SColor.secondOrange
        let key = Store.shared.string(key: "\(module)_wiredColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    private var compressedColor: NSColor {
        let color = SColor.pink
        let key = Store.shared.string(key: "\(module)_compressedColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }

    private var textValue: String {
        Store.shared.string(key: "\(module)_textWidgetValue", defaultValue: "$mem.used/$mem.total ($pressure.value)")
    }


    private var mainColor: NSColor {
        SColor.fromString(Store.shared.string(key: "Disk_mainColor", defaultValue: SColor.secondBlue.key)).additional as? NSColor ?? .systemBlue
    }

    private func updateMemory(_ value: RAM_Usage, appendHistory: Bool) {
        let total: Double = value.total == 0 ? 1 : value.total
        active.forEach { (w: SWidget) in
            switch w.item {
            case let widget as Mini:
                widget.setValue(value.usage)
                widget.setPressure(value.pressure.value)
            case let widget as LineChart where appendHistory:
                widget.setValue(value.usage)
                widget.setPressure(value.pressure.value)
            case let widget as BarChart:
                if self.splitValueState {
                    widget.setValue([[
                        ColorValue(value.app/total, color: self.appColor),
                        ColorValue(value.wired/total, color: self.wiredColor),
                        ColorValue(value.compressed/total, color: self.compressedColor)
                    ]])
                } else {
                    widget.setValue([[ColorValue(value.usage)]])
                    widget.setColorZones((0.8, 0.95))
                    widget.setPressure(value.pressure.value)
                }
            case let widget as PieChart:
                widget.setValue([
                    ColorValue(value.app/total, color: self.appColor),
                    ColorValue(value.wired/total, color: self.wiredColor),
                    ColorValue(value.compressed/total, color: self.compressedColor)
                ])
            case let widget as MemoryWidget:
                let free = Units(bytes: Int64(value.free)).getReadableMemory(style: .memory)
                let used = Units(bytes: Int64(value.used)).getReadableMemory(style: .memory)
                widget.setValue((free, used), usedPercentage: value.usage)
                widget.setPressure(value.pressure.value)
            case let widget as Tachometer:
                widget.setValue([
                    ColorValue(value.app/total, color: self.appColor),
                    ColorValue(value.wired/total, color: self.wiredColor),
                    ColorValue(value.compressed/total, color: self.compressedColor)
                ])
            case let widget as TextWidget:
                var text = "\(self.textValue)"
                let pairs = TextWidget.parseText(text)
                pairs.forEach { pair in
                    var replacement: String? = nil

                    switch pair.key {
                    case "$mem":
                        switch pair.value {
                        case "total": replacement = Units(bytes: Int64(value.total)).getReadableMemory(style: .memory)
                        case "used": replacement = Units(bytes: Int64(value.used)).getReadableMemory(style: .memory)
                        case "free": replacement = Units(bytes: Int64(value.free)).getReadableMemory(style: .memory)
                        case "active": replacement = Units(bytes: Int64(value.active)).getReadableMemory(style: .memory)
                        case "inactive": replacement = Units(bytes: Int64(value.inactive)).getReadableMemory(style: .memory)
                        case "wired": replacement = Units(bytes: Int64(value.wired)).getReadableMemory(style: .memory)
                        case "compressed": replacement = Units(bytes: Int64(value.compressed)).getReadableMemory(style: .memory)
                        case "app": replacement = Units(bytes: Int64(value.app)).getReadableMemory(style: .memory)
                        case "cache": replacement = Units(bytes: Int64(value.cache)).getReadableMemory(style: .memory)
                        case "swapins": replacement = "\(value.swapins)"
                        case "swapouts": replacement = "\(value.swapouts)"
                        default: return
                        }
                    case "$swap":
                        switch pair.value {
                        case "total": replacement = Units(bytes: Int64(value.swap.total)).getReadableMemory(style: .memory)
                        case "used": replacement = Units(bytes: Int64(value.swap.used)).getReadableMemory(style: .memory)
                        case "free": replacement = Units(bytes: Int64(value.swap.free)).getReadableMemory(style: .memory)
                        default: return
                        }
                    case "$pressure":
                        switch pair.value {
                        case "level": replacement = "\(value.pressure.level)"
                        case "value": replacement = value.pressure.value.rawValue
                        default: return
                        }
                    default: return
                    }

                    if let replacement {
                        let key = pair.value.isEmpty ? pair.key : "\(pair.key).\(pair.value)"
                        text = text.replacingOccurrences(of: key, with: replacement)
                    }
                }
                widget.setValue(text)
            case let widget as DotWidget: widget.setValue(value.pressure.value.pressureColor())
            default: break
            }
        }

    }

    private func updateCapacity(_ d: drive) {
        active.forEach { (w: SWidget) in
            switch w.item {
            case let widget as Mini: widget.setValue(d.percentage)
            case let widget as BarChart: widget.setValue([[ColorValue(d.percentage)]])
            case let widget as MemoryWidget:
                widget.setValue((DiskSize(d.free).getReadableMemory(), DiskSize(d.size - d.free).getReadableMemory()), usedPercentage: d.percentage)
            case let widget as PieChart:
                widget.setValue([
                    ColorValue(d.percentage, color: self.mainColor)
                ])
            case let widget as TextWidget:
                var text = "\(Store.shared.string(key: "Disk_textWidgetValue", defaultValue: "$capacity.free/$capacity.total"))"
                let pairs = TextWidget.parseText(text)
                pairs.forEach { pair in
                    var replacement: String? = nil

                    switch pair.key {
                    case "$capacity":
                        switch pair.value {
                        case "total": replacement = DiskSize(d.size).getReadableMemory()
                        case "used": replacement = DiskSize(d.size - d.free).getReadableMemory()
                        case "free": replacement = DiskSize(d.free).getReadableMemory()
                        default: return
                        }
                    case "$percentage":
                        var percentage: Int
                        if d.size == 0 {
                            percentage = 0
                        } else {
                            switch pair.value {
                            case "used": percentage = Int((Double(d.size - d.free) / Double(d.size)) * 100)
                            case "free": percentage = Int((Double(d.free) / Double(d.size)) * 100)
                            default: return
                            }
                        }
                        replacement = "\(percentage < 0 ? 0 : percentage)%"
                    default: return
                    }

                    if let replacement {
                        let key = pair.value.isEmpty ? pair.key : "\(pair.key).\(pair.value)"
                        text = text.replacingOccurrences(of: key, with: replacement)
                    }
                }
                widget.setValue(text)
            default: break
            }
        }

    }

    private func updateActivity(_ d: drive, appendHistory: Bool) {
        for w in active {
            switch w.item {
            case let widget as SpeedWidget: widget.setValue(input: d.activity.read, output: d.activity.write)
            case let widget as NetworkChart where appendHistory:
                widget.setValue(upload: Double(d.activity.write), download: Double(d.activity.read))
            default: break
            }
        }
    }
}
