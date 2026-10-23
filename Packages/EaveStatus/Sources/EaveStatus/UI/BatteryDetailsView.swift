import SwiftUI
@preconcurrency import EaveNetworkStats

struct BatteryDetailsView: View {
    @StateObject private var monitor = BatteryMonitor()
    let onOpenBatterySettings: () -> Void

    var body: some View {
        BatteryPanel(monitor: monitor)
            .frame(width: monitor.panelSize.width, height: monitor.panelSize.height)
            .onAppear {
                monitor.openSettings = onOpenBatterySettings
                monitor.setVisible(true)
            }
            .onDisappear { monitor.setVisible(false) }
    }
}

struct BatteryPanel: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let monitor: BatteryMonitor
    func makeNSView(context: Context) -> NSView { monitor.panel }
    func updateNSView(_ nsView: NSView, context: Context) {
        // Stats draws ordinary AppKit labels, which must not inherit vibrant label colors.
        nsView.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}
