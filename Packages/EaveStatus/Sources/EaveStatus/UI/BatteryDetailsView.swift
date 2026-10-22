import SwiftUI
@preconcurrency import EaveNetworkStats

struct BatteryDetailsView: View {
    @EnvironmentObject private var localization: Localization
    @StateObject private var monitor = BatteryMonitor()
    let onBack: () -> Void
    let onOpenBatterySettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BatteryPanel(monitor: monitor)
                .frame(width: monitor.panelSize.width, height: monitor.panelSize.height)
            Button(action: onBack) {
                Label(localization.string(.commonBack), systemImage: "chevron.left")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .frame(width: monitor.panelSize.width)
        .onAppear {
            monitor.openSettings = onOpenBatterySettings
            monitor.setVisible(true)
        }
        .onDisappear { monitor.setVisible(false) }
    }
}

private struct BatteryPanel: NSViewRepresentable {
    let monitor: BatteryMonitor
    func makeNSView(context: Context) -> NSView { monitor.panel }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
