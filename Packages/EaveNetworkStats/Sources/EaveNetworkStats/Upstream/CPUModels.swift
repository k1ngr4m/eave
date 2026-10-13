//
//  main.swift
//  CPU
//
//  Created by Serhiy Mytrovtsiy on 09/04/2020.
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import IOKit

public struct CPU_Load: Codable {
    public var totalUsage: Double = 0
    var usagePerCore: [Double] = []
    var usageECores: Double? = nil
    var usagePCores: Double? = nil
    var usageSCores: Double? = nil

    var systemLoad: Double = 0
    var userLoad: Double = 0
    var idleLoad: Double = 0

    public func remote() -> Data? {
        var string = "1,1,\(self.totalUsage),\(self.usagePerCore.count),"
        for c in self.usagePerCore {
            string += "\(c),"
        }
        string += "$"
        return string.data(using: .utf8)
    }
}

public struct CPU_Frequency: Codable {
    var value: Double? = nil
    var eCore: Double? = nil
    var pCore: Double? = nil
    var sCore: Double? = nil
}

public struct CPU_Limit: Codable {
    var scheduler: Int = 0
    var cpus: Int = 0
    var speed: Int = 0
}

public struct CPU_AverageLoad: Codable {
    var load1: Double = 0
    var load5: Double = 0
    var load15: Double = 0

    public func remote() -> Data? {
        let string = "1,1,\(self.load1),\(self.load5),\(self.load15)$"
        return string.data(using: .utf8)
    }
}
