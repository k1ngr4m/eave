import AppKit
import WebKit

@main
struct DesktopPingRegression {
    @MainActor static func main() {
        var config = DesktopPingConfiguration()
        assert(!config.enabled && !config.paused)
        assert(config.helperCommand["emoteTrigger"] as? String == "off")
        assert(config.helperCommand["enabled"] as? Bool == false)
        config.enabled = true
        assert(config.helperCommand["enabled"] as? Bool == true)
        config.paused = true
        assert(config.helperCommand["enabled"] as? Bool == false)
        config.place("push", at: 0)
        assert(config.wheel[0] == "push" && config.wheel[1] == "danger")
        config.place("bait", at: 7)
        assert(config.wheel[7] == "bait" && Set(config.wheel).count == 8)
        config.wheel = ["bad"]
        config.size = .nan; config.volume = 999; config.duration = -1; config.clickPingID = "bad"
        let clean = config.normalized
        assert(clean.wheel == DesktopPingConfiguration.defaultWheel && clean.size == 110)
        assert(clean.volume == 100 && clean.duration == 1 && clean.clickPingID == "generic")
        assert((try! JSONDecoder().decode(DesktopPingConfiguration.self, from: JSONEncoder().encode(clean))) == clean)
        let point = DesktopPingConfiguration.localPoint(CGPoint(x: -1800, y: -300), screen: CGRect(x: -1920, y: 1080, width: 1920, height: 1080), primaryHeight: 1080)
        assert(point == CGPoint(x: 120, y: 780))
        let resourceRoot = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Support/DesktopPing/web")
        for name in DesktopPingConfiguration.sounds {
            assert(NSSound(contentsOf: resourceRoot.appendingPathComponent("sounds/\(name).wav"), byReference: false) != nil, name)
        }
        print("Configuration, pause, wheel swaps, persistence, sound decoding and secondary-screen coordinates passed.")
        guard CommandLine.arguments.contains("--ui") else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Support/DesktopPing/web")
        let overlay = DesktopPingOverlay(screen: NSScreen.screens[0], root: root)
        var sounds: [String] = []
        overlay.onSound = { sounds.append($0) }
        overlay.onFailure = { message in fatalError(message) }
        overlay.onReady = {
            Task { @MainActor in
                do {
                    overlay.send("settings", DesktopPingConfiguration().overlaySettings)
                    overlay.send("wheelOpen", ["x": 500, "y": 400])
                    overlay.send("wheelMove", ["x": 500, "y": 260])
                    try await Task.sleep(for: .milliseconds(200))
                    let wheel = try await overlay.webView.evaluateJavaScript("document.querySelector('#wheel').classList.contains('open') && getComputedStyle(document.querySelector('#wheel .icon.hot')).filter === 'none'") as? Bool
                    assert(wheel == true)
                    overlay.send("wheelRelease", ["x": 500, "y": 260])
                    try await Task.sleep(for: .milliseconds(200))
                    assert(sounds.contains("SRP_12"))
                    let ping = try await overlay.webView.evaluateJavaScript("document.querySelectorAll('.ping').length === 1 && !document.querySelector('#wheel').classList.contains('open')") as? Bool
                    assert(ping == true)
                    overlay.send("clear")
                    try await Task.sleep(for: .milliseconds(100))
                    let cleared = try await overlay.webView.evaluateJavaScript("document.querySelectorAll('.ping').length") as? Int
                    assert(cleared == 0)
                    overlay.send("wheelOpen", ["x": 500, "y": 400])
                    overlay.send("wheelMove", ["x": 640, "y": 400])
                    overlay.send("click", ["id": "assist", "x": 800, "y": 400])
                    try await Task.sleep(for: .milliseconds(300))
                    let snapshot = try await overlay.webView.takeSnapshot(configuration: nil)
                    if let tiff = snapshot.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(".build/desktop-ping/overlay.png"))
                    }
                    overlay.send("cancel")
                    try await Task.sleep(for: .milliseconds(100))
                    let closed = try await overlay.webView.evaluateJavaScript("!document.querySelector('#wheel').classList.contains('open')") as? Bool
                    assert(closed == true)
                    assert(overlay.panel.ignoresMouseEvents && overlay.panel.sharingType == .readOnly)
                    overlay.close()
                    print("Real WebKit resource loading, wheel selection, sound messages, clear/cancel and snapshot passed.")
                    exit(0)
                } catch { fatalError(error.localizedDescription) }
            }
        }
        Task { try? await Task.sleep(for: .seconds(20)); fatalError("Overlay timed out") }
        app.run()
    }
}
