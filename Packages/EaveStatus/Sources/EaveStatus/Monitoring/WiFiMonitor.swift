import CoreWLAN
import Foundation
import SystemConfiguration
import os

private let wifiMonitorLogger = Logger(
    subsystem: "com.lingsmbp.StatusTrio",
    category: "WiFiMonitor"
)

enum WiFiInterfaceMode: Equatable, Sendable {
    case none
    case station
    case ibss
    case hostAP
    case unknown

    init(coreWLANMode: CWInterfaceMode) {
        switch coreWLANMode {
        case .none:
            self = .none
        case .station:
            self = .station
        case .IBSS:
            self = .ibss
        case .hostAP:
            self = .hostAP
        @unknown default:
            self = .unknown
        }
    }
}

struct WiFiClassificationInput: Equatable, Sendable {
    var powerOn: Bool
    var serviceActive: Bool
    var mode: WiFiInterfaceMode
    var pathSatisfied: Bool?
    var pathUsesWiFi: Bool
    var pathExpensive: Bool
    var sharingActive: Bool
}

enum WiFiClassifier {
    static func classify(_ input: WiFiClassificationInput) -> WiFiState {
        if !input.powerOn { return .off }
        if !input.serviceActive { return .notAssociated }
        if input.sharingActive { return .shared }
        if input.mode == .ibss { return .temporary }

        if let pathSatisfied = input.pathSatisfied {
            if pathSatisfied && input.pathUsesWiFi && input.pathExpensive {
                return .hotspot
            }
            if !pathSatisfied {
                return .noInternet
            }
        }

        return .connected
    }
}

struct WiFiSystemReading: Equatable, Sendable {
    var powerOn: Bool
    var serviceActive: Bool
    var mode: WiFiInterfaceMode
    var rssi: Int?
    var ssid: String?
    var band: WiFiFrequencyBand? = nil
}

protocol WiFiSystemReadingProviding: AnyObject {
    func read() -> WiFiSystemReading?
    func read(includeSSID: Bool) -> WiFiSystemReading?
}

extension WiFiSystemReadingProviding {
    func read(includeSSID: Bool) -> WiFiSystemReading? {
        read()
    }
}

protocol InternetSharingDetecting: AnyObject {
    func isActive() -> Bool?
}

protocol WiFiEventMonitoring: AnyObject {
    func start(delegate: any CWEventDelegate, events: [CWEventType])
    func restart(delegate: any CWEventDelegate, events: [CWEventType])
    func stop()
}

typealias WiFiClientFactory = () -> CWWiFiClient

final class CoreWLANWiFiSystemReader: WiFiSystemReadingProviding {
    private let client: CWWiFiClient

    init(client: CWWiFiClient = CWWiFiClient.shared()) {
        self.client = client
    }

    func read() -> WiFiSystemReading? {
        read(includeSSID: true)
    }

    func read(includeSSID: Bool) -> WiFiSystemReading? {
        guard let interface = client.interface() else { return nil }

        let powerOn = interface.powerOn()
        let serviceActive = interface.serviceActive()
        return WiFiSystemReading(
            powerOn: powerOn,
            serviceActive: serviceActive,
            mode: WiFiInterfaceMode(coreWLANMode: interface.interfaceMode()),
            rssi: interface.rssiValue(),
            ssid: includeSSID ? interface.ssid() : nil,
            // includeSSID is the existing visible-details gate. This reads the
            // associated interface only; it never requests a network scan.
            band: includeSSID && powerOn && serviceActive ? interface.wlanChannel().flatMap {
                WiFiFrequencyBand(coreWLANBand: $0.channelBand)
            } : nil
        )
    }
}

final class CoreWLANWiFiEventMonitor: WiFiEventMonitoring {
    private let clientFactory: WiFiClientFactory
    private var client: CWWiFiClient

    init(clientFactory: @escaping WiFiClientFactory = { CWWiFiClient() }) {
        self.clientFactory = clientFactory
        self.client = clientFactory()
    }

    func start(delegate: any CWEventDelegate, events: [CWEventType]) {
        configure(delegate: delegate, events: events)
    }

    func restart(delegate: any CWEventDelegate, events: [CWEventType]) {
        clear()
        client = clientFactory()
        configure(delegate: delegate, events: events)
    }

    func stop() {
        clear()
    }

    private func configure(delegate: any CWEventDelegate, events: [CWEventType]) {
        client.delegate = delegate
        for event in events {
            do {
                try client.startMonitoringEvent(with: event)
            } catch {
                wifiMonitorLogger.error(
                    "Failed to register CoreWLAN event \(event.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func clear() {
        client.delegate = nil
        do {
            try client.stopMonitoringAllEvents()
        } catch {
            wifiMonitorLogger.error(
                "Failed to clear CoreWLAN events: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

/// `com.apple.nat` is an undocumented dynamic-store key used only as a
/// best-effort signal. Missing or unreadable data returns `nil`, which means
/// "not definitively sharing" and never assumes sharing is active.
final class SystemInternetSharingDetector: InternetSharingDetecting {
    func isActive() -> Bool? {
        guard
            let store = SCDynamicStoreCreate(
                nil,
                "StatusTrio" as CFString,
                nil,
                nil
            ),
            let value = SCDynamicStoreCopyValue(
                store,
                "com.apple.nat" as CFString
            ) as? [String: Any],
            let nat = value["NAT"] as? [String: Any]
        else { return nil }

        return booleanValue(nat["Enabled"])
    }

    private func booleanValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        if let value = value as? Int {
            return value == 1
        }
        return nil
    }
}

@MainActor
final class WiFiMonitor: NSObject, WiFiMonitoring, CWEventDelegate {
    private enum Lifecycle {
        case idle
        case running
        case stopped
    }

    let updates: AsyncStream<WiFiStatus>

    private static let monitoredEvents: [CWEventType] = [
        .powerDidChange,
        .ssidDidChange,
        .bssidDidChange,
        .linkDidChange,
        .linkQualityDidChange,
        .modeDidChange
    ]

    private let continuation: AsyncStream<WiFiStatus>.Continuation
    private let statusReader: any WiFiStatusReadingProviding
    private let nameAuthorizer: any WiFiNameAuthorizing
    nonisolated(unsafe) private let eventMonitor: any WiFiEventMonitoring
    private let staleInterval: TimeInterval
    private let now: () -> Date
    private let refreshDebounceInterval: Duration
    private let refreshDebounceSleep: @Sendable (Duration) async throws -> Void
    private var scheduledRefreshTask: Task<Void, Never>?
    private var detailsVisible = true
    private let keepsNameAvailable: Bool
    private var readInFlight = false
    private var refreshPending = false
    private var readGeneration: UInt64 = 0
    private var readToken: UInt64 = 0
    private let readWatchdog: ReadWatchdog

    private var latestPath: NetworkPathSnapshot?
    private var lastValidStatus: WiFiStatus?
    private var lastValidDate: Date?
    private var lastRecoveryAttempt: Date?
    private var isPersistentReadFailure = false
    /// Rebuilds performed while reads reported no interface at all, which is what
    /// a Mac without Wi-Fi hardware returns on every read. Rebuilding the CoreWLAN
    /// event stack for those is pure waste, so the rebuilds are bounded. Reads the
    /// stale-interval gate suppresses do not count; any read that reports an
    /// interface, and `recover()`, reset it.
    private(set) var interfaceAbsentStreak = 0
    private let noInterfaceRecoveryLimit: Int
    private var lifecycle = Lifecycle.idle

    init(
        statusReader: any WiFiStatusReadingProviding = CoreWLANStatusReader(),
        nameAuthorizer: any WiFiNameAuthorizing = CoreLocationWiFiNameAuthorizer(),
        eventMonitor: any WiFiEventMonitoring = CoreWLANWiFiEventMonitor(),
        keepsNameAvailable: Bool = false,
        staleInterval: TimeInterval = 30,
        initialPath: NetworkPathSnapshot? = nil,
        now: @escaping () -> Date = Date.init,
        refreshDebounceInterval: Duration = .milliseconds(150),
        refreshDebounceSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        noInterfaceRecoveryLimit: Int = 3,
        readTimeout: Duration = .seconds(5),
        readTimeoutSleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.statusReader = statusReader
        self.nameAuthorizer = nameAuthorizer
        self.eventMonitor = eventMonitor
        self.keepsNameAvailable = keepsNameAvailable
        self.staleInterval = staleInterval
        self.latestPath = initialPath
        self.now = now
        self.refreshDebounceInterval = refreshDebounceInterval
        self.refreshDebounceSleep = refreshDebounceSleep
        self.noInterfaceRecoveryLimit = noInterfaceRecoveryLimit
        readWatchdog = ReadWatchdog(
            baseTimeout: readTimeout,
            maxTimeout: .seconds(60),
            sleep: readTimeoutSleep
        )
        (updates, continuation) = MonitorStream.make(of: WiFiStatus.self)
        super.init()
        nameAuthorizer.onAccessChange = { [weak self] in
            self?.readGeneration &+= 1
            self?.refresh()
        }
    }

    deinit {
        scheduledRefreshTask?.cancel()
        if lifecycle != .stopped {
            eventMonitor.stop()
            continuation.finish()
        }
    }

    func start() {
        guard lifecycle == .idle else { return }
        lifecycle = .running

        eventMonitor.start(delegate: self, events: Self.monitoredEvents)
        refresh()
    }

    /// External triggers (a wake, an explicit `recover()`) start a fresh budget;
    /// the internal retry path is the one that is bounded.
    func recover() {
        guard lifecycle == .running else { return }
        interfaceAbsentStreak = 0
        restartMonitoring()
    }

    @discardableResult
    func requestNameAccess() -> WiFiNameAccessRequestResult {
        guard lifecycle == .running else { return .notNeeded }
        let result = nameAuthorizer.requestAccess()
        if result == .notNeeded {
            // The displayed permission state may lag behind a grant in Settings.
            readGeneration &+= 1
            refresh()
        }
        return result
    }

    func setDetailsVisible(_ visible: Bool) {
        guard lifecycle != .stopped else { return }
        let changed = detailsVisible != visible
        detailsVisible = visible
        if changed { readGeneration &+= 1 }
        if changed, !visible, lifecycle == .running {
            refresh()
        }
    }

    func updateNetworkPath(_ path: NetworkPathSnapshot) {
        guard lifecycle != .stopped, path != latestPath else { return }
        latestPath = path
        scheduleRefresh()
    }

    func stop() {
        guard lifecycle != .stopped else { return }
        lifecycle = .stopped
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = nil
        readWatchdog.cancel()
        teardown()
    }

    func refresh() {
        guard lifecycle != .stopped else { return }
        // Coalesce event bursts and polling while a slow system service replies.
        // At most one read and one follow-up are retained, regardless of latency.
        guard !readInFlight else {
            refreshPending = true
            return
        }
        readInFlight = true
        readToken &+= 1
        let token = readToken
        let generation = readGeneration
        readWatchdog.arm { [weak self] in
            self?.abandonTimedOutRead(token: token)
        }
        statusReader.read(includeSSID: detailsVisible || keepsNameAvailable) { [weak self] result in
            // A completion that arrives after the read was declared stuck must not
            // release the latch of the read that replaced it.
            guard let self, token == self.readToken else { return }
            self.readWatchdog.cancel()
            guard self.lifecycle != .stopped else { return }
            self.readWatchdog.recordSuccess()
            self.readInFlight = false
            let needsRefresh = self.refreshPending || generation != self.readGeneration
            self.refreshPending = false
            // Visibility, permission and wake/recovery changes invalidate old reads.
            if generation == self.readGeneration {
                self.receive(result)
            }
            // A debounced event already owns the follow-up. Starting it now would
            // let that timer enqueue another read while this follow-up is in flight.
            if needsRefresh, self.scheduledRefreshTask == nil { self.refresh() }
        }
    }

    /// A system read never returned. Ignore its late completion, release the
    /// single-read latch so the monitor is not stuck forever, and try again so a
    /// transient stall can recover. The reader moves the retry to a fresh queue.
    private func abandonTimedOutRead(token: UInt64) {
        guard token == readToken else { return }
        readToken &+= 1
        readInFlight = false
        readGeneration &+= 1
        refresh()
    }

    private func receive(_ result: WiFiStatusReading) {
        guard let reading = result.interface else {
            publish(.unavailable, rssi: nil, ssid: nil, nameAccess: nameAuthorizer.access)
            return
        }

        interfaceAbsentStreak = 0
        lastRecoveryAttempt = nil
        isPersistentReadFailure = false

        let input = WiFiClassificationInput(
            powerOn: reading.powerOn,
            serviceActive: reading.serviceActive,
            mode: reading.mode,
            pathSatisfied: latestPath?.connected,
            pathUsesWiFi: latestPath?.wireless ?? false,
            pathExpensive: latestPath?.expensive == true && latestPath?.constrained == false,
            sharingActive: result.sharingActive
        )
        let nameAccess = nameAuthorizer.access
        let state = WiFiClassifier.classify(input)
        publish(
            state,
            rssi: normalizedRSSI(reading.rssi),
            ssid: (detailsVisible || keepsNameAvailable) && nameAccess == .authorized ? normalizedSSID(reading.ssid) : nil,
            nameAccess: nameAccess,
            band: detailsVisible && (state == .connected || state == .hotspot) ? reading.band : nil
        )
    }

    nonisolated func clientConnectionInterrupted() {
        Task { @MainActor [weak self] in
            guard let self, self.lifecycle == .running else { return }
            self.scheduleRefresh()
        }
    }

    nonisolated func clientConnectionInvalidated() {
        Task { @MainActor [weak self] in
            guard let self, self.lifecycle == .running else { return }
            self.recover()
            self.scheduleRefresh()
        }
    }

    nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.scheduleRefresh()
        }
    }

    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.scheduleRefresh()
        }
    }

    nonisolated func bssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.scheduleRefresh()
        }
    }

    nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.scheduleRefresh()
        }
    }

    nonisolated func linkQualityDidChangeForWiFiInterface(
        withName interfaceName: String,
        rssi: Int,
        transmitRate: Double
    ) {
        Task { @MainActor [weak self] in
            self?.scheduleRefresh()
        }
    }

    nonisolated func modeDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor [weak self] in
            self?.scheduleRefresh()
        }
    }

    private func scheduleRefresh() {
        guard lifecycle == .running, scheduledRefreshTask == nil else { return }

        let interval = refreshDebounceInterval
        let sleep = refreshDebounceSleep
        scheduledRefreshTask = Task { @MainActor [weak self] in
            do {
                try await sleep(interval)
            } catch {
                self?.scheduledRefreshTask = nil
                return
            }

            guard !Task.isCancelled, let self, self.lifecycle == .running else {
                self?.scheduledRefreshTask = nil
                return
            }

            self.scheduledRefreshTask = nil
            self.refresh()
        }
    }

    private func teardown() {
        eventMonitor.stop()
        latestPath = nil
        lastValidStatus = nil
        lastValidDate = nil
        lastRecoveryAttempt = nil
        isPersistentReadFailure = false
        continuation.finish()
    }

    private func publish(
        _ state: WiFiState,
        rssi: Int?,
        ssid: String?,
        nameAccess: WiFiNameAccess,
        band: WiFiFrequencyBand? = nil
    ) {
        let candidate = WiFiStatus(
            state: state,
            rssi: rssi,
            ssid: ssid,
            nameAccess: nameAccess,
            band: band
        )

        if state == .unavailable {
            let currentDate = now()
            if
                let lastValidStatus,
                let lastValidDate,
                currentDate.timeIntervalSince(lastValidDate) <= staleInterval
            {
                continuation.yield(WiFiStatus(
                    state: lastValidStatus.state,
                    rssi: lastValidStatus.rssi,
                    ssid: (detailsVisible || keepsNameAvailable) && nameAccess == .authorized ? lastValidStatus.ssid : nil,
                    nameAccess: nameAccess
                ))
                return
            }

            let shouldAttemptRecovery = lastValidStatus != nil || isPersistentReadFailure
            isPersistentReadFailure = true
            if shouldAttemptRecovery {
                recoverIfAllowed(at: currentDate)
            }

            lastValidStatus = nil
            lastValidDate = nil
            continuation.yield(candidate)
            return
        }

        isPersistentReadFailure = false
        lastValidStatus = candidate
        lastValidDate = now()
        continuation.yield(candidate)
    }

    private func recoverIfAllowed(at date: Date) {
        // Bound the rebuilds, not the reads: the streak is counted only for absent
        // reads that reach the far side of the stale-interval gate and actually
        // rebuild, so gated reads cost nothing and the budget stays
        // `noInterfaceRecoveryLimit` rebuilds whatever the read cadence. The gate
        // also absorbs the fix-up read a rebuild triggers, so a rebuild can never
        // re-trigger itself.
        guard interfaceAbsentStreak < noInterfaceRecoveryLimit else { return }
        if
            let lastRecoveryAttempt,
            date.timeIntervalSince(lastRecoveryAttempt) < staleInterval
        {
            return
        }

        interfaceAbsentStreak += 1
        restartMonitoring()
    }

    private func restartMonitoring() {
        readGeneration &+= 1
        lastRecoveryAttempt = now()
        eventMonitor.restart(delegate: self, events: Self.monitoredEvents)
        scheduleRefresh()
    }

    private func normalizedRSSI(_ rssi: Int?) -> Int? {
        guard let rssi, rssi < 0 else { return nil }
        return rssi
    }

    private func normalizedSSID(_ ssid: String?) -> String? {
        guard let ssid else { return nil }
        let value = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
