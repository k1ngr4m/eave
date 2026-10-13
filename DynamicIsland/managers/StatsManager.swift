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
    let network = NetworkMonitor.shared
    @Published var networkDetailRequested = false
    weak var networkDetailViewModel: DynamicIslandViewModel?
    @Published var detail: MonitoringModule? {
        didSet {
            if detail != oldValue, let detail {
                samples[detail]?.processes = []
                samples[detail]?.processStatus = nil
                delayTask?.cancel()
            }
        }
    }
    private var samplingTask: Task<Void, Never>?
    private var delayTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "app.eave.monitoring", qos: .utility)
    private let reader = MonitoringReader()
    private var generation = 0
    private var cancellables = Set<AnyCancellable>()
    private var notchIsOpen = false
    private var currentView = "other"
    private var sleeping = false

    private init() {
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
            self.delayTask?.cancel()
            self.reconcile()
        }.store(in: &cancellables)
        Publishers.Merge(
            Defaults.publisher(.enableStatsFeature, options: []).map { _ in () },
            Defaults.publisher(.statsStopWhenNotchCloses, options: []).map { _ in () }
        ).receive(on: DispatchQueue.main).sink { [weak self] in self?.reconcile() }.store(in: &cancellables)
        Defaults.publisher(.statsUpdateInterval, options: []).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.delayTask?.cancel() }.store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.sleeping = true; self?.network.setEnabled(false); self?.stopMonitoring()
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
        network.setEnabled(Defaults[.enableStatsFeature] && enabledModules.contains(.network) && !sleeping)
        if MonitoringActivity.shouldRun(enabled: Defaults[.enableStatsFeature], hasModules: !enabledModules.isEmpty,
                                        sleeping: sleeping, notchIsOpen: notchIsOpen, statsSelected: currentView == "stats",
                                        stopWhenClosed: Defaults[.statsStopWhenNotchCloses]) {
            startMonitoring()
        } else { stopMonitoring() }
    }

    func startMonitoring() {
        guard !isMonitoring, !sleeping, Defaults[.enableStatsFeature], !enabledModules.isEmpty else { return }
        isMonitoring = true
        generation += 1
        let session = generation
        let reader = self.reader
        queue.async { reader.reset() }
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == session else { return }
                let modules = Set(self.enabledModules).subtracting([.network])
                let detail = self.detail
                let values = await withCheckedContinuation { continuation in
                    self.queue.async { continuation.resume(returning: reader.read(modules: modules, detail: detail)) }
                }
                guard !Task.isCancelled, self.generation == session else { return }
                let now = Date()
                self.samples = self.samples.filter { $0.key == .network && self.enabledModules.contains(.network) }
                    .merging(values.filter { self.enabledModules.contains($0.key) }) { _, new in new }
                if detail != self.detail {
                    for key in self.samples.keys { self.samples[key]?.processes = [] }
                }
                self.lastUpdated = now
                for (module, sample) in values where self.enabledModules.contains(module) {
                    self.history[module, default: []].append(.init(date: now, value: sample.value, secondary: sample.secondary))
                    self.history[module] = Array(self.history[module, default: []].suffix(60))
                }
                if detail != self.detail || modules != Set(self.enabledModules).subtracting([.network]) { continue }
                let configured = Defaults[.statsUpdateInterval]
                let seconds = configured.isFinite ? min(60, max(1, configured)) : 1
                let delay = Task<Void, Never> { try? await Task.sleep(for: .seconds(seconds)) }
                self.delayTask = delay
                await delay.value
            }
        }
    }

    func stopMonitoring() {
        generation += 1
        samplingTask?.cancel(); samplingTask = nil
        delayTask?.cancel(); delayTask = nil
        isMonitoring = false
    }

    func clearHistory() {
        samples = [:]; history = [:]; lastUpdated = nil
    }
}
