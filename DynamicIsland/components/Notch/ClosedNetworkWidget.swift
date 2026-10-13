import SwiftUI
import EaveNetworkStats

/// A fixed-size speed row, independent of music playback and lyric availability.
struct ClosedNetworkWidget: View {
    static let height: CGFloat = 22
    static let minimumWidth: CGFloat = 190

    @ObservedObject private var network = NetworkMonitor.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var isPresented = false
    var onHover: (Bool) -> Void = { _ in }

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 12) {
                speed(network.rates.download, symbol: "arrow.down", color: .blue, label: "Download")
                speed(network.rates.upload, symbol: "arrow.up", color: .red, label: "Upload")
            }
            .font(.system(size: 10, weight: .medium)).monospacedDigit()
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open network details")
        .accessibilityIdentifier("ClosedNetworkWidget")
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

    private func speed(_ value: Double, symbol: String, color: Color, label: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(network.formattedSpeed(value))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(width: 78, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label) + Text(" " + network.formattedSpeed(value)))
    }
}
