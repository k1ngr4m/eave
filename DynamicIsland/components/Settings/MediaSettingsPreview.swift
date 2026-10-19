import SwiftUI
import Defaults

private struct MediaSettingsPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isMediaSettingsPreview: Bool {
        get { self[MediaSettingsPreviewKey.self] }
        set { self[MediaSettingsPreviewKey.self] = newValue }
    }
}

/// The actual media page, without the notch's navigation or other home widgets.
struct MediaSettingsPreview: View {
    @Environment(\.colorScheme) private var systemScheme
    @StateObject private var vm = DynamicIslandViewModel(settingsPreview: true)
    @ObservedObject private var music = MusicManager.shared
    @Namespace private var artworkNamespace
    @Default(.notchAppearance) private var appearance
    @Default(.enableMinimalisticUI) private var minimalistic
    @Default(.showStandardMediaControls) private var showMedia
    @Default(.autoHideInactiveNotchMediaPlayer) private var autoHide
    @Default(.enableLyrics) private var lyrics
    @Default(.lyricsPanelWidth) private var lyricsWidth
    @Default(.lyricsPanelOffset) private var lyricsOffset
    @Default(.showMinimalisticBatteryIndicator) private var batteryIndicator
    @Default(.externalDisplayStyle) private var displayStyle
    @Default(.enableWaveformScrubber) private var waveform
    @Default(.colorExtractionMode) private var colorExtraction
    @Default(.visualizerBarCount) private var visualizerBars

    private var sideLyrics: Bool { !minimalistic && lyrics }
    private var hidden: Bool {
        !minimalistic && (!showMedia || (autoHide && !music.hasActiveSession))
    }
    private var size: CGSize {
        if minimalistic { return CGSize(width: 420, height: 280) }
        return CGSize(width: 440 + (sideLyrics ? max(0, lyricsWidth) + abs(lyricsOffset) + 20 : 0),
                      height: 200)
    }

    static func scale(content: CGSize, stage: CGSize) -> CGFloat {
        guard content.width > 0, content.height > 0 else { return 1 }
        return max(0, min(1, (stage.width - 32) / content.width, (stage.height - 24) / content.height))
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = Self.scale(content: size, stage: geometry.size)
            player
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background(Color.notchBackground, in: RoundedRectangle(cornerRadius: 24))
                .environment(\.colorScheme, appearance.colorScheme(for: systemScheme))
                .environment(\.isMediaSettingsPreview, true)
                .environmentObject(vm)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .opacity(hidden ? 0.4 : 1)
                .scaleEffect(scale)
                .frame(width: size.width * scale, height: size.height * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 200)
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
        .accessibilityValue(Text(music.hasActiveSession ? music.songTitle : String(localized: "Nothing Playing")))
    }

    @ViewBuilder
    private var player: some View {
        if minimalistic {
            MinimalisticMusicPlayerView(albumArtNamespace: artworkNamespace)
                // The compact player's artwork can extend up around the camera area.
                .padding(.top, vm.effectiveClosedNotchHeight)
        } else if music.hasActiveSession {
            HStack(alignment: .top, spacing: SideLyricsLayout.hStackSpacing) {
                MusicPlayerView(albumArtNamespace: artworkNamespace)
                    .frame(maxWidth: .infinity)
                if sideLyrics {
                    LyricsSidePanelView()
                        .frame(width: max(0, lyricsWidth))
                        .padding(.leading, max(0, -lyricsOffset))
                        .offset(x: lyricsOffset)
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "music.note.slash").font(.title2)
                Text("Nothing Playing").font(.callout)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    MediaSettingsPreview().padding().frame(width: 700)
}
