/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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

#if os(macOS)
import SwiftUI
import Defaults

/// Custom OSD panel that mimics macOS native OSD appearance
/// Supports volume, brightness, and keyboard backlight displays
struct CustomOSDView: View {
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    
    @Default(.osdMaterial) var osdMaterial
    @Default(.osdLiquidGlassCustomizationMode) var osdLiquidGlassCustomizationMode
    @Default(.osdLiquidGlassVariant) var osdLiquidGlassVariant
    @Default(.osdIconColorStyle) var osdIconColorStyle
    @Environment(\.colorScheme) var colorScheme
    
    private let iconSize: CGFloat = 56
    private let progressBarHeight: CGFloat = 6
    private let spacing: CGFloat = 20
    private let segmentCount: Int = 16
    
    var body: some View {
        VStack(spacing: spacing) {
            // Icon
            ZStack {
                Image(systemName: symbolName)
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(iconColor)
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 80, height: 60, alignment: .center) // Fixed container for icon
            
            // Progress/Value Indicator
            progressView
                .frame(width: 140)
                .padding(.top, 4) // Lower the bar slightly
        }
        .frame(width: 200, height: 200)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.1)) // Subtle backing for shadow source
                .shadow(color: Color.black.opacity(0.25), radius: 24, x: 0, y: 8)
        )
        .background(
            backgroundView
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    
    // MARK: - Symbol Logic
    
    private var symbolName: String {
        if !icon.isEmpty {
            return icon
        }
        
        switch type {
        case .volume:
            if value < 0.01 {
                return "speaker.slash.fill"
            } else if value < 0.33 {
                return "speaker.fill"
            } else if value < 0.66 {
                return "speaker.wave.1.fill"
            } else {
                return "speaker.wave.3.fill"
            }
            
        case .brightness:
            return "sun.max.fill"
            
        case .backlight:
            return value >= 0.5 ? "light.max" : "light.min"
            
        default:
            return "questionmark"
        }
    }
    
    private var backgroundScheme: ColorScheme {
        osdMaterial.colorScheme(for: colorScheme)
    }

    private var iconColor: Color {
        osdIconColorStyle.color(on: backgroundScheme)
    }

    // MARK: - Progress View
    
    private var progressView: some View {
        HStack(spacing: 3) {
            ForEach(0..<segmentCount, id: \.self) { index in
                Capsule()
                    .fill(index < Int(value * CGFloat(segmentCount)) ? iconColor : inactiveSegmentColor)
                    .frame(width: 6, height: progressBarHeight)
            }
        }
    }
    
    private var inactiveSegmentColor: Color {
        (backgroundScheme == .dark ? Color.white : Color.black).opacity(0.25)
    }

    // MARK: - Background
    
    @ViewBuilder
    private var backgroundView: some View {
        switch osdMaterial {
        case .frosted:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        case .liquid:
            if #available(macOS 26.0, *) {
                if osdLiquidGlassCustomizationMode == .customLiquid {
                    LiquidGlassBackground(
                        variant: osdLiquidGlassVariant,
                        cornerRadius: 18
                    ) {
                        Color.white.opacity(0.04)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .glassEffect(
                            .regular.interactive(),
                            in: .rect(cornerRadius: 18)
                        )
                }
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        case .solidDark:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.85))
        case .solidLight:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.85))
        case .solidAuto:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill((colorScheme == .dark ? Color.black : Color.white).opacity(0.85))
        }
    }
}

// MARK: - OSD Material Enum

enum OSDMaterial: String, CaseIterable, Defaults.Serializable {
    case frosted = "Frosted Glass"
    case liquid = "Liquid Glass"
    case solidDark = "Solid Dark"
    case solidLight = "Solid Light"
    case solidAuto = "Solid Auto"

    func colorScheme(for systemScheme: ColorScheme) -> ColorScheme {
        switch self {
        case .solidDark: return .dark
        case .solidLight: return .light
        default: return systemScheme
        }
    }
}

// MARK: - OSD Icon Color Style Enum

enum OSDIconColorStyle: String, CaseIterable, Defaults.Serializable {
    case white = "White"
    case whiteTransparent = "White (Transparent)"
    case lightGray = "Light Gray"
    case darkGray = "Dark Gray"
    case black = "Black"
    case blackTransparent = "Black (Transparent)"
    case auto = "Auto"
    case autoTransparent = "Auto (Transparent)"

    func color(on backgroundScheme: ColorScheme) -> Color {
        let automatic: Color = backgroundScheme == .dark ? .white : .black
        let requested: Color
        switch self {
        case .white: requested = .white
        case .whiteTransparent: requested = .white.opacity(0.85)
        case .lightGray: requested = Color(white: 0.85)
        case .darkGray: requested = Color(white: 0.3)
        case .black: requested = .black
        case .blackTransparent: requested = .black.opacity(0.85)
        case .auto: requested = automatic
        case .autoTransparent: requested = automatic.opacity(0.85)
        }
        // Keep manual colors when readable, including previously saved defaults.
        let luminance = OSDContrast.luminance(of: requested, in: backgroundScheme)
        let contrast = backgroundScheme == .dark
            ? (luminance + 0.05) / 0.05 : 1.05 / (luminance + 0.05)
        return contrast >= 4.5 ? requested : automatic
    }
}

// Shared by the classic OSD and text drawn inside the vertical HUD's fill.
enum OSDContrast {
    static func luminance(of color: Color, in scheme: ColorScheme) -> Double {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let resolved = color.resolve(in: environment)
        let backdrop = scheme == .dark ? 0.0 : 1.0
        func linearize(_ channel: Float) -> Double {
            let value = Double(channel * resolved.opacity) + backdrop * Double(1 - resolved.opacity)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(resolved.red)
            + 0.7152 * linearize(resolved.green)
            + 0.0722 * linearize(resolved.blue)
    }

    static func foreground(on color: Color, in scheme: ColorScheme) -> Color {
        let luminance = luminance(of: color, in: scheme)
        return (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) ? .black : .white
    }
}

#endif
