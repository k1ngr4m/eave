import AppKit
import Combine
import Defaults
import Foundation
import EaveNetworkStats

extension MonitoringModule {
    var visibilityKey: Defaults.Key<Bool> {
        switch self {
        case .cpu: return .showCpuGraph
        case .memory: return .showMemoryGraph
        case .gpu: return .showGpuGraph
        case .disk: return .showDiskGraph
        case .network: return .showNetworkGraph
        case .sensors: return .showSensorsGraph
        }
    }
}

@MainActor
final class StatsManager: ObservableObject {
    static let shared = StatsManager()
    @Published private(set) var isMonitoring = false
    @Published private(set) var samples: [MonitoringModule: MonitoringSample] = [:]
    @Published private(set) var history: [MonitoringModule: [MonitoringPoint]] = [:]
    @Published private(set) var enabledModules: [MonitoringModule] = []
    @Published private(set) var lastUpdated: Date?
    let cpu = ProcessorMonitor.cpu
    let gpu = ProcessorMonitor.gpu
    let memory = MemoryDiskMonitor.memory
    let disk = MemoryDiskMonitor.disk
    let sensors = SensorsMonitor.shared
    let network = NetworkMonitor.shared
    @Published var requestedDetail: MonitoringModule?
    weak var detailViewModel: DynamicIslandViewModel?
    @Published var detail: MonitoringModule?
    private var cancellables = Set<AnyCancellable>()
    private var notchIsOpen = false
    private var currentView = "other"
    private var sleeping = false

    private init() {
        HardwareAccess.smcKeys = { SMC.shared.getAllKeys() }
        HardwareAccess.smcString = { SMC.shared.getStringValue($0) }
        HardwareAccess.smcValue = { SMC.shared.getValue($0) }
        HardwareAccess.temperatureUnit = Defaults[.cpuTemperatureUnit].rawValue.lowercased()
        Defaults.publisher(.cpuTemperatureUnit, options: []).receive(on: DispatchQueue.main).sink { _ in
            HardwareAccess.temperatureUnit = Defaults[.cpuTemperatureUnit].rawValue.lowercased()
        }.store(in: &cancellables)
        for (module, monitor) in [(MonitoringModule.cpu, cpu), (.gpu, gpu)] {
            monitor.$utilization.dropFirst().receive(on: DispatchQueue.main).sink { [weak self, weak monitor] value in
                guard let self, monitor?.isEnabled == true, self.enabledModules.contains(module) else { return }
                let percent = value.map { $0 * 100 }
                let now = Date()
                self.samples[module] = MonitoringSample(value: percent)
                self.history[module, default: []].append(.init(date: now, value: percent, secondary: nil))
                self.history[module] = Array(self.history[module, default: []].suffix(60))
                self.lastUpdated = now
            }.store(in: &cancellables)
            monitor.$settingsVisible.dropFirst().receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.reconcile() }.store(in: &cancellables)
        }
        Publishers.Merge(Defaults.publisher(.showCPUWidgetWhenClosed, options: []).map { _ in () },
                         Defaults.publisher(.showGPUWidgetWhenClosed, options: []).map { _ in () })
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.reconcile() }.store(in: &cancellables)

        memory.$utilization.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] value in
            guard let self, self.memory.isEnabled, self.enabledModules.contains(.memory) else { return }
            let now = Date()
            let percent = value.map { $0 * 100 }
            self.samples[.memory] = MonitoringSample(value: percent)
            self.history[.memory, default: []].append(.init(date: now, value: percent, secondary: nil))
            self.history[.memory] = Array(self.history[.memory, default: []].suffix(60))
            self.lastUpdated = now
        }.store(in: &cancellables)
        disk.$rates.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] rates in
            guard let self, self.disk.isEnabled, self.enabledModules.contains(.disk) else { return }
            let now = Date()
            self.samples[.disk] = MonitoringSample(value: rates.read, secondary: rates.write)
            self.history[.disk, default: []].append(.init(date: now, value: rates.read, secondary: rates.write))
            self.history[.disk] = Array(self.history[.disk, default: []].suffix(60))
            self.lastUpdated = now
        }.store(in: &cancellables)
        for monitor in [memory, disk] {
            monitor.$settingsVisible.dropFirst().receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.reconcile() }.store(in: &cancellables)
        }
        Publishers.Merge(Defaults.publisher(.showMemoryWidgetWhenClosed, options: []).map { _ in () },
                         Defaults.publisher(.showDiskWidgetWhenClosed, options: []).map { _ in () })
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.reconcile() }.store(in: &cancellables)

        sensors.$hottestTemperature.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] value in
            guard let self, self.sensors.isEnabled, self.enabledModules.contains(.sensors) else { return }
            let now = Date()
            self.samples[.sensors] = MonitoringSample(value: value)
            self.history[.sensors, default: []].append(.init(date: now, value: value, secondary: nil))
            self.history[.sensors] = Array(self.history[.sensors, default: []].suffix(60))
            self.lastUpdated = now
        }.store(in: &cancellables)
        sensors.$settingsVisible.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcile() }.store(in: &cancellables)
        Defaults.publisher(.showSensorsWidgetWhenClosed, options: []).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcile() }.store(in: &cancellables)

        network.$rates.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] rates in
            guard let self, self.network.isEnabled, self.enabledModules.contains(.network) else { return }
            let now = Date()
            self.samples[.network] = MonitoringSample(value: rates.download, secondary: rates.upload)
            self.history[.network, default: []].append(.init(date: now, value: rates.download, secondary: rates.upload))
            self.history[.network] = Array(self.history[.network, default: []].suffix(60))
            self.lastUpdated = now
        }.store(in: &cancellables)
        enabledModules = MonitoringModule.allCases.filter { Defaults[$0.visibilityKey] }
        Publishers.MergeMany(MonitoringModule.allCases.map {
            Defaults.publisher($0.visibilityKey, options: []).map { _ in () }.eraseToAnyPublisher()
        }).receive(on: DispatchQueue.main).sink { [weak self] in
            guard let self else { return }
            self.enabledModules = MonitoringModule.allCases.filter { Defaults[$0.visibilityKey] }
            self.samples = self.samples.filter { self.enabledModules.contains($0.key) }
            self.history = self.history.filter { self.enabledModules.contains($0.key) }
            if let detail = self.detail, !self.enabledModules.contains(detail) { self.detail = nil }
            self.reconcile()
        }.store(in: &cancellables)
        Publishers.Merge(
            Defaults.publisher(.enableStatsFeature, options: []).map { _ in () },
            Defaults.publisher(.statsStopWhenNotchCloses, options: []).map { _ in () }
        ).receive(on: DispatchQueue.main).sink { [weak self] in self?.reconcile() }.store(in: &cancellables)
        Defaults.publisher(.showNetworkWidgetWhenClosed, options: []).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcile() }.store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.sleeping = true; self?.reconcile()
            }.store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.sleeping = false; self?.reconcile()
            }.store(in: &cancellables)
        reconcile()
    }

    func updateMonitoringState(notchIsOpen: Bool, currentView: String) {
        self.notchIsOpen = notchIsOpen; self.currentView = currentView
        reconcile()
    }

    private func reconcile() {
        network.setEnabled(Defaults[.enableStatsFeature] && (enabledModules.contains(.network) || Defaults[.showNetworkWidgetWhenClosed]) && !sleeping)
        let shouldRun = MonitoringActivity.shouldRun(enabled: Defaults[.enableStatsFeature], hasModules: !enabledModules.isEmpty,
                                        sleeping: sleeping, notchIsOpen: notchIsOpen, statsSelected: currentView == "stats",
                                        stopWhenClosed: Defaults[.statsStopWhenNotchCloses])
        for (module, monitor, widget) in [(MonitoringModule.cpu, cpu, Defaults[.showCPUWidgetWhenClosed]),
                                          (.gpu, gpu, Defaults[.showGPUWidgetWhenClosed])] {
            monitor.setEnabled(Defaults[.enableStatsFeature] && !sleeping &&
                ((shouldRun && enabledModules.contains(module)) || widget || monitor.settingsVisible))
        }
        for (module, monitor, widget) in [(MonitoringModule.memory, memory, Defaults[.showMemoryWidgetWhenClosed]),
                                          (.disk, disk, Defaults[.showDiskWidgetWhenClosed])] {
            monitor.setEnabled(Defaults[.enableStatsFeature] && !sleeping &&
                ((shouldRun && enabledModules.contains(module)) || widget || monitor.settingsVisible))
        }
        sensors.setEnabled(Defaults[.enableStatsFeature] && !sleeping &&
            ((shouldRun && enabledModules.contains(.sensors)) || Defaults[.showSensorsWidgetWhenClosed] || sensors.settingsVisible))
        if shouldRun { startMonitoring() } else { stopMonitoring() }
    }

    func startMonitoring() {
        guard !isMonitoring, !sleeping, Defaults[.enableStatsFeature], !enabledModules.isEmpty else { return }
        if enabledModules.contains(.cpu) { cpu.setEnabled(true) }
        if enabledModules.contains(.gpu) { gpu.setEnabled(true) }
        if enabledModules.contains(.memory) { memory.setEnabled(true) }
        if enabledModules.contains(.disk) { disk.setEnabled(true) }
        if enabledModules.contains(.sensors) { sensors.setEnabled(true) }
        isMonitoring = true
    }

    func stopMonitoring() {
        if !Defaults[.showMemoryWidgetWhenClosed] && !memory.settingsVisible { memory.setEnabled(false) }
        if !Defaults[.showDiskWidgetWhenClosed] && !disk.settingsVisible { disk.setEnabled(false) }
        if !Defaults[.showCPUWidgetWhenClosed] && !cpu.settingsVisible { cpu.setEnabled(false) }
        if !Defaults[.showGPUWidgetWhenClosed] && !gpu.settingsVisible { gpu.setEnabled(false) }
        if !Defaults[.showSensorsWidgetWhenClosed] && !sensors.settingsVisible { sensors.setEnabled(false) }
        isMonitoring = false
    }

    func clearHistory() {
        samples = [:]; history = [:]; lastUpdated = nil
    }
}
