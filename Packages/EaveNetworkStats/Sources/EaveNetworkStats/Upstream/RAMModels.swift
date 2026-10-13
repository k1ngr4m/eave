//
//  main.swift
//  Memory
//
//  Created by Serhiy Mytrovtsiy on 12/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import IOKit

public struct RAM_Usage: Codable {
    var total: Double
    var used: Double
    var free: Double

    var active: Double
    var inactive: Double
    var wired: Double
    var compressed: Double

    var app: Double
    var cache: Double

    var swap: Swap
    var pressure: Pressure

    var swapins: Int64
    var swapouts: Int64

    public var usage: Double {
        get { self.total > 0 ? min(1, max(0, (self.total - self.free) / self.total)) : 0 }
    }

    public func remote() -> Data? {
        let string = "\(self.total),\(self.used),\(self.pressure.level),\(self.swap.used)$"
        return string.data(using: .utf8)
    }
}

public struct Swap: Codable {
    var total: Double
    var used: Double
    var free: Double
}

public struct Pressure: Codable {
    let level: Int
    let value: RAMPressure
}
