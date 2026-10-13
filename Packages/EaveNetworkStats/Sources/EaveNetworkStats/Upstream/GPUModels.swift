//
//  main.swift
//  GPU
//
//  Created by Serhiy Mytrovtsiy on 17/08/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import IOKit

public typealias GPU_type = String
public enum GPU_types: GPU_type {
    case unknown = ""

    case integrated = "i"
    case external = "e"
    case discrete = "d"
}

public struct GPU_Info: Codable {
    public let id: String
    public let type: GPU_type

    public let IOClass: String
    public var vendor: String? = nil
    public let model: String
    public var cores: Int? = nil

    public var state: Bool = true

    public var fanSpeed: Int? = nil
    public var coreClock: Int? = nil
    public var memoryClock: Int? = nil
    public var temperature: Double? = nil
    public var utilization: Double? = nil
    public var renderUtilization: Double? = nil
    public var tilerUtilization: Double? = nil
    public var aneUtilization: Double? = nil
    public var fps: Double? = nil

    init(id: String, type: GPU_type, IOClass: String, vendor: String? = nil, model: String, cores: Int?, utilization: Double? = nil, render: Double? = nil, tiler: Double? = nil) {
        self.id = id
        self.type = type
        self.IOClass = IOClass
        self.vendor = vendor
        self.model = model
        self.cores = cores
        self.utilization = utilization
        self.renderUtilization = render
        self.tilerUtilization = tiler
    }

    public func remote() -> String {
        var id = self.id
        if self.id.isEmpty {
            id = "0"
        }
        return "\(id),1,\(self.utilization ?? 0),\(self.renderUtilization ?? 0),\(self.tilerUtilization ?? 0),,"
    }
}

public class GPUs: Codable {
    private var queue: DispatchQueue = DispatchQueue(label: "eu.exelban.Stats.GPU.SynchronizedArray")

    private var _list: [GPU_Info] = []
    public var list: [GPU_Info] {
        get { self.queue.sync { self._list } }
        set { self.queue.sync { self._list = newValue } }
    }

    enum CodingKeys: String, CodingKey {
        case list
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.list = try container.decode(Array<GPU_Info>.self, forKey: CodingKeys.list)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(list, forKey: .list)
    }

    init() {}

    internal func active() -> [GPU_Info] {
        return self.list.filter{ $0.state && $0.utilization != nil }.sorted{ $0.utilization ?? 0 > $1.utilization ?? 0 }
    }

    public func remote() -> Data? {
        var string = "\(self.list.count),"
        for (i, v) in self.list.enumerated() {
            string += v.remote()
            if i != self.list.count {
                string += ","
            }
        }
        string += "$"
        return string.data(using: .utf8)
    }
}
