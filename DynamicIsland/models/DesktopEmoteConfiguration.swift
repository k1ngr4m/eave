import Foundation

struct DesktopEmoteConfiguration: Codable, Equatable {
    struct Custom: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let animation: String?
        var valid: Bool {
            id.range(of: "^c:[0-9a-f]{32}$", options: .regularExpression) != nil
                && (animation == nil || animation == "gif" || animation == "webp")
        }
        var icon: String { "eave-ping://custom/\(id.dropFirst(2)).png" }
        var art: String { "eave-ping://custom/\(id.dropFirst(2)).\(animation ?? "png")" }
    }

    var enabled = false
    var trigger: DesktopPingConfiguration.Trigger = .ctrl
    var click = false
    var center = "facepalm"
    var wheel = DesktopEmote.defaultWheel
    var size = 150.0
    var sound = true
    var custom: [Custom] = []

    func contains(_ id: String) -> Bool { DesktopEmote.ids.contains(id) || custom.contains { $0.id == id && $0.valid } }

    var normalized: Self {
        var c = self
        var used = Set<String>()
        c.custom = Array(custom.filter { $0.valid && used.insert($0.id).inserted }.prefix(24))
        c.size = size.isFinite ? min(300, max(80, size)) : 150
        if !c.contains(center) { c.center = "facepalm" }
        if wheel.count != 8 || Set(wheel).count != 8 { c.wheel = DesktopEmote.defaultWheel }
        used = Set(c.wheel.filter(c.contains))
        for i in c.wheel.indices where !c.contains(c.wheel[i]) {
            let fallback = DesktopEmote.defaultWheel[i]
            let id = used.contains(fallback) ? DesktopEmote.catalog.first { !used.contains($0.id) }!.id : fallback
            c.wheel[i] = id
            used.insert(id)
        }
        return c
    }

    mutating func place(_ id: String, at slot: Int) {
        guard contains(id) else { return }
        if slot == 8 { center = id; return }
        guard wheel.indices.contains(slot) else { return }
        if let old = wheel.firstIndex(of: id) { wheel.swapAt(slot, old) }
        else { wheel[slot] = id }
    }

    var items: [[String: String]] {
        DesktopEmote.catalog.map { ["id": $0.id, "name": $0.localizedName,
            "icon": "../emotes/\($0.id).png", "art": "../emotes/\($0.id).webp", "sound": "emote:\($0.id)"] }
        + custom.filter(\.valid).map { ["id": $0.id, "name": $0.name, "icon": $0.icon, "art": $0.art] }
    }
}
