import SwiftUI
import WebKit

struct DesktopPingWheelEditor: View {
    @Binding var configuration: DesktopPingConfiguration
    var preview: (String) -> Void
    var emotes = false
    @State private var height: CGFloat = 370
    @State private var failed = false

    var body: some View {
        if failed {
            Text("Could not load the desktop ping overlay.").foregroundStyle(.secondary)
        } else {
            Editor(configuration: $configuration, preview: preview, emotes: emotes, height: $height, failed: $failed)
                .frame(height: height)
        }
    }

    private struct Editor: NSViewRepresentable {
        @Binding var configuration: DesktopPingConfiguration
        var preview: (String) -> Void
        var emotes: Bool
        @Binding var height: CGFloat
        @Binding var failed: Bool

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        func makeNSView(context: Context) -> WKWebView {
            let settings = WKWebViewConfiguration()
            if let root = Bundle.main.resourceURL?.appendingPathComponent("DesktopPing") {
                settings.setURLSchemeHandler(DesktopPingResources(root: root), forURLScheme: "eave-ping")
            }
            settings.userContentController.add(context.coordinator, name: "editor")
            let view = WKWebView(frame: .zero, configuration: settings)
            view.setValue(false, forKey: "drawsBackground")
            view.navigationDelegate = context.coordinator
            context.coordinator.webView = view
            view.load(URLRequest(url: URL(string: "eave-ping://bundle/editor/index.html")!))
            return view
        }

        func updateNSView(_ view: WKWebView, context: Context) {
            context.coordinator.parent = self
            context.coordinator.update()
        }

        static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
            view.configuration.userContentController.removeScriptMessageHandler(forName: "editor")
            view.navigationDelegate = nil
            view.stopLoading()
        }

        final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
            var parent: Editor
            weak var webView: WKWebView?
            private var ready = false
            private var lastConfiguration: DesktopPingConfiguration?
            init(_ parent: Editor) { self.parent = parent }

            func update() {
                let config = parent.configuration.normalized
                guard ready, config != lastConfiguration else { return }
                lastConfiguration = config
                let names = Dictionary(uniqueKeysWithValues: zip(DesktopPingConfiguration.pingIDs, DesktopPingConfiguration.titles.map { NSLocalizedString($0, comment: "") }))
                let emotes = parent.emotes
                let items = emotes ? config.emote.items : zip(DesktopPingConfiguration.pingIDs, DesktopPingConfiguration.icons).map {
                    ["id": $0.0, "icon": "../textures/\($0.1).png", "name": names[$0.0]!]
                }
                let state: [String: Any] = [
                    "wheel": emotes ? config.emote.wheel : config.wheel,
                    "clickPingID": emotes ? config.emote.center : config.clickPingID,
                    "clickPing": emotes ? config.emote.click : config.clickPing,
                    "items": items, "emotes": emotes,
                    "names": Dictionary(uniqueKeysWithValues: items.map { ($0["id"]!, $0["name"]!) }),
                    "directions": [NSLocalizedString("DesktopPing.Direction.Up", value: "Up", comment: "Wheel direction"), String(localized: "Upper Right"), String(localized: "Right"), String(localized: "Lower Right"), NSLocalizedString("DesktopPing.Direction.Down", value: "Down", comment: "Wheel direction"), String(localized: "Lower Left"), String(localized: "Left"), String(localized: "Upper Left")],
                    "labels": [
                        "title": emotes ? String(localized: "Customize Emote Wheel") : String(localized: "Customize Wheel"),
                        "description": emotes ? String(localized: "Drag emotes onto the wheel or center. Hold \(config.emote.trigger.label) and drag to send.") : String(localized: "Drag signals into a segment. Drop in the center to set the signal sent by \(config.trigger.label) + click."),
                        "poolTitle": emotes ? String(localized: "All Emotes") : String(localized: "All Signals"),
                        "poolDescription": emotes ? String(localized: "Click to preview. Drag an emote to assign it, or click an emote and then a position.") : String(localized: "Click to preview. Drag onto the wheel to assign, or select a signal and then click a position."),
                        "reset": String(localized: "Reset to Default"),
                        "center": emotes ? String(localized: "Click Emote") : String(localized: "Click Signal"), "click": String(localized: "Click"),
                        "placeHint": String(localized: "Choose a segment or the center. Esc cancels.")
                    ]
                ]
                webView?.callAsyncJavaScript("window.updateEditor(state)", arguments: ["state": state], in: nil, in: .page) { [weak self] result in
                    if case .failure = result { self?.parent.failed = true }
                }
            }

            func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
                guard message.frameInfo.isMainFrame, let data = message.body as? [String: Any], let type = data["type"] as? String else { return }
                switch type {
                case "ready": ready = true; update()
                case "height":
                    if let height = data["value"] as? Double, height.isFinite, height > 0, height < 2000 {
                        parent.height = height
                    }
                case "scroll":
                    guard let delta = data["delta"] as? Double, delta.isFinite,
                          let scroll = webView?.enclosingScrollView, let document = scroll.documentView else { return }
                    let clip = scroll.contentView
                    var bounds = clip.bounds
                    bounds.origin.y += document.isFlipped ? delta : -delta
                    clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
                    scroll.reflectScrolledClipView(clip)
                case "assign":
                    guard let id = data["id"] as? String, let slot = data["slot"] as? Int else { return }
                    if parent.emotes { parent.configuration.emote.place(id, at: slot) }
                    else { parent.configuration.place(id, at: slot) }
                case "preview":
                    if let id = data["id"] as? String, parent.emotes ? parent.configuration.emote.contains(id) : DesktopPingConfiguration.pingIDs.contains(id) { parent.preview(id) }
                case "reset":
                    var config = parent.configuration
                    if parent.emotes {
                        config.emote.wheel = DesktopEmote.defaultWheel
                        config.emote.center = "facepalm"
                    } else {
                        config.wheel = DesktopPingConfiguration.defaultWheel
                        config.clickPingID = "generic"
                    }
                    parent.configuration = config
                default: break
                }
            }

            func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
                let url = navigationAction.request.url
                decisionHandler(url?.scheme == "eave-ping" && url?.host == "bundle" ? .allow : .cancel)
            }
            func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.failed = true }
            func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.failed = true }
            func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { parent.failed = true }
        }
    }
}
