//
//  settings.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 13/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

class WidgetSelectorView: NSStackView {
    private var module: String
    private var stateCallback: () -> Void = {}
    private var moved: Bool = false

    private var background: NSVisualEffectView = {
        let view = NSVisualEffectView(frame: .zero)
        view.blendingMode = .withinWindow
        view.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 26.0, *) {
            view.material = .titlebar
        } else {
            view.material = .contentBackground
        }
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 5
        return view
    }()

    private var separator: NSView?

    init(module: String, widgets: [SWidget], stateCallback: @escaping () -> Void) {
        self.module = module
        self.stateCallback = stateCallback

        super.init(frame: NSRect.zero)

        self.translatesAutoresizingMaskIntoConstraints = false
        self.edgeInsets = NSEdgeInsets(
            top: Constants.Settings.margin,
            left: Constants.Settings.margin,
            bottom: Constants.Settings.margin,
            right: Constants.Settings.margin
        )
        self.spacing = Constants.Settings.margin

        var active: [WidgetPreview] = []
        var inactive: [WidgetPreview] = []

        if !widgets.isEmpty {
            for i in 0...widgets.count - 1 {
                let widget = widgets[i]
                let preview = WidgetPreview(
                    id: "\(widget.module)_\(widget.type)",
                    type: widget.type,
                    image: widget.image,
                    isActive: widget.isActive, { [weak self] state in
                        widget.toggle(state)
                        self?.stateCallback()
                })
                if widget.isActive {
                    active.append(preview)
                } else {
                    inactive.append(preview)
                }
            }
        }

        active.sort(by: { $0.position < $1.position })
        inactive.sort(by: { $0.position < $1.position })

        active.forEach { (widget: WidgetPreview) in
            self.addArrangedSubview(widget)
        }

        let separator = NSView()
        separator.identifier = NSUserInterfaceItemIdentifier(rawValue: "separator")
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(isDarkMode ? 0.35 : 0.15).cgColor
        self.addArrangedSubview(separator)
        self.separator = separator

        inactive.forEach { (widget: WidgetPreview) in
            self.addArrangedSubview(widget)
        }

        self.addArrangedSubview(NSView())
        self.addSubview(self.background, positioned: .below, relativeTo: .none)

        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: Constants.Widget.height + (Constants.Settings.margin*2)),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalTo: self.heightAnchor, constant: -18),
            self.background.widthAnchor.constraint(equalTo: self.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayer() {
        self.background.setFrameSize(self.frame.size)
        self.separator?.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(isDarkMode ? 0.35 : 0.15).cgColor
    }

    override func mouseUp(with event: NSEvent) {
        guard !self.moved else { return }
        let location = convert(event.locationInWindow, from: nil)
        guard let targetIdx = self.views.firstIndex(where: { $0.hitTest(location) != nil }),
              self.views[targetIdx].identifier != nil, let view = self.views[targetIdx] as? WidgetPreview else {
            super.mouseUp(with: event)
            return
        }
        activate(view)
    }

    fileprivate func activate(_ view: WidgetPreview) {
        guard let targetIdx = views.firstIndex(of: view),
              let separatorIdx = views.firstIndex(where: { $0.identifier?.rawValue == "separator" }) else { return }
        let newIdx = separatorIdx

        view.removeFromSuperviewWithoutNeedingDisplay()
        self.insertArrangedSubview(view, at: newIdx)
        self.layoutSubtreeIfNeeded()

        for (i, v) in self.views(in: .leading).compactMap({$0 as? WidgetPreview}).enumerated() {
            v.position = i
        }

        view.status(separatorIdx < targetIdx)
        NotificationCenter.default.post(name: .widgetRearrange, object: nil, userInfo: ["module": self.module])
    }

    override func mouseDown(with event: NSEvent) {
        self.moved = false
        let location = convert(event.locationInWindow, from: nil)
        guard let targetIdx = self.views.firstIndex(where: { $0.hitTest(location) != nil }),
              let separatorIdx = self.views.firstIndex(where: { $0.identifier?.rawValue == "separator" }),
              let window = self.window, self.views[targetIdx].identifier != nil else {
            super.mouseDragged(with: event)
            return
        }

        let view = self.views[targetIdx]
        let copy = ViewCopy(view)
        copy.zPosition = 2
        copy.transform = CATransform3DMakeScale(0.9, 0.9, 1)

        // hide the original view, show the copy
        view.subviews.forEach({ $0.isHidden = true })
        self.layer?.addSublayer(copy)

        // hide the copy view, show the original
        defer {
            copy.removeFromSuperlayer()
            view.subviews.forEach({ $0.isHidden = false })
        }

        var newIdx = -1
        let originCenter = view.frame.midX
        let originX = view.frame.origin.x
        let p0 = convert(event.locationInWindow, from: nil).x

        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: 1e6, mode: .eventTracking) { event, stop in
            guard let event = event else {
                stop.pointee = true
                return
            }

            if event.type == .leftMouseDragged {
                let p1 = self.convert(event.locationInWindow, from: nil).x
                let diff = p1 - p0

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                copy.frame.origin.x = originX + diff
                CATransaction.commit()

                let reordered = self.views.map{
                    (view: $0, x: $0 !== view ? $0.frame.midX : originCenter + diff)
                }.sorted{ $0.x < $1.x }.map { $0.view }

                guard let nextIndex = reordered.firstIndex(of: view),
                      let prevIndex = self.views.firstIndex(of: view) else {
                    stop.pointee = true
                    return
                }

                if nextIndex != prevIndex && nextIndex != self.views.count - 1 {
                    newIdx = nextIndex
                    view.removeFromSuperviewWithoutNeedingDisplay()
                    self.insertArrangedSubview(view, at: newIdx)
                    self.layoutSubtreeIfNeeded()

                    for (i, v) in self.views(in: .leading).compactMap({$0 as? WidgetPreview}).enumerated() {
                        v.position = i
                    }
                }
                self.moved = abs(diff) > 1
            } else {
                if newIdx != -1, let view = self.views[newIdx] as? WidgetPreview {
                    if newIdx <= separatorIdx && newIdx < targetIdx {
                        view.status(true)
                    } else if newIdx >= separatorIdx {
                        view.status(false)
                    }
                    NotificationCenter.default.post(name: .widgetRearrange, object: nil, userInfo: ["module": self.module])
                }

                view.mouseUp(with: event)
                stop.pointee = true
                self.moved = true
            }
        }
    }
}

private class WidgetPreview: NSStackView {
    private var stateCallback: (_ status: Bool) -> Void = {_ in }

    private let rgbImage: NSImage
    private let grayImage: NSImage
    private let imageView: NSImageView

    private var state: Bool
    private let id: String

    fileprivate var position: Int {
        get { Store.shared.int(key: "\(self.id)_position", defaultValue: 0) }
        set { Store.shared.set(key: "\(self.id)_position", value: newValue) }
    }

    init(id: String, type: widget_t, image: NSImage, isActive: Bool, _ callback: @escaping (_ status: Bool) -> Void) {
        self.id = id
        self.stateCallback = callback
        self.rgbImage = image
        self.grayImage = type == .icon ? image : grayscaleImage(image) ?? image
        self.imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        self.state = isActive

        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Constants.Widget.height))

        self.wantsLayer = true
        self.layer?.cornerRadius = 2
        self.layer?.borderColor = NSColor(red: 221/255, green: 221/255, blue: 221/255, alpha: 1).cgColor
        self.layer?.borderWidth = 1
        self.layer?.backgroundColor = NSColor.white.cgColor

        self.identifier = NSUserInterfaceItemIdentifier(rawValue: type.rawValue)
        self.setAccessibilityElement(true)
        self.toolTip = type.name()
        self.setAccessibilityRole(.button)
        self.setAccessibilityLabel(type.name())
        self.setAccessibilityValue(isActive ? 1 : 0)

        self.orientation = .vertical
        self.distribution = .fill
        self.alignment = .centerY
        self.spacing = 0

        self.imageView.image = isActive ? self.rgbImage : self.grayImage
        self.imageView.alphaValue = isActive ? 1 : 0.75
        if type == .icon {
            self.imageView.imageScaling = .scaleNone
            self.imageView.contentTintColor = .black
        }

        self.addArrangedSubview(self.imageView)

        self.addTrackingArea(NSTrackingArea(
            rect: NSRect(
                x: Constants.Widget.spacing,
                y: 0,
                width: self.imageView.frame.width + Constants.Widget.spacing*2,
                height: self.frame.height
            ),
            options: [NSTrackingArea.Options.activeAlways, NSTrackingArea.Options.mouseEnteredAndExited, NSTrackingArea.Options.activeInActiveApp],
            owner: self,
            userInfo: nil
        ))

        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: self.imageView.frame.width + Constants.Widget.spacing*2),
            self.heightAnchor.constraint(equalToConstant: self.frame.height)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate func status(_ newState: Bool) {
        self.state = newState
        self.setAccessibilityValue(newState ? 1 : 0)
        self.stateCallback(newState)
        self.imageView.image = newState ? self.rgbImage : self.grayImage
        self.imageView.alphaValue = newState ? 1 : 0.8
    }

    override var acceptsFirstResponder: Bool { true }

    override func accessibilityPerformPress() -> Bool {
        guard let selector = superview as? WidgetSelectorView else { return false }
        selector.activate(self)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 || event.keyCode == 36 { _ = accessibilityPerformPress() }
        else { super.keyDown(with: event) }
    }

    override func mouseEntered(with: NSEvent) {
        NSCursor.pointingHand.set()
        if !self.state {
            self.imageView.image = self.rgbImage
            self.imageView.alphaValue = 0.9
        }
    }

    override func mouseExited(with: NSEvent) {
        NSCursor.arrow.set()
        if !self.state {
            self.imageView.image = self.grayImage
            self.imageView.alphaValue = 0.8
        }
    }
}

class WidgetSettings: NSStackView {
    init(title: String, image: NSImage, settingsView: NSView) {
        super.init(frame: NSRect.zero)

        self.translatesAutoresizingMaskIntoConstraints = false
        self.orientation = .vertical
        self.spacing = 0

        self.addArrangedSubview(self.header(title, image))
        self.addArrangedSubview(settingsView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func header(_ title: String, _ image: NSImage) -> NSView {
        let container = NSStackView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .horizontal
        container.edgeInsets = NSEdgeInsets(
            top: 6,
            left: 0,
            bottom: 6,
            right: 0
        )
        container.spacing = 0
        container.distribution = .equalCentering

        let content = NSStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.distribution = .fill
        content.spacing = 0

        let title: NSTextField = LabelField(frame: NSRect(x: 0, y: 0, width: 0, height: 0), title)
        title.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        title.textColor = .textColor

        let imageContainer = NSStackView()
        imageContainer.orientation = .vertical
        imageContainer.spacing = 0
        imageContainer.wantsLayer = true
        imageContainer.layer?.backgroundColor = NSColor.white.cgColor
        imageContainer.layer?.cornerRadius = 2
        imageContainer.edgeInsets = NSEdgeInsets(
            top: 2,
            left: 2,
            bottom: 2,
            right: 2
        )

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image

        imageContainer.addArrangedSubview(imageView)

        content.addArrangedSubview(imageContainer)
        content.addArrangedSubview(title)

        container.addArrangedSubview(NSView())
        container.addArrangedSubview(content)
        container.addArrangedSubview(NSView())

        return container
    }
}
