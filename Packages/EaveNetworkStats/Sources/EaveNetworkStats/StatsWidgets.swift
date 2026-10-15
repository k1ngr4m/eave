import AppKit
import Combine

/// Stats' actual widget views and controls, rendered once for every Eave display.
public class StatsWidgets: NSObject, ObservableObject {
    @Published public private(set) var image = NSImage(size: .zero)
    @Published public private(set) var size = NSSize.zero
    let items: [SWidget]
    private let canvas = NSView()
    private let editor = NSStackView()
    private let livePreview = NSImageView()
    let module: String
    var refreshValues: (() -> Void)?
    private var pendingRender = false

    var active: [SWidget] { items.filter(\.isActive).sorted { $0.position < $1.position } }

    init(module: ModuleType) {
        self.module = module.stringValue
        let url = Bundle.module.url(forResource: module.stringValue + "Widgets", withExtension: "plist")!
        let document = NSDictionary(contentsOf: url)!
        let config = document["Widgets"] as! NSDictionary
        let types = config.allKeys.compactMap { ($0 as? String).flatMap(widget_t.init(rawValue:)) }.sorted {
            ((config[$0.rawValue] as! NSDictionary)["Order"] as! Int) < ((config[$1.rawValue] as! NSDictionary)["Order"] as! Int)
        }
        let defaultWidget = types.first { (config[$0.rawValue] as! NSDictionary)["Default"] as? Bool == true } ?? .mini
        items = types.compactMap { $0.new(module: module.stringValue, config: config, defaultWidget: defaultWidget,
            icon: NSImage(systemSymbolName: document["Symbol"] as! String, accessibilityDescription: nil)) }
        super.init()
        canvas.appearance = NSAppearance(named: .darkAqua)
        editor.orientation = .vertical
        editor.alignment = .centerX
        editor.spacing = 10
        for (position, widget) in items.enumerated() {
            if !Store.shared.exist(key: "\(self.module)_\(widget.type)_position") { widget.position = position }
            widget.sizeCallback = { [weak self] in self?.scheduleRender() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged(_:)), name: .statsPreferencesChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reordered(_:)), name: .widgetRearrange, object: nil)
        scheduleRender()
    }

    public func setDarkAppearance(_ dark: Bool) {
        let name: NSAppearance.Name = dark ? .darkAqua : .aqua
        guard canvas.appearance?.name != name else { return }
        canvas.appearance = NSAppearance(named: name)
        livePreview.layer?.backgroundColor = (dark ? NSColor.black : NSColor(white: 0.96, alpha: 1)).cgColor
        scheduleRender()
    }

    func selector(changed: @escaping () -> Void) -> NSView {
        WidgetSelectorView(module: module, widgets: items) { [weak self] in
            self?.reloadEditor()
            self?.scheduleRender()
            changed()
        }
    }

    func settings() -> NSView { reloadEditor(); return editor }

    private func reloadEditor() {
        editor.arrangedSubviews.forEach { $0.removeFromSuperview() }
        livePreview.identifier = NSUserInterfaceItemIdentifier("\(module)WidgetsPreview")
        livePreview.image = image
        livePreview.imageScaling = .scaleProportionallyDown
        livePreview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        livePreview.wantsLayer = true
        livePreview.layer?.backgroundColor = (canvas.appearance?.name == .aqua ? NSColor(white: 0.96, alpha: 1) : .black).cgColor
        livePreview.layer?.cornerRadius = 6
        livePreview.setAccessibilityLabel(localizedString(module))
        if livePreview.constraints.isEmpty { livePreview.heightAnchor.constraint(equalToConstant: 38).isActive = true }
        editor.addArrangedSubview(livePreview)
        if active.count > 1 {
            let toggle = NSSwitch()
            toggle.action = #selector(toggleMerge(_:))
            toggle.state = Store.shared.bool(key: "\(module)_oneView", defaultValue: false) ? .on : .off
            toggle.target = self
            editor.addArrangedSubview(PreferencesSection([PreferencesRow(localizedString("Merge widgets"), component: toggle)]))
        }
        for widget in active where widget.type != .label {
            editor.addArrangedSubview(WidgetSettings(title: widget.type.name(), image: widget.image, settingsView: widget.item.settings()))
        }
        for view in editor.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: editor.widthAnchor).isActive = true
        }
    }

    @objc private func toggleMerge(_ sender: NSControl) {
        Store.shared.set(key: "\(module)_oneView", value: controlState(sender))
    }

    @objc private func reordered(_ note: Notification) {
        guard note.userInfo?["module"] as? String == module else { return }
        reloadEditor(); scheduleRender()
    }

    @objc private func preferencesChanged(_ note: Notification) {
        guard let key = note.userInfo?["key"] as? String, key.hasPrefix(module + "_") else { return }
        refreshValues?()
        scheduleRender()
    }

    func scheduleRender() {
        guard !pendingRender else { return }
        pendingRender = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingRender = false
            self.render()
        }
    }

    private func render() {
        let list = active
        canvas.subviews.forEach { $0.removeFromSuperview() }
        guard !list.isEmpty else {
            if size != .zero { size = .zero }
            image = NSImage(size: .zero)
            livePreview.image = nil
            return
        }
        canvas.appearance!.performAsCurrentDrawingAppearance {
            let spacing: CGFloat = Store.shared.bool(key: "\(module)_oneView", defaultValue: false) ? Constants.Widget.spacing : 10
            var x: CGFloat = 4
            for widget in list {
                let view = widget.item
                canvas.addSubview(view)
                // Original draw methods determine their width. Measure before composing the strip.
                _ = view.dataWithPDF(inside: view.bounds)
                if let wrapper = view as? WidgetWrapper { view.setFrameSize(wrapper.shadowSize) }
                view.setFrameOrigin(NSPoint(x: x, y: Constants.Widget.margin.y))
                x += view.frame.width + spacing
            }
            let newSize = NSSize(width: x - spacing + 4, height: Constants.Widget.height)
            canvas.setFrameSize(newSize)
            if let rendered = NSImage(data: canvas.dataWithPDF(inside: canvas.bounds)) {
                image = rendered
                livePreview.image = rendered
            }
            if size != newSize { size = newSize }
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

extension Notification.Name {
    static let statsPreferencesChanged = Notification.Name("EaveStatsPreferencesChanged")
}
