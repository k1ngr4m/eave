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

    public func new(module: String, config: NSDictionary, defaultWidget: widget_t, icon: NSImage? = nil) -> SWidget? {
        guard let widgetConfig: NSDictionary = config[self.rawValue] as? NSDictionary else { return nil }

        var image: NSImage? = nil
        var preview: widget_p? = nil
        var item: widget_p? = nil

        switch self {
        case .networkChart:
            preview = NetworkChart(title: module, config: widgetConfig, preview: true)
            item = NetworkChart(title: module, config: widgetConfig, preview: false)
        case .speed:
            preview = SpeedWidget(title: module, config: widgetConfig, preview: true)
            item = SpeedWidget(title: module, config: widgetConfig, preview: false)
        case .label:
            preview = Label(title: module, config: widgetConfig)
            item = Label(title: module, config: widgetConfig)
        case .state:
            preview = DotWidget(title: module, config: widgetConfig, preview: true)
            item = DotWidget(title: module, config: widgetConfig, preview: false)
        case .text:
            preview = TextWidget(title: module, preview: true)
            item = TextWidget(title: module, preview: false)
        case .icon:
            preview = IconWidget(title: module, icon: icon, preview: true)
            item = IconWidget(title: module, icon: icon, preview: false)
            image = icon?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)) ?? icon
        default: break
        }

        if image == nil, let view = preview {
            let width: CGFloat = view.bounds.width

            let r = NSRect(
                x: -view.frame.origin.x/2,
                y: 0,
                width: width - view.frame.origin.x,
                height: view.bounds.height
            )
            image = NSImage(data: view.dataWithPDF(inside: r))
        }

        if let item = item, let image = image {
            return SWidget(self, defaultWidget: defaultWidget, module: module, item: item, image: image)
        }

        return nil
    }

    public func name() -> String {
        switch self {
        case .mini: return localizedString("Mini widget")
        case .lineChart: return localizedString("Line chart widget")
        case .barChart: return localizedString("Bar chart widget")
        case .pieChart: return localizedString("Pie chart widget")
        case .networkChart: return localizedString("Network chart widget")
        case .speed: return localizedString("Speed widget")
        case .battery: return localizedString("Battery widget")
        case .batteryDetails: return localizedString("Battery details widget")
        case .stack: return localizedString("Stack widget")
        case .memory: return localizedString("Memory widget")
        case .label: return localizedString("Label widget")
        case .tachometer: return localizedString("Tachometer widget")
        case .state: return localizedString("State widget")
        case .text: return localizedString("Text widget")
        case .icon: return localizedString("Icon widget")
        default: return ""
        }
    }
}
extension widget_t: CaseIterable {}

public protocol widget_p: NSView {
    var widthHandler: (() -> Void)? { get set }
    var onClick: (() -> Void)? { get set }

    func settings() -> NSView
}

open class WidgetWrapper: NSView, widget_p {
    public var type: widget_t
    public var title: String
    public var widthHandler: (() -> Void)? = nil
    public var onClick: (() -> Void)? = nil
    public var shadowSize: CGSize
    internal var queue: DispatchQueue

    public init(_ type: widget_t, title: String, frame: NSRect) {
        self.type = type
        self.title = title
        self.shadowSize = frame.size
        self.queue = DispatchQueue(label: "eu.exelban.Stats.WidgetWrapper.\(type.rawValue).\(title)")

        super.init(frame: frame)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setWidth(_ width: CGFloat) {
        var newWidth = width
        if width == 0 || width == 1 {
            newWidth = self.emptyView()
        }

        guard self.shadowSize.width != newWidth else { return }
        self.shadowSize.width = newWidth

        DispatchQueue.main.async {
            self.setFrameSize(NSSize(width: newWidth, height: self.frame.size.height))
            self.widthHandler?()
        }
    }

    public func emptyView() -> CGFloat {
        let size: CGFloat = 15
        let lineWidth = 1 / (NSScreen.main?.backingScaleFactor ?? 1)
        let offset = lineWidth / 2
        let width: CGFloat = (Constants.Widget.margin.x*2) + size + (lineWidth*2)

        NSColor.textColor.set()

        var circle = NSBezierPath()
        circle = NSBezierPath(ovalIn: CGRect(x: Constants.Widget.margin.x+offset, y: 1+offset, width: size, height: size))
        circle.stroke()
        circle.lineWidth = lineWidth

        let line = NSBezierPath()
        line.move(to: NSPoint(x: 3, y: 3.5))
        line.line(to: NSPoint(x: 13.5, y: 14))
        line.lineWidth = lineWidth
        line.stroke()

        return width
    }

    public func redraw() {
        DispatchQueue.main.async { [weak self] in
            self?.needsDisplay = true
        }
    }

    open func settings() -> NSView { return NSView() }

    open override func mouseDown(with event: NSEvent) {
        if let f = self.onClick {
            f()
            return
        }
        super.mouseDown(with: event)
    }
}

public class SWidget {
    public let type: widget_t
    public let defaultWidget: widget_t
    public let module: String
    public let image: NSImage
    public var item: widget_p

    public var isActive: Bool {
        get { self.list.contains{ $0 == self.type } }
        set {
            if newValue {
                self.list.append(self.type)
            } else {
                self.list.removeAll{ $0 == self.type }
            }
        }
    }

    public var toggleCallback: ((widget_t, Bool) -> Void)? = nil
    public var sizeCallback: (() -> Void)? = nil

    public var log: NextLog {
        NextLog.shared.copy(category: self.module)
    }
    public var position: Int {
        get { Store.shared.int(key: "\(self.module)_\(self.type)_position", defaultValue: 0) }
        set { Store.shared.set(key: "\(self.module)_\(self.type)_position", value: newValue) }
    }


    private var list: [widget_t] {
        get {
            let string = Store.shared.string(key: "\(self.module)_widget", defaultValue: self.defaultWidget.rawValue)
            return string.split(separator: ",").map{ (widget_t(rawValue: String($0)) ?? .unknown)}
        }
        set { Store.shared.set(key: "\(self.module)_widget", value: newValue.map{ $0.rawValue }.joined(separator: ",")) }
    }


    public init(_ type: widget_t, defaultWidget: widget_t, module: String, item: widget_p, image: NSImage) {
        self.type = type
        self.module = module
        self.item = item
        self.defaultWidget = defaultWidget
        self.image = image

        self.item.widthHandler = { [weak self] in
            self?.sizeCallback?()

        }
        self.item.identifier = NSUserInterfaceItemIdentifier(self.type.rawValue)
    }

    // show item in the menu bar
    public func enable() {
        guard self.isActive else { return }
        self.toggleCallback?(self.type, true)
        debug("widget \(self.type.rawValue) enabled", log: self.log)
    }

    // remove item from the menu bar
    public func disable() {
        self.toggleCallback?(self.type, false)
        debug("widget \(self.type.rawValue) disabled", log: self.log)
    }

    // toggle the widget
    public func toggle(_ state: Bool? = nil) {
        var newState: Bool = !self.isActive
        if let state = state {
            newState = state
        }

        if self.isActive == newState {
            return
        }

        self.isActive = newState

        if !self.isActive {
            self.disable()
        } else {
            self.enable()
        }

        NotificationCenter.default.post(name: .toggleWidget, object: nil, userInfo: ["module": self.module])
    }

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

