import SwiftUI
import Defaults

struct NotchAppearanceSettings: View {
    @Default(.notchAppearance) private var selection

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                Label("Notch appearance", systemImage: "circle.lefthalf.filled")
                    .fixedSize()
                    .padding(.top, 8)
                Spacer(minLength: 16)
                options
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("Notch appearance", systemImage: "circle.lefthalf.filled")
                options
            }
        }
        .padding(.vertical, 4)
    }

    private var options: some View {
        HStack(spacing: 12) {
            ForEach(NotchAppearance.allCases) { appearance in
                Button {
                    selection = appearance
                } label: {
                    VStack(spacing: 6) {
                        NotchAppearancePreview(appearance: appearance)
                            .frame(width: 100, height: 68)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(3)
                            .overlay {
                                RoundedRectangle(cornerRadius: 11)
                                    .strokeBorder(selection == appearance ? Color.accentColor : Color.primary.opacity(0.12),
                                                  lineWidth: selection == appearance ? 3 : 1)
                            }
                        Text(appearance.localizedName)
                            .font(.callout)
                            .fontWeight(selection == appearance ? .semibold : .regular)
                            .foregroundStyle(selection == appearance ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(appearance.localizedName))
                .accessibilityAddTraits(selection == appearance ? .isSelected : [])
            }
        }
    }
}

/// A miniature of the actual notch surface; system mode shows both appearances.
struct NotchAppearancePreview: View {
    let appearance: NotchAppearance

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                scene(dark: appearance == .dark)
                if appearance == .system {
                    scene(dark: true)
                        .mask(alignment: .trailing) {
                            Rectangle().frame(width: geometry.size.width / 2)
                        }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func scene(dark: Bool) -> some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: dark
                           ? [Color(red: 0.12, green: 0.15, blue: 0.39), Color(red: 0.16, green: 0.38, blue: 0.65)]
                           : [Color(red: 0.59, green: 0.81, blue: 0.96), Color(red: 0.29, green: 0.59, blue: 0.85)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 6) {
                HStack(spacing: 3) {
                    Image(systemName: "music.note")
                    Spacer()
                    Image(systemName: "battery.100percent")
                }
                .font(.system(size: 5, weight: .semibold))
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.blue.gradient)
                        .frame(width: 17, height: 17)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 8)).foregroundStyle(.white)
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(Color.primary.opacity(0.8)).frame(width: 24, height: 3)
                        Capsule().fill(Color.primary.opacity(0.3)).frame(width: 17, height: 2)
                    }
                    Image(systemName: "pause.fill").font(.system(size: 7))
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.top, 5)
            .padding(.bottom, 9)
            .background(Color.notchBackground, in: NotchShape(topCornerRadius: 4, bottomCornerRadius: 9))
            .padding(.horizontal, 8)
            // The camera cutout stays black in both appearances.
            UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3)
                .fill(.black)
                .frame(width: 29, height: 9)
        }
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}
