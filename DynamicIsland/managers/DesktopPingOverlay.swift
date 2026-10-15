import AppKit
import WebKit

/// A separate, non-activating surface: pings stay visible when the notch is hidden from screen sharing.
@MainActor
final class DesktopPingOverlay: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let screen: NSScreen
    let panel: NSPanel
    let webView: WKWebView
    var ready = false
    var onReady: (() -> Void)?
    var onSound: ((String) -> Void)?
    var onFailure: ((String) -> Void)?

    init(screen: NSScreen, root: URL, customRoot: URL = DesktopEmoteLibrary.directory) {
        self.screen = screen
        panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(DesktopPingResources(root: root, customRoot: customRoot), forURLScheme: "eave-ping")
        webView = WKWebView(frame: NSRect(origin: .zero, size: screen.frame.size), configuration: config)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.sharingType = .readOnly
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        config.userContentController.add(self, name: "ping")
        panel.contentView = webView
        webView.load(URLRequest(url: URL(string: "eave-ping://bundle/overlay/index.html")!))
        panel.orderFrontRegardless()
    }

    func send(_ type: String, _ payload: [String: Any] = [:]) {
        guard ready else { return }
        webView.callAsyncJavaScript("window.eavePing(type, payload)", arguments: ["type": type, "payload": payload], in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result { self?.onFailure?(error.localizedDescription) }
        }
    }

    func close() {
        ready = false
        onReady = nil
        onSound = nil
        onFailure = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "ping")
        webView.navigationDelegate = nil
        webView.stopLoading()
        panel.close()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready": ready = true; onReady?()
        case "sound": if let name = body["name"] as? String { onSound?(name) }
        case "error": onFailure?(String(localized: "Could not load the desktop ping overlay."))
        default: break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        decisionHandler(url?.scheme == "eave-ping" && url?.host == "bundle" ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFailure?(error.localizedDescription) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onFailure?(error.localizedDescription) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { onFailure?(String(localized: "The desktop ping overlay stopped. Try again.")) }
}

final class DesktopPingResources: NSObject, WKURLSchemeHandler {
    let root: URL
    let customRoot: URL
    init(root: URL, customRoot: URL = DesktopEmoteLibrary.directory) {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
        self.customRoot = customRoot.resolvingSymlinksInPath().standardizedFileURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, ["bundle", "custom"].contains(url.host ?? "") else {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        let base = url.host == "custom" ? customRoot : root
        if url.host == "custom", url.path.range(of: "^/[0-9a-f]{32}\\.(png|gif|webp)$", options: .regularExpression) == nil {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        let file = base.appendingPathComponent(url.path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(base.path + "/") else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile)); return
        }
        do {
            let data = try Data(contentsOf: file)
            let mime = ["html": "text/html", "js": "text/javascript", "css": "text/css", "png": "image/png", "webp": "image/webp", "gif": "image/gif"][file.pathExtension] ?? "application/octet-stream"
            urlSchemeTask.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: "utf-8"))
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
