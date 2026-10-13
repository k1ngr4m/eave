import AppKit

final class ProcessorWidgets: StatsWidgets {
    private var lastCPU: CPU_Load?
    private var lastGPU: GPU_Info?

    override init(module: ModuleType) {
        super.init(module: module)
        refreshValues = { [weak self] in
            guard let self else { return }
            if let value = self.lastCPU { self.updateCPU(value, appendHistory: false) }
            if let value = self.lastGPU { self.updateGPU(value, appendHistory: false) }
        }
    }

    func receive(_ value: CPU_Load) {
        lastCPU = value
        updateCPU(value, appendHistory: true)
        scheduleRender()
    }

    func receive(_ value: GPU_Info) {
        lastGPU = value
        updateGPU(value, appendHistory: true)
        scheduleRender()
    }

    private var usagePerCoreState: Bool {
        Store.shared.bool(key: "CPU_usagePerCore", defaultValue: false)
    }
    private var splitValueState: Bool {
        Store.shared.bool(key: "CPU_splitValue", defaultValue: false)
    }
    private var groupByClustersState: Bool {
        Store.shared.bool(key: "CPU_clustersGroup", defaultValue: false)
    }
    private var systemColor: NSColor {
        let color = SColor.secondRed
        let key = Store.shared.string(key: "CPU_systemColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    private var userColor: NSColor {
        let color = SColor.secondBlue
        let key = Store.shared.string(key: "CPU_userColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }

    private var eCoresColor: NSColor {
        let color = SColor.teal
        let key = Store.shared.string(key: "CPU_eCoresColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    private var pCoresColor: NSColor {
        let color = SColor.indigo
        let key = Store.shared.string(key: "CPU_pCoresColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    private var sCoresColor: NSColor {
        let color = SColor.orange
        let key = Store.shared.string(key: "CPU_sCoresColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }

    private func updateCPU(_ value: CPU_Load, appendHistory: Bool) {
        active.forEach { [self] (w: SWidget) in
            switch w.item {
            case let widget as Mini: widget.setValue(value.totalUsage)
            case let widget as LineChart where appendHistory: widget.setValue(value.totalUsage)
            case let widget as BarChart:
                var val: [[ColorValue]] = [[ColorValue(value.totalUsage)]]
                let cores = SystemKit.shared.device.info.cpu?.cores ?? []

                if self.usagePerCoreState {
                    if widget.colorState == .cluster {
                        val = []
                        for (i, v) in value.usagePerCore.enumerated() {
                            let core = cores.first(where: {$0.id == i })
                            let color = core?.type == .efficiency ? self.eCoresColor : core?.type == .super ? self.sCoresColor : self.pCoresColor
                            val.append([ColorValue(v, color: color)])
                        }
                    } else {
                        val = value.usagePerCore.map({ [ColorValue($0)] })
                    }
                } else if self.splitValueState {
                    val = [[
                        ColorValue(value.systemLoad, color: self.systemColor),
                        ColorValue(value.userLoad, color: self.userColor)
                    ]]
                } else if self.groupByClustersState {
                    var clusters: [[ColorValue]] = []
                    var clustersPlain: [[ColorValue]] = []

                    if let e = value.usageECores {
                        clusters.append([ColorValue(e, color: self.eCoresColor)])
                        clustersPlain.append([ColorValue(e)])
                    }
                    if let p = value.usagePCores {
                        clusters.append([ColorValue(p, color: self.pCoresColor)])
                        clustersPlain.append([ColorValue(p)])
                    }
                    if let s = value.usageSCores {
                        clusters.append([ColorValue(s, color: self.sCoresColor)])
                        clustersPlain.append([ColorValue(s)])
                    }

                    if !clusters.isEmpty {
                        val = widget.colorState == .cluster ? clusters : clustersPlain
                    }
                }
                widget.setValue(val)
            case let widget as PieChart:
                widget.setValue([
                    ColorValue(value.systemLoad, color: self.systemColor),
                    ColorValue(value.userLoad, color: self.userColor)
                ])
            case let widget as Tachometer:
                widget.setValue([
                    ColorValue(value.systemLoad, color: self.systemColor),
                    ColorValue(value.userLoad, color: self.userColor)
                ])
            default: break
            }
        }
    }

    private func updateGPU(_ selectedGPU: GPU_Info, appendHistory: Bool) {
        guard let utilization = selectedGPU.utilization else { return }
        active.forEach { (w: SWidget) in
            switch w.item {
            case let widget as Mini:
                widget.setValue(utilization)
                widget.setTitle(Store.shared.bool(key: "GPU_showType", defaultValue: false) ? "\(selectedGPU.type)GPU" : nil)
            case let widget as LineChart where appendHistory: widget.setValue(utilization)
            case let widget as BarChart: widget.setValue([[ColorValue(utilization)]])
            case let widget as Tachometer:
                widget.setValue([
                    ColorValue(utilization, color: NSColor.systemBlue)
                ])
            case let widget as TextWidget:
                var text = Store.shared.string(key: "GPU_textWidgetValue", defaultValue: "$usage - $fps")
                let pairs = TextWidget.parseText(text)
                pairs.forEach { pair in
                    var replacement: String? = nil

                    switch pair.key {
                    case "$usage": replacement = "\(Int(utilization*100))%"
                    case "$render": replacement = "\(Int((selectedGPU.renderUtilization ?? 0)*100))%"
                    case "$tiler": replacement = "\(Int((selectedGPU.tilerUtilization ?? 0)*100))%"
                    case "$ane": replacement = "\(Int((selectedGPU.aneUtilization ?? 0)*100))%"
                    case "$fps": replacement = "\(Int((selectedGPU.fps ?? 0).rounded()))"
                    case "$temperature": replacement = temperature(selectedGPU.temperature ?? 0)
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
}
