import Foundation

enum MonitoringModule: String, CaseIterable, Identifiable, Sendable {
    case cpu, memory, gpu, disk, network, sensors
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return String(localized: "Memory")
        case .gpu: return "GPU"
        case .disk: return String(localized: "Disk")
        case .network: return String(localized: "Network")
        case .sensors: return String(localized: "Sensors")
        }
    }
    var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .gpu: return "display"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .sensors: return "thermometer.medium"
        }
    }
    var unit: MonitoringUnit {
        switch self {
        case .cpu, .memory, .gpu: return .percent
        case .disk, .network: return .rate
        case .sensors: return .temperature
        }
    }
}

enum MonitoringUnit: Sendable {
    case percent, bytes, rate, temperature, voltage, current, power, fan, frequency, number
    func string(_ value: Double?, fahrenheit: Bool = false) -> String {
        guard let value, value.isFinite else { return "—" }
        switch self {
        case .percent: return String(format: "%.1f%%", value)
        case .bytes: return ByteCountFormatter.string(fromByteCount: Int64(max(0, min(value, Double(Int64.max / 2)))), countStyle: .memory)
        case .rate: return MonitoringUnit.bytes.string(value) + "/s"
        case .temperature: return String(format: "%.1f°%@", fahrenheit ? value * 1.8 + 32 : value, fahrenheit ? "F" : "C")
        case .voltage: return String(format: "%.2f V", value)
        case .current: return String(format: "%.2f A", value)
        case .power: return String(format: "%.2f W", value)
        case .fan: return String(format: "%.0f RPM", value)
        case .frequency: return String(format: "%.2f GHz", value)
        case .number: return String(format: "%.2f", value)
        }
    }
}

struct MonitoringRow: Identifiable, Sendable {
    var id: String
    var label: String
    var value: Double?
    var unit: MonitoringUnit
    var text: String? = nil
    init(_ label: String, _ value: Double?, _ unit: MonitoringUnit, id: String? = nil) {
        self.id = id ?? label; self.label = label; self.value = value; self.unit = unit
    }
    init(_ label: String, text: String, id: String? = nil) {
        self.init(label, nil, .number, id: id); self.text = text
    }
}

struct MonitoringSection: Identifiable, Sendable {
    var id: String
    var title: String
    var rows: [MonitoringRow]
    init(_ title: String, rows: [MonitoringRow], id: String? = nil) {
        self.id = id ?? title; self.title = title; self.rows = rows
    }
}

struct MonitoringSample: Sendable {
    var value: Double? = nil
    var secondary: Double? = nil
    var sections: [MonitoringSection] = []
    var processes: [MonitoringRow] = []
    var processStatus: String? = nil
}

struct MonitoringPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double?
    let secondary: Double?
}

// Counters are sampled per device/process so removal, reset and first reads never spike.
struct MonitoringCounter {
    private var previous: [String: (UInt64, UInt64)] = [:]
    private var timestamp: TimeInterval?
    mutating func rates(_ counters: [String: (UInt64, UInt64)], at time: TimeInterval) -> [String: (Double, Double)] {
        defer { previous = counters; timestamp = time }
        guard let timestamp, time > timestamp else { return [:] }
        let elapsed = time - timestamp
        var result: [String: (Double, Double)] = [:]
        for (key, current) in counters {
            guard let old = previous[key] else { continue }
            result[key] = (Self.delta(current.0, old.0) / elapsed, Self.delta(current.1, old.1) / elapsed)
        }
        return result
    }
    static func delta(_ current: UInt64, _ previous: UInt64) -> Double {
        current >= previous ? Double(current - previous) : 0
    }
}

enum MonitoringParsing {
    static func cpuTicks(_ current: [UInt32], previous: [UInt32]) -> (user: Double, system: Double, idle: Double)? {
        guard current.count == 4, previous.count == 4 else { return nil }
        let delta = zip(current, previous).map { Double($0 &- $1) }
        let total = delta.reduce(0, +)
        guard total > 0 else { return nil }
        return ((delta[0] + delta[3]) / total * 100, delta[1] / total * 100, delta[2] / total * 100)
    }
    static func memoryProcess(_ line: String) -> MonitoringRow? {
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 3, let pid = Int32(parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "*"))), pid > 0 else { return nil }
        var raw = String(parts.last!)
        while raw.last == "+" || raw.last == "-" { raw.removeLast() }
        let scales: [Character: Double] = ["B": 1, "K": 1024, "M": 1048576, "G": 1073741824, "T": 1099511627776]
        let scale = raw.last.flatMap { scales[$0] } ?? 1
        let number = raw.last.flatMap { scales[$0] } == nil ? raw : String(raw.dropLast())
        guard let value = Double(number), value.isFinite, value >= 0 else { return nil }
        return MonitoringRow(parts.dropFirst().dropLast().filter { $0 != "*" }.joined(separator: " "), value * scale, .bytes, id: String(pid))
    }
}

enum MonitoringActivity {
    static func shouldRun(enabled: Bool, hasModules: Bool, sleeping: Bool, notchIsOpen: Bool,
                          statsSelected: Bool, stopWhenClosed: Bool) -> Bool {
        enabled && hasModules && !sleeping && statsSelected && (notchIsOpen || !stopWhenClosed)
    }
}
