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

struct ProcessorMonitoringDetailView: View {
    @ObservedObject var monitor: ProcessorMonitor
    var body: some View {
        ProcessorPanel(monitor: monitor)
            .frame(width: monitor.panelSize.width, height: monitor.panelSize.height)
            .onAppear { monitor.setVisible(true) }
            .onDisappear { monitor.setVisible(false) }
    }
}

private struct ProcessorPanel: NSViewRepresentable {
    let monitor: ProcessorMonitor
    func makeNSView(context: Context) -> NSView { monitor.panel }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct MemoryDiskMonitoringDetailView: View {
    @ObservedObject var monitor: MemoryDiskMonitor
    var body: some View {
        MemoryDiskPanel(monitor: monitor)
            .frame(width: monitor.panelSize.width, height: monitor.panelSize.height)
            .onAppear { monitor.setVisible(true) }
            .onDisappear { monitor.setVisible(false) }
    }
}

private struct MemoryDiskPanel: NSViewRepresentable {
    let monitor: MemoryDiskMonitor
    func makeNSView(context: Context) -> NSView { monitor.panel }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct SensorsMonitoringDetailView: View {
    @ObservedObject private var monitor = SensorsMonitor.shared
    var body: some View {
        SensorsPanel(monitor: monitor)
            .frame(width: monitor.panelSize.width, height: monitor.panelSize.height)
            .onAppear { monitor.setVisible(true) }
            .onDisappear { monitor.setVisible(false) }
    }
}

private struct SensorsPanel: NSViewRepresentable {
    let monitor: SensorsMonitor
    func makeNSView(context: Context) -> NSView { monitor.panel }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
