import SwiftUI
import EaveNetworkStats

/// Original Stats widgets, independent of music playback and lyric availability.
struct ClosedNetworkWidget: View {
    static let height: CGFloat = 22
    static var minimumWidth: CGFloat { max(190, min(600, NetworkMonitor.shared.widgets.size.width + 16)) }

    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var widgets = NetworkMonitor.shared.widgets
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var isPresented = false
    var onHover: (Bool) -> Void = { _ in }

    var body: some View {
        Button { isPresented = true } label: {
            Image(nsImage: widgets.image)
            .resizable().scaledToFit()
            .frame(width: min(widgets.size.width, Self.minimumWidth - 16), height: Self.height)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open network details")
        .accessibilityIdentifier("ClosedNetworkWidget")
        .accessibilityLabel(Text("\(Text("Download")) \(network.formattedSpeed(network.rates.download)), \(Text("Upload")) \(network.formattedSpeed(network.rates.upload))"))
        .contextMenu { Button("Network settings…") { network.showSettings() } }
        .onHover(perform: onHover)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            NetworkMonitoringDetailView()
        }
        .onChange(of: isPresented) { _, presented in vm.isStatsPopoverActive = presented }
        .onDisappear {
            isPresented = false
            vm.isStatsPopoverActive = false
            onHover(false)
        }
    }
}
