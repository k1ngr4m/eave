import Defaults
import SwiftUI
import Charts

extension MonitoringModule {
    var color: Color {
        switch self {
        case .cpu: return .blue
        case .memory: return .green
        case .gpu: return .purple
        case .disk: return .cyan
        case .network: return .orange
        case .sensors: return .pink
        }
    }
    var primaryLabel: String {
        switch self {
        case .disk: return String(localized: "Read")
        case .network: return String(localized: "Download")
        case .sensors: return String(localized: "Hottest sensor")
        default: return String(localized: "Usage")
        }
    }
    var secondaryLabel: String { self == .disk ? String(localized: "Write") : String(localized: "Upload") }
    var hasProcesses: Bool { self == .cpu || self == .memory || self == .disk || self == .network }
}

struct NotchStatsView: View {
    @ObservedObject private var manager = StatsManager.shared
    @Default(.enableStatsFeature) private var enabled
    @Default(.cpuTemperatureUnit) private var temperatureUnit
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var selected: MonitoringModule?

    var body: some View {
        Group {
            if !enabled || manager.enabledModules.isEmpty {
                ContentUnavailableView(enabled ? String(localized: "No Graphs Enabled") : String(localized: "Stats Disabled"),
                                       systemImage: "chart.xyaxis.line",
                                       description: Text("Enable graph visibility in Settings → Stats to view performance data."))
            } else {
                let columns = manager.enabledModules.count == 4 ? 2 : min(3, manager.enabledModules.count)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 12) {
                    ForEach(manager.enabledModules) { module in
                        Button { selected = module } label: { tile(module) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(module.title + ": " + module.unit.string(manager.samples[module]?.value, fahrenheit: temperatureUnit == .fahrenheit))
                            .popover(isPresented: Binding(get: { selected == module }, set: { if !$0 { selected = nil } })) {
                                if module == .network {
                                    NetworkMonitoringDetailView()
                                } else if module == .cpu || module == .gpu {
                                    ProcessorMonitoringDetailView(monitor: module == .cpu ? manager.cpu : manager.gpu)
                                } else {
                                    if module == .memory || module == .disk {
                                        MemoryDiskMonitoringDetailView(monitor: module == .memory ? manager.memory : manager.disk)
                                    } else { SensorsMonitoringDetailView() }
                                }
                            }
                    }
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            manager.updateMonitoringState(notchIsOpen: vm.notchState == .open, currentView: "stats")
            if manager.detailViewModel === vm { selected = manager.requestedDetail }
        }
        .onChange(of: manager.requestedDetail) { _, requested in
            if manager.detailViewModel === vm { selected = requested }
        }
        .onChange(of: selected) { _, value in
            vm.isStatsPopoverActive = value != nil
            manager.detail = value
            if let value {
                manager.detailViewModel = vm
                manager.requestedDetail = value
            } else if manager.detailViewModel === vm { manager.requestedDetail = nil }
        }
        .onChange(of: manager.enabledModules) { _, modules in
            if let selected, !modules.contains(selected) { self.selected = nil }
        }
        .onDisappear {
            selected = nil; manager.detail = nil; vm.isStatsPopoverActive = false
            if manager.detailViewModel === vm { manager.requestedDetail = nil }
        }
    }

    private func tile(_ module: MonitoringModule) -> some View {
        let sample = manager.samples[module]
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: module.icon).foregroundStyle(module.color)
                Text(module.title).fontWeight(.medium)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
            Text(module == .network ? manager.network.formattedSpeed(sample?.value ?? 0) : module == .disk ? manager.disk.formattedSpeed(sample?.value ?? 0) : module.unit.string(sample?.value, fahrenheit: temperatureUnit == .fahrenheit))
                .font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            HStack(spacing: 3) {
                Text(module.primaryLabel)
                if module == .disk || module == .network {
                    Spacer(minLength: 0)
                    Text(module.secondaryLabel + " " + (module == .network ? manager.network.formattedSpeed(sample?.secondary ?? 0) : manager.disk.formattedSpeed(sample?.secondary ?? 0)))
                }
            }
            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            MonitoringHistoryChart(module: module, points: manager.history[module] ?? [])
                .frame(height: 25)
                .accessibilityHidden(true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(module.color.opacity(0.15), lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MonitoringHistoryChart: View {
    let module: MonitoringModule
    let points: [MonitoringPoint]
    private var ceiling: Double {
        if module.unit == .percent { return 100 }
        return max(1, points.flatMap { [$0.value, $0.secondary].compactMap { $0 } }.max() ?? 1) * 1.1
    }
    var body: some View {
        Chart(points) { point in
            if let value = point.value {
                LineMark(x: .value("Time", point.date), y: .value("Value", value), series: .value("Series", "Primary"))
                    .foregroundStyle(module.color).lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            if let value = point.secondary {
                LineMark(x: .value("Time", point.date), y: .value("Value", value), series: .value("Series", "Secondary"))
                    .foregroundStyle(module.color.opacity(0.45)).lineStyle(StrokeStyle(lineWidth: 1.2))
            }
        }
        .chartYScale(domain: 0...ceiling)
        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
    }
}

private struct MonitoringDetailView: View {
    let module: MonitoringModule
    @ObservedObject private var manager = StatsManager.shared
    @Default(.cpuTemperatureUnit) private var temperatureUnit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let sample = manager.samples[module] ?? MonitoringSample()
        VStack(spacing: 0) {
            HStack {
                Label(module.title, systemImage: module.icon).font(.headline)
                Spacer()
                Text(manager.isMonitoring ? String(localized: "Live") : String(localized: "Stopped"))
                    .font(.caption).foregroundStyle(.secondary)
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel(Text("Close"))
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(module.primaryLabel).font(.caption).foregroundStyle(.secondary)
                            Text(module.unit.string(sample.value, fahrenheit: temperatureUnit == .fahrenheit)).font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(module.color)
                        }
                        Spacer()
                        if module == .disk || module == .network {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(module.secondaryLabel).font(.caption).foregroundStyle(.secondary)
                                Text(module.unit.string(sample.secondary)).font(.title2).foregroundStyle(module.color.opacity(0.65))
                            }
                        }
                    }
                    MonitoringHistoryChart(module: module, points: manager.history[module] ?? []).frame(height: 65)
                        .accessibilityLabel(Text("Recent history"))
                    if sample.sections.isEmpty {
                        Text(manager.lastUpdated == nil ? "Waiting for sample…" : "No readable data on this Mac.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(sample.sections) { section in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(section.title).font(.headline)
                            ForEach(section.rows) { row in metric(row) }
                        }
                        .padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if module.hasProcesses {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Top Processes").font(.headline)
                            if module == .network || module == .disk {
                                Text(module.primaryLabel + " / " + module.secondaryLabel).font(.caption).foregroundStyle(.secondary)
                            }
                            if sample.processes.isEmpty {
                                Text(sample.processStatus ?? String(localized: "Waiting for process sample…")).font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(sample.processes) { row in metric(row) }
                        }.padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let date = manager.lastUpdated {
                        Text(date, style: .time).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }.padding(16)
            }
        }
        .frame(width: 420, height: 530)
    }

    private func metric(_ row: MonitoringRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.label).lineLimit(2).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(row.text ?? row.unit.string(row.value, fahrenheit: temperatureUnit == .fahrenheit))
                .monospacedDigit().textSelection(.enabled)
        }.font(.system(size: 11))
    }
}
