//
//  store.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 10/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

public class Store {
    static var shared = Store()
    let defaults: UserDefaults
    private var cache: [String: Any] = [:]
    private let cacheQueue = DispatchQueue(label: "eu.exelban.Stats.Store.cache", attributes: .concurrent)
    
    init(defaults: UserDefaults = UserDefaults(suiteName: "app.eave.network-monitoring")!) {
        self.defaults = defaults
        self.loadCache()
    }
    
    private func loadCache() {
        self.cache = self.defaults.dictionaryRepresentation()
    }
    
    private func getValue<T>(for key: String, type: T.Type) -> T? {
        return self.cacheQueue.sync {
            return self.cache[key] as? T
        }
    }
    
    private func setValue(_ value: Any?, for key: String) {
        defer {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .networkPreferencesChanged, object: self, userInfo: ["key": key])
            }
        }
        self.cacheQueue.async(flags: .barrier) {
            self.cache[key] = value
        }
        
        if let value = value {
            self.defaults.set(value, forKey: key)
        } else {
            self.defaults.removeObject(forKey: key)
        }
    }
    
    public func exist(key: String) -> Bool {
        return self.cacheQueue.sync {
            self.cache.keys.contains(key) || self.defaults.object(forKey: key) != nil
        }
    }
    
    public func remove(_ key: String) {
        self.setValue(nil, for: key)
    }
    
    public func bool(key: String, defaultValue value: Bool) -> Bool {
        return self.getValue(for: key, type: Bool.self) ?? value
    }
    
    public func string(key: String, defaultValue value: String) -> String {
        return self.getValue(for: key, type: String.self) ?? value
    }
    
    public func int(key: String, defaultValue value: Int) -> Int {
        return self.getValue(for: key, type: Int.self) ?? value
    }
    
    public func array(key: String, defaultValue value: [Any]) -> [Any] {
        return self.getValue(for: key, type: [Any].self) ?? value
    }
    
    public func data(key: String) -> Data? {
        return self.getValue(for: key, type: Data.self)
    }
    
    public func set(key: String, value: Bool) {
        self.setValue(value, for: key)
    }
    
    public func set(key: String, value: String) {
        self.setValue(value, for: key)
    }
    
    public func set(key: String, value: Int) {
        self.setValue(value, for: key)
    }
    
    public func set(key: String, value: Data) {
        self.setValue(value, for: key)
    }
    
    public func set(key: String, value: [Any]) {
        self.setValue(value, for: key)
    }
    
}
