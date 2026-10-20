import SwiftUI
import Defaults

/// The timer tab composer, without starting or stopping a real timer.
struct TimerSettingsPreview: View {
    @Environment(\.colorScheme) private var systemScheme
    @StateObject private var vm = DynamicIslandViewModel(settingsPreview: true)
    @Default(.enableTimerFeature) private var enableTimerFeature
    @Default(.notchAppearance) private var appearance
    private let contentSize = CGSize(width: 740, height: 160)

    private var hidden: Bool {
        !enableTimerFeature
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = MediaSettingsPreview.scale(content: contentSize, stage: geometry.size)
            NotchTimerView(isSettingsPreview: true)
                .frame(width: contentSize.width, height: contentSize.height)
                .background(Color.notchBackground, in: RoundedRectangle(cornerRadius: 18))
                .environment(\.colorScheme, appearance.colorScheme(for: systemScheme))
                .environmentObject(vm)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .opacity(hidden ? 0.4 : 1)
                .scaleEffect(scale)
                .frame(width: contentSize.width * scale, height: contentSize.height * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 184)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottomTrailing) {
            if hidden {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Preview"))
    }
}

#Preview {
    TimerSettingsPreview().padding().frame(width: 700)
}
