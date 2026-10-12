/// The same network reading drives the menu bar and Eave's connectivity HUD.
public struct MenuBarNetworkState: Equatable, Sendable {
    public enum Connection: Equatable, Sendable {
        case unknown, offline, wifi, ethernet, other
    }

    public let connection: Connection
    public let wifiName: String?
    public let isHotspot: Bool
    public let isConstrained: Bool

    public init(connection: Connection, wifiName: String? = nil,
                isHotspot: Bool = false, isConstrained: Bool = false) {
        self.connection = connection
        self.wifiName = wifiName
        self.isHotspot = isHotspot
        self.isConstrained = isConstrained
    }

    public var isConnected: Bool {
        connection != .unknown && connection != .offline
    }

    public var usesWiFi: Bool { connection == .wifi }

    init(path: NetworkPathSnapshot?, wifi: WiFiStatus) {
        guard let path else {
            self.init(connection: .unknown)
            return
        }
        let connection: Connection
        switch path.connection {
        case .unknown: connection = .unknown
        case .offline: connection = .offline
        case .wifi: connection = .wifi
        case .ethernet: connection = .ethernet
        case .other: connection = .other
        }
        self.init(
            connection: connection,
            wifiName: connection == .wifi && wifi.state.isNetworkAssociated ? wifi.ssid : nil,
            isHotspot: connection == .wifi && path.expensive && !path.constrained,
            isConstrained: path.constrained
        )
    }
}
