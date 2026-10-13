import SwiftUI
import Defaults
import EaveNetworkStats

extension MonitoringModule {
    var widgets: StatsWidgets {
        switch self {
        case .cpu: return ProcessorMonitor.cpu.widgets
        case .memory: return MemoryDiskMonitor.memory.widgets
        case .gpu: return ProcessorMonitor.gpu.widgets
        case .disk: return MemoryDiskMonitor.disk.widgets
        case .network: return NetworkMonitor.shared.widgets
        case .sensors: return SensorsMonitor.shared.widgets
        }
    }
}

struct MonitoringWidgetPreview: View {
    @ObservedObject var widgets: StatsWidgets

    var body: some View {
        Group {
            if widgets.size.width > 0 {
                Image(nsImage: widgets.image)
                    .resizable().scaledToFit()
                    .frame(width: widgets.size.width, height: ClosedMonitoringWidgets.height)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 48, minHeight: 32)
        .padding(8)
        .background(.black, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}

/// Stats widgets share one row above lyrics; each module opens its own native details.
struct ClosedMonitoringWidgets: View {
    static let height: CGFloat = 22
    static var entries: [(MonitoringModule, StatsWidgets)] {
        let candidates: [(MonitoringModule, Bool, StatsWidgets)] = [(.cpu, Defaults[.showCPUWidgetWhenClosed], ProcessorMonitor.cpu.widgets),
         (.memory, Defaults[.showMemoryWidgetWhenClosed], MemoryDiskMonitor.memory.widgets),
         (.disk, Defaults[.showDiskWidgetWhenClosed], MemoryDiskMonitor.disk.widgets),
         (.gpu, Defaults[.showGPUWidgetWhenClosed], ProcessorMonitor.gpu.widgets),
         (.network, Defaults[.showNetworkWidgetWhenClosed], NetworkMonitor.shared.widgets),
         (.sensors, Defaults[.showSensorsWidgetWhenClosed], SensorsMonitor.shared.widgets)]
        return MonitoringModule.ordered(Defaults[.statsModuleOrder]).compactMap { module in
            guard let entry = candidates.first(where: { $0.0 == module }), entry.1, entry.2.size.width > 0 else { return nil }
            return (entry.0, entry.2)
        }
    }
    static var naturalWidth: CGFloat { entries.reduce(0) { $0 + $1.1.size.width } + CGFloat(max(0, entries.count - 1)) * 8 }
    static var minimumWidth: CGFloat { max(190, min(600, naturalWidth + 16)) }

    @Default(.statsModuleOrder) private var moduleOrder
    @Default(.showMemoryWidgetWhenClosed) private var showMemory
    @Default(.showDiskWidgetWhenClosed) private var showDisk
    @ObservedObject private var memoryWidgets = MemoryDiskMonitor.memory.widgets
    @ObservedObject private var diskWidgets = MemoryDiskMonitor.disk.widgets
    @Default(.showSensorsWidgetWhenClosed) private var showSensors
    @ObservedObject private var sensorsWidgets = SensorsMonitor.shared.widgets
    @Default(.showCPUWidgetWhenClosed) private var showCPU
    @Default(.showGPUWidgetWhenClosed) private var showGPU
    @Default(.showNetworkWidgetWhenClosed) private var showNetwork
    @ObservedObject private var cpuWidgets = ProcessorMonitor.cpu.widgets
    @ObservedObject private var gpuWidgets = ProcessorMonitor.gpu.widgets
    @ObservedObject private var networkWidgets = NetworkMonitor.shared.widgets
    var onHover: (Bool) -> Void = { _ in }

    var body: some View {
        let scale = min(1, (Self.minimumWidth - 16) / max(1, Self.naturalWidth))
        HStack(spacing: 8 * scale) {
            ForEach(Self.entries, id: \.0) { module, widgets in
                MonitoringWidgetButton(module: module, widgets: widgets, scale: scale)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onDisappear { onHover(false) }
    }
}

private struct MonitoringWidgetButton: View {
    let module: MonitoringModule
    @ObservedObject var widgets: StatsWidgets
    let scale: CGFloat
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var isPresented = false

    private var memoryDisk: MemoryDiskMonitor { module == .memory ? .memory : .disk }
    private var processor: ProcessorMonitor { module == .cpu ? .cpu : .gpu }
    private var accessibilityValue: String {
        if module == .sensors { return SensorsMonitor.shared.sensorDescription }
        if module == .network {
            let network = NetworkMonitor.shared
            return "↓ \(network.formattedSpeed(network.rates.download)), ↑ \(network.formattedSpeed(network.rates.upload))"
        }
        if module == .disk { return "↓ \(memoryDisk.formattedSpeed(memoryDisk.rates.read)), ↑ \(memoryDisk.formattedSpeed(memoryDisk.rates.write))" }
        let utilization = module == .memory ? memoryDisk.utilization : processor.utilization
        return MonitoringUnit.percent.string(utilization.map { $0 * 100 })
    }

    var body: some View {
        Button { isPresented = true } label: {
            Image(nsImage: widgets.image)
                .resizable().scaledToFit()
                .frame(width: widgets.size.width * scale, height: ClosedMonitoringWidgets.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(module == .sensors ? Text("Open sensor details") : module == .network ? Text("Open network details") : module == .cpu ? Text("Open CPU details") : module == .gpu ? Text("Open GPU details") : module == .memory ? Text("Open memory details") : Text("Open disk details"))
        .accessibilityIdentifier(module == .sensors ? "ClosedSensorsWidget" : module == .network ? "ClosedNetworkWidget" : module == .cpu ? "ClosedCPUWidget" : module == .gpu ? "ClosedGPUWidget" : module == .memory ? "ClosedMemoryWidget" : "ClosedDiskWidget")
        .accessibilityLabel(Text("\(module.title): \(accessibilityValue)"))
        .contextMenu {
            Button("Settings…") {
                if module == .sensors { SensorsMonitor.shared.showSettings() }
                else if module == .network { NetworkMonitor.shared.showSettings() }
                else if module == .memory || module == .disk { memoryDisk.showSettings() }
                else { processor.showSettings() }
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            if module == .sensors { SensorsMonitoringDetailView() }
            else if module == .network { NetworkMonitoringDetailView() }
            else if module == .memory || module == .disk { MemoryDiskMonitoringDetailView(monitor: memoryDisk) }
            else { ProcessorMonitoringDetailView(monitor: processor) }
        }
        .onChange(of: isPresented) { _, value in vm.isStatsPopoverActive = value }
        .onDisappear { isPresented = false; vm.isStatsPopoverActive = false }
    }
}
