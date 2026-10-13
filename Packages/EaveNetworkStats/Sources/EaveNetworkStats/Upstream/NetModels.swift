//
//  main.swift
//  Net
//
//  Created by Serhiy Mytrovtsiy on 24/05/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import SystemConfiguration

public enum Network_t: String, Codable {
    case wifi
    case ethernet
    case bluetooth
    case other
}

public struct Network_interface: Codable {
    var status: Bool = false
    var displayName: String = ""
    var BSDName: String = ""
    var address: String = ""
    var transmitRate: Double = 0
}

public struct Network_addr: Codable {
    var v4: String? = nil
    var v6: String? = nil
    var countryCode: String? = nil
}

public struct Network_wifi: Codable {
    var countryCode: String? = nil
    var ssid: String? = nil
    var bssid: String? = nil
    var RSSI: Int? = nil
    var noise: Int? = nil
    
    var standard: String? = nil
    var mode: String? = nil
    var security: String? = nil
    var channel: String? = nil
    
    var channelBand: String? = nil
    var channelWidth: String? = nil
    var channelNumber: String? = nil
    
    mutating func reset() {
        self.countryCode = nil
        self.ssid = nil
        self.bssid = nil
        self.RSSI = nil
        self.noise = nil
        self.standard = nil
        self.mode = nil
        self.security = nil
        self.channel = nil
        self.channelBand = nil
        self.channelWidth = nil
        self.channelNumber = nil
    }
}

public struct Bandwidth: Codable {
    var upload: Int64 = 0
    var download: Int64 = 0
}

enum WiFiLocationAuthorization: String, Codable {
    case notDetermined, denied, authorized
}

public struct Network_Usage: Codable {
    var bandwidth: Bandwidth = Bandwidth()
    var total: Bandwidth = Bandwidth()
    
    var laddr: Network_addr = Network_addr() // local ip
    var raddr: Network_addr = Network_addr() // remote ip
    
    var dns: [String] = []
    
    var interface: Network_interface? = nil
    var connectionType: Network_t? = nil
    var status: Bool = false
    
    var wifiDetails: Network_wifi = Network_wifi()
    var wifiLocationAuthorization: WiFiLocationAuthorization?
    
    mutating func reset() {
        self.bandwidth = Bandwidth()
        
        self.laddr = Network_addr()
        self.raddr = Network_addr()
        
        self.dns = []
        
        self.interface = nil
        self.connectionType = nil
        
        self.wifiDetails.reset()
    }
    
    public func remote() -> Data? {
        let addr = "\(self.laddr.v4 ?? ""),\(self.laddr.v6 ?? ""),\(self.raddr.v4 ?? ""),\(self.raddr.v6 ?? "")"
        let string = "1,\(self.interface?.BSDName ?? ""),1,\(self.bandwidth.download),\(self.bandwidth.upload),\(addr)$"
        return string.data(using: .utf8)
    }
}

public struct Network_Connectivity: Codable {
    var status: Bool = false
    var latency: Double = 0
    var jitter: Double = 0
}

public struct Network_Process: Codable, Process_p {
    public var pid: Int
    public var name: String
    public var time: Date
    public var download: Int
    public var upload: Int
    public var icon: NSImage {
        get { ProcessIconCache.shared.icon(for: self.pid) }
    }
    
    public init(pid: Int = 0, name: String = "", time: Date = Date(), download: Int = 0, upload: Int = 0) {
        self.pid = pid
        self.name = name
        self.time = time
        self.download = download
        self.upload = upload
    }
}

