import AppKit
import WebKit
import SwiftUI

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
        let beforeCenter = config.wheel
        config.place("danger", at: 8)
        assert(config.clickPingID == "danger" && config.wheel == beforeCenter)
        config.place("invalid", at: 8)
        config.place("bait", at: -1)
        assert(config.clickPingID == "danger" && config.wheel == beforeCenter)
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
        checkEmoteConfiguration(resourceRoot)
        print("Configuration, pause, wheel swaps, persistence, sound decoding and secondary-screen coordinates passed.")
        guard CommandLine.arguments.contains("--ui") else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Support/DesktopPing/web")
        let customDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let custom = try! DesktopEmoteLibrary.importImage(root.appendingPathComponent("emotes/facepalm.webp"), existing: [], directory: customDirectory)
        let overlay = DesktopPingOverlay(screen: NSScreen.screens[0], root: root, customRoot: customDirectory)
        var sounds: [String] = []
        overlay.onSound = { sounds.append($0) }
        overlay.onFailure = { message in fatalError(message) }
        overlay.onReady = {
            Task { @MainActor in
                do {
                    overlay.send("settings", DesktopPingConfiguration().overlaySettings)
                    overlay.send("wheelOpen", ["x": 500, "y": 400])
                    overlay.send("wheelMove", ["x": 500, "y": 260])
                    try await waitFor("document.querySelector('#wheel').classList.contains('open') && document.querySelector('#wheel .icon.hot') !== null && getComputedStyle(document.querySelector('#wheel .icon.hot')).filter === 'none'", in: overlay.webView)
                    overlay.send("wheelRelease", ["x": 500, "y": 260])
                    try await waitFor("document.querySelectorAll('.ping').length === 1 && !document.querySelector('#wheel').classList.contains('open')", in: overlay.webView)
                    assert(sounds.contains("SRP_12"))
                    overlay.send("clear")
                    try await waitFor("document.querySelectorAll('.ping').length === 0", in: overlay.webView)
                    overlay.send("wheelOpen", ["x": 500, "y": 400])
                    overlay.send("wheelMove", ["x": 640, "y": 400])
                    overlay.send("click", ["id": "assist", "x": 800, "y": 400])
                    try await Task.sleep(for: .milliseconds(300))
                    let snapshot = try await overlay.webView.takeSnapshot(configuration: nil)
                    if let tiff = snapshot.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(".build/desktop-ping/overlay.png"))
                    }
                    overlay.send("cancel")
                    try await waitFor("!document.querySelector('#wheel').classList.contains('open')", in: overlay.webView)
                    assert(overlay.panel.ignoresMouseEvents && overlay.panel.sharingType == .readOnly)
                    try await checkEmoteOverlay(overlay, custom: custom, sounds: { sounds })
                    overlay.close()
                    try await checkEditor()
                    try await checkEditor(emotes: false)
                    try FileManager.default.removeItem(at: customDirectory)
                    print("Real WebKit resource loading, wheel selection, sound messages, clear/cancel and snapshot passed.")
                    exit(0)
                } catch { fatalError(error.localizedDescription) }
            }
        }
        Task { try? await Task.sleep(for: .seconds(45)); fatalError("Overlay timed out") }
        app.run()
    }
    @MainActor static func checkEmoteConfiguration(_ root: URL) {
        var original = DesktopPingConfiguration()
        original.place("bait", at: 0)
        let oldJSON = try! JSONEncoder().encode(original)
        assert(!String(data: oldJSON, encoding: .utf8)!.contains("emotes"))
        var c = try! JSONDecoder().decode(DesktopPingConfiguration.self, from: oldJSON)
        assert(c.wheel == original.wheel && !c.emote.enabled)
        c.emote.enabled = true; c.emote.click = true
        assert(c.helperCommand["emoteTrigger"] as? String == "ctrl")
        assert(c.helperCommand["emoteClick"] as? Bool == true)
        c.trigger = .ctrl
        assert(c.helperCommand["emoteTrigger"] as? String == "off")
        c.emote.place("bee_mad", at: 0)
        assert(c.emote.wheel[0] == "bee_mad" && c.emote.wheel[7] == "unworthy_cn")
        c.emote.place("sad_kitten", at: 8)
        assert(c.emote.center == "sad_kitten")
        c.emote.size = .infinity
        assert(c.normalized.emote.size == 150)
        c = c.normalized
        assert(try! JSONDecoder().decode(DesktopPingConfiguration.self, from: JSONEncoder().encode(c)) == c)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = root.appendingPathComponent("emotes/facepalm.png")
        let item = try! DesktopEmoteLibrary.importImage(image, existing: [], directory: directory)
        assert(item.valid && item.animation == nil)
        c.emote.custom = [item]
        c.emote.place(item.id, at: 2); c.emote.place(item.id, at: 8)
        c.emote.custom = []
        let repaired = c.emote.normalized
        assert(repaired.wheel[0] == "bee_mad" && Set(repaired.wheel).count == 8 && repaired.center == "facepalm")
        do { _ = try DesktopEmoteLibrary.importImage(image, existing: [item], directory: directory); fatalError("Duplicate accepted") }
        catch DesktopEmoteLibrary.ImportError.duplicate { } catch { fatalError("Wrong import error: \(error)") }
        let animated = try! DesktopEmoteLibrary.importImage(root.appendingPathComponent("emotes/facepalm.webp"), existing: [], directory: directory)
        assert(animated.animation == "webp")
        do { _ = try DesktopEmoteLibrary.importImage(root.appendingPathComponent("overlay/index.html"), existing: [], directory: directory); fatalError("Non-image accepted") }
        catch DesktopEmoteLibrary.ImportError.format { } catch { fatalError("Wrong format error: \(error)") }
        DesktopEmoteLibrary.remove(item, directory: directory)
        assert(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(item.id.dropFirst(2)).png").path))
        for e in DesktopEmote.catalog {
            assert(NSSound(contentsOf: root.appendingPathComponent("emotes/\(e.id).wav"), byReference: false) != nil)
        }
        print("Emote migration, triggers, wheel repair, import validation, animated WebP and 44 sounds passed.")
    }

    @MainActor static func waitFor(_ script: String, in web: WKWebView) async throws {
        for _ in 0..<180 {
            if try await web.evaluateJavaScript(script) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        fatalError("WebKit condition timed out: \(script)")
    }

    @MainActor static func checkEmoteOverlay(_ overlay: DesktopPingOverlay, custom: DesktopEmoteConfiguration.Custom, sounds: () -> [String]) async throws {
        overlay.send("clear")
        overlay.send("wheelOpen", ["wheel": "emote", "x": 500, "y": 400])
        overlay.send("wheelMove", ["x": 500, "y": 260])
        try await waitFor("document.querySelector('#wheel.emote-wheel.open .icon.hot') !== null", in: overlay.webView)
        overlay.send("wheelRelease", ["x": 500, "y": 260])
        try await waitFor("document.querySelector('.emote img')?.complete === true", in: overlay.webView)
        assert(sounds().contains("emote:unworthy_cn"))
        overlay.send("click", ["wheel": "emote", "id": "facepalm", "x": 500, "y": 400])
        try await waitFor("document.querySelector('.emote img')?.src.includes('facepalm') === true", in: overlay.webView)
        let first = try await overlay.webView.evaluateJavaScript("document.querySelector('.emote img').src") as! String
        overlay.send("click", ["wheel": "emote", "id": "facepalm", "x": 500, "y": 400])
        try await waitFor("document.querySelector('.emote img')?.complete === true", in: overlay.webView)
        let second = try await overlay.webView.evaluateJavaScript("document.querySelector('.emote img').src") as! String
        assert(first != second)
        let count = try await overlay.webView.evaluateJavaScript("document.querySelectorAll('.emote').length") as? Int
        assert(count == 1)
        try await Task.sleep(for: .milliseconds(600)) // The baked animation starts with transparent frames.
        let snapshot = try await overlay.webView.takeSnapshot(configuration: nil)
        if let tiff = snapshot.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(".build/desktop-ping/emote.png"))
        }
        overlay.send("clear")
        try await waitFor("document.querySelectorAll('.emote').length === 0", in: overlay.webView)
        var muted = DesktopPingConfiguration(); muted.emote.sound = false
        overlay.send("settings", muted.overlaySettings)
        let soundCount = sounds().count
        overlay.send("click", ["wheel": "emote", "id": "bee_happy", "x": 500, "y": 400])
        try await waitFor("document.querySelector('.emote img')?.complete === true", in: overlay.webView)
        assert(sounds().count == soundCount)
        try await waitFor("document.querySelectorAll('.emote').length === 0", in: overlay.webView)
        var customConfig = DesktopPingConfiguration()
        customConfig.emote.custom = [custom]
        overlay.send("settings", customConfig.overlaySettings)
        overlay.send("click", ["wheel": "emote", "id": custom.id, "x": 500, "y": 400])
        try await waitFor("document.querySelector('.emote img')?.src.startsWith('eave-ping://custom/') === true && document.querySelector('.emote img').naturalWidth > 0", in: overlay.webView)
        overlay.send("clearEmote")
        try await waitFor("document.querySelectorAll('.emote').length === 0", in: overlay.webView)
        print("Custom WebP through the restricted native resource scheme passed.")
        print("WebKit emote wheel, animation restart, replacement, mute and cleanup passed.")
    }

    @MainActor static func checkEditor(emotes: Bool = true) async throws {
        let model = EditorModel()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 480, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        scroll.hasVerticalScroller = true
        let content = NSHostingView(rootView: EditorTestView(model: model, emotes: emotes))
        content.frame = NSRect(x: 0, y: 0, width: 480, height: 1400)
        scroll.documentView = content
        window.contentView = scroll
        window.orderFrontRegardless()
        defer { window.close() }
        func webView(_ view: NSView) -> WKWebView? {
            (view as? WKWebView) ?? view.subviews.compactMap(webView).first
        }
        var web: WKWebView?
        for _ in 0..<180 {
            web = window.contentView.flatMap(webView)
            if web != nil { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        let page = web!
        try await waitFor("document.querySelectorAll('#signals button').length === \(emotes ? 44 : 11)", in: page)
        try await checkEditorScroll(page, scroll: scroll, emotes: emotes)
        guard emotes else { return }
        _ = try await page.evaluateJavaScript("document.querySelector('[data-source=\"pool:facepalm\"]').click(); document.querySelector('[data-slot=\"0\"]').dispatchEvent(new MouseEvent('click'))")
        try await waitFor("document.querySelector('[data-slot=\"0\"] img').src.includes('facepalm')", in: page)
        assert(model.config.emote.wheel[0] == "facepalm" && model.previewed == "facepalm")
        _ = try await page.evaluateJavaScript("const transfer = new DataTransfer(); document.querySelector('[data-source=\"pool:bee_sad\"]').dispatchEvent(new DragEvent('dragstart', {dataTransfer:transfer})); document.querySelector('[data-slot=\"8\"]').dispatchEvent(new DragEvent('drop', {dataTransfer:transfer}));")
        try await waitFor("document.querySelector('[data-slot=\"8\"] img').src.includes('bee_sad')", in: page)
        assert(model.config.emote.center == "bee_sad")
        _ = try await page.evaluateJavaScript("document.querySelector('#reset').click()")
        try await waitFor("document.querySelector('[data-slot=\"8\"] img').src.includes('facepalm')", in: page)
        assert(model.config.emote.wheel == DesktopEmote.defaultWheel)
        try await Task.sleep(for: .milliseconds(200))
        let snapshot = try await page.takeSnapshot(configuration: nil)
        if let tiff = snapshot.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(".build/desktop-ping/emote-editor.png"))
        }
        print("Native editor bridge: preview, assignment, drag/drop center and reset passed.")
    }

    @MainActor static func checkEditorScroll(_ page: WKWebView, scroll: NSScrollView, emotes: Bool) async throws {
        let clip = scroll.contentView
        clip.scroll(to: CGPoint(x: 0, y: 200))
        let start = clip.bounds.origin.y
        for selector in ["#title", "#wheel", "#editor"] {
            _ = try await page.evaluateJavaScript("document.querySelector('\(selector)').dispatchEvent(new WheelEvent('wheel', {deltaY:40, bubbles:true, cancelable:true}))")
        }
        for _ in 0..<100 {
            if abs(clip.bounds.origin.y - start - 120) < 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        assert(abs(clip.bounds.origin.y - start - 120) < 1, "Editor swallowed page scrolling")
        if emotes {
            // Synthetic wheel events have no browser default action; an uncancelled event
            // confirms the palette keeps its native scrolling rather than forwarding it.
            let allowed = try await page.evaluateJavaScript("const pool = document.querySelector('#signals'); pool.scrollTop = 40; pool.dispatchEvent(new WheelEvent('wheel', {deltaY:20, bubbles:true, cancelable:true}))") as? Bool
            assert(allowed == true)
            assert(abs(clip.bounds.origin.y - start - 120) < 1)
        }
        _ = try await page.evaluateJavaScript("document.querySelector('#signals').scrollTop = 0; document.querySelector('#signals button').dispatchEvent(new WheelEvent('wheel', {deltaY:-40, bubbles:true, cancelable:true}))")
        for _ in 0..<100 {
            if abs(clip.bounds.origin.y - start - 80) < 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        assert(abs(clip.bounds.origin.y - start - 80) < 1, "Palette edge swallowed page scrolling")
        clip.scroll(to: .zero)
        print("\(emotes ? "Emote" : "Ping") editor page scrolling and palette boundary passed.")
    }

}

@MainActor private final class EditorModel: ObservableObject {
    @Published var config = DesktopPingConfiguration()
    var previewed: String?
}
private struct EditorTestView: View {
    @ObservedObject var model: EditorModel
    var emotes = true
    var body: some View {
        DesktopPingWheelEditor(configuration: $model.config, preview: { model.previewed = $0 }, emotes: emotes).padding(20)
    }
}
