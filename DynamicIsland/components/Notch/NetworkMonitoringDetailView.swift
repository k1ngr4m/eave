import SwiftUI
import EaveNetworkStats

/// Hosts Stats' original AppKit popup, including its header and settings actions.
struct NetworkMonitoringDetailView: View {
    @ObservedObject private var network = NetworkMonitor.shared
    var body: some View {
        NetworkPanel(network: network)
            .frame(width: network.panelSize.width, height: network.panelSize.height)
            .onAppear { network.setVisible(true) }
            .onDisappear { network.setVisible(false) }
    }
}

private struct NetworkPanel: NSViewRepresentable {
    let network: NetworkMonitor
    func makeNSView(context: Context) -> NSView { network.panel }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
