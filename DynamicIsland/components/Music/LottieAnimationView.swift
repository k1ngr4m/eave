/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Lottie
import Defaults

struct LottieAnimationView: View {
    let isPlaying: Bool
    @Default(.selectedVisualizer) private var selectedVisualizer
    @Default(.customVisualizers) private var customVisualizers

    var body: some View {
        if let visualizer = CustomVisualizer.resolvedSelection(selectedVisualizer, in: customVisualizers) {
            CustomVisualizerAnimationView(visualizer: visualizer, isPlaying: isPlaying)
                .id(visualizer.UUID)
        } else {
            MusicAnimationFallbackView(isPlaying: isPlaying)
        }
    }
}

struct CustomVisualizerAnimationView: View {
    let visualizer: CustomVisualizer
    let isPlaying: Bool
    @State private var loadedURL: URL?

    var body: some View {
        let speed = visualizer.speed.isFinite && visualizer.speed > 0 ? min(2, max(0.1, visualizer.speed)) : 1
        Lottie.LottieView {
            try await visualizer.loadAnimation()
        } placeholder: {
            if loadedURL != visualizer.url {
                MusicAnimationFallbackView(isPlaying: isPlaying)
            }
        }
        .reloadAnimationTrigger(visualizer.url)
        .animationDidLoad { _ in loadedURL = visualizer.url }
        .playbackMode(isPlaying ? .playing(.fromProgress(0, toProgress: 1, loopMode: .loop)) : .paused(at: .currentFrame))
        .animationSpeed(Double(speed))
        .resizable()
        .aspectRatio(contentMode: .fit)
        .clipped()
    }
}

private struct MusicAnimationFallbackView: View {
    let isPlaying: Bool
    @Default(.visualizerBarCount) private var barCount

    var body: some View {
        Rectangle()
            .fill(Color.gray.spectrogramGradient())
            .frame(width: CGFloat(barCount) * 4, height: 12)
            .mask {
                AudioVisualizerView(isPlaying: .constant(isPlaying))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LottieAnimationView(isPlaying: true)
        .frame(width: 32, height: 32)
}
