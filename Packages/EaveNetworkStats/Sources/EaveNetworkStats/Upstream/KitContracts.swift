//
//  widget.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 10/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

public enum widget_t: String {
    case unknown = ""
    case mini = "mini"
    case lineChart = "line_chart"
    case barChart = "bar_chart"
    case pieChart = "pie_chart"
    case networkChart = "network_chart"
    case speed = "speed"
    case battery = "battery"
    case batteryDetails = "battery_details"
    case stack = "sensors" // to replace
    case memory = "memory"
    case label = "label"
    case tachometer = "tachometer"
    case state = "state"
    case text = "text"
    case icon = "icon"
    
}

public protocol Settings_v: NSView {
    func load(widgets: [widget_t])
}

open class PreviewWrapper: NSStackView {
    public let module: ModuleType
    
    public init(type: ModuleType) {
        self.module = type
        super.init(frame: NSRect.zero)
        
        self.orientation = .vertical
        self.distribution = .gravityAreas
        self.translatesAutoresizingMaskIntoConstraints = false
        self.spacing = Constants.Settings.margin
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

