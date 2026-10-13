import Foundation

/// Stats Reader's latest-value persistence, isolated from Stats and Eave's other preferences.
final class DB {
    static let shared = DB()
    private let queue = DispatchQueue(label: "app.eave.network.snapshots")
    private var values: [String: Codable] = [:]
    private var writeDates: [String: Date] = [:]

    func setup<T: Codable>(_ type: T.Type, _ key: String) {
        guard let data = Store.shared.defaults.data(forKey: "snapshot." + key),
              let value = try? JSONDecoder().decode(type, from: data) else { return }
        queue.sync { values[key] = value }
    }
    func findOne<T: Decodable>(_ type: T.Type, key: String) -> T? {
        queue.sync { values[key] as? T }
    }
    func insert(key: String, value: Codable, ts: Bool = false, force: Bool = false) {
        queue.sync {
            values[key] = value
            let now = Date()
            if !force, let last = writeDates[key], now.timeIntervalSince(last) < 30 { return }
            guard let data = try? JSONEncoder().encode(value) else { return }
            Store.shared.defaults.set(data, forKey: "snapshot." + key)
            writeDates[key] = now
        }
    }
}
