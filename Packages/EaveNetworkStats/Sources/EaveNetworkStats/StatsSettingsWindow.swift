import AppKit

func makeStatsSettingsWindow(module: String, widgets: StatsWidgets, panes: [(String, NSView)], selectionChanged: @escaping () -> Void) -> NSWindow {
    let tabs = NSTabView(frame: NSRect(x: 0, y: 0, width: 580, height: 650))

    for (name, pane) in panes {
        let scroll = ScrollableStackView()
        scroll.stackView.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        scroll.stackView.addArrangedSubview(pane)
        pane.translatesAutoresizingMaskIntoConstraints = false
        pane.widthAnchor.constraint(equalTo: scroll.stackView.widthAnchor, constant: -24).isActive = true
        let tab = NSTabViewItem(identifier: name)
        tab.label = localizedString(name)
        tab.view = scroll
        tabs.addTabViewItem(tab)
    }
    let window = NSWindow(contentRect: tabs.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = localizedString(module) + " — " + localizedString("Settings")
    let content = NSView(frame: tabs.frame)
    let selector = widgets.selector(changed: selectionChanged)
    tabs.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(selector)
    content.addSubview(tabs)
    NSLayoutConstraint.activate([
        selector.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
        selector.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
        selector.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
        tabs.topAnchor.constraint(equalTo: selector.bottomAnchor, constant: 8),
        tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
        tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
        tabs.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
    ])
    window.contentView = content
    window.minSize = NSSize(width: 580, height: 480)
    window.isReleasedWhenClosed = false
    window.center()
    return window
}
