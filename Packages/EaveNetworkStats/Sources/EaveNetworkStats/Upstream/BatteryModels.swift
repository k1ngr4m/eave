//
//  main.swift
//  Battery
//
//  Created by Serhiy Mytrovtsiy on 06/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import IOKit
import IOKit.ps
import IOKit.ps

struct Battery_Usage: Codable {
    var powerSource: String = ""
    var state: String? = nil
    var isCharged: Bool = false
    var isCharging: Bool = false
    var isBatteryPowered: Bool = false
    var optimizedChargingEngaged: Bool = false
    var level: Double = 0
    var cycles: Int = 0
    var health: Int = 0
    
    var designedCapacity: Int = 0
    var maxCapacity: Int = 0
    var currentCapacity: Int = 0
    
    var current: Int = 0
    var voltage: Double = 0
    var temperature: Double? = nil
    var batteryPower: Double = 0
    
    var ACwatts: Int = 0
    var chargingCurrent: Int = 0
    var chargingVoltage: Int = 0
    var adapterPower: Double = 0
    var adapterVoltage: Double = 0
    
    var timeToEmpty: Int = 0
    var timeToCharge: Int = 0
    var timeOnACPower: Date? = nil
    
    var ups: UPS_Usage? = nil
}

struct UPS_Usage: Codable {
    var name: String = ""
    var powerSource: String = ""
    var isBatteryPowered: Bool = false
    var isCharged: Bool = false
    var isCharging: Bool = false
    var level: Double = 0
}


