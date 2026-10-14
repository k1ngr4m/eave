import Foundation

struct DesktopPingConfiguration: Codable, Equatable {
    enum Trigger: String, Codable, CaseIterable {
        case alt, ctrl, shift, win, mouse4, mouse5
        var label: String {
            switch self {
            case .alt: return "⌥ Option"
            case .ctrl: return "⌃ Control"
            case .shift: return "⇧ Shift"
            case .win: return "⌘ Command"
            case .mouse4: return String(localized: "Mouse Button 4")
            case .mouse5: return String(localized: "Mouse Button 5")
            }
        }
    }

    static let defaultWheel = ["danger", "push", "omw", "allin", "assist", "needvision", "missing", "enemyvision"]
    static let pingIDs = defaultWheel + ["generic", "bait", "visioncleared"]
    static let titles = ["Danger", "Push", "On My Way", "All In", "Assist Me", "Need Vision", "Enemy Missing", "Enemy Vision", "Generic Ping", "Bait", "Vision Cleared"]
    static let icons = ["pingwheel_retreatrender", "push", "omw", "all_in", "assist_me", "need_vision", "enemy_missing", "enemy_vision", "generic_ping", "pingwheel_baitrender", "vision_cleared"]
    static let sounds = ["SRP_12", "SRP_9", "OnMyWay", "SRP_4", "ComeHere", "SRP_7", "MIA", "AreaIsWarded", "Base", "SRP_11", "SRP_6", "button"]

    var enabled = false
    var paused = false
    var trigger: Trigger = .alt
    var clickPing = false
    var clickPingID = "generic"
    var wheel = defaultWheel
    var dragThreshold = 8.0
    var size = 110.0
    var duration = 3.2
    var volume = 70.0
    var muted = false
    var tickSound = true

    var normalized: Self {
        var copy = self
        func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        copy.dragThreshold = clamp(dragThreshold, 2...40, 8)
        copy.size = clamp(size, 60...220, 110)
        copy.duration = clamp(duration, 1...8, 3.2)
        copy.volume = clamp(volume, 0...100, 70)
        if !Self.pingIDs.contains(clickPingID) { copy.clickPingID = "generic" }
        if wheel.count != 8 || Set(wheel).count != 8 || !wheel.allSatisfy(Self.pingIDs.contains) {
            copy.wheel = Self.defaultWheel
        }
        return copy
    }

    mutating func place(_ id: String, at slot: Int) {
        guard Self.pingIDs.contains(id) else { return }
        if slot == 8 { clickPingID = id; return }
        guard wheel.indices.contains(slot) else { return }
        if let old = wheel.firstIndex(of: id) { wheel.swapAt(slot, old) }
        else { wheel[slot] = id }
    }

    var helperCommand: [String: Any] {
        let c = normalized
        return ["type": "config", "trigger": c.trigger.rawValue, "triggerVk": 0,
                "clickPing": c.clickPing, "emoteTrigger": "off", "emoteTriggerVk": 0,
                "emoteClick": false, "gameCheck": false, "dragThresholdPx": Int(c.dragThreshold),
                "toggleMods": 3, "toggleVk": 80, "enabled": c.enabled && !c.paused]
    }

    var overlaySettings: [String: Any] {
        let c = normalized
        return ["wheel": c.wheel, "size": c.size, "duration": c.duration, "tickSound": c.tickSound,
                "wheelLabel": String(localized: "PING"), "cancelLabel": String(localized: "CANCEL")]
    }

    /// CGEvent uses a top-left origin; AppKit screens use the primary screen's bottom-left origin.
    static func localPoint(_ point: CGPoint, screen: CGRect, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x - screen.minX, y: point.y - (primaryHeight - screen.maxY))
    }
}
