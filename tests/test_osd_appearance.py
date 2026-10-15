"""Run: python3 tests/test_osd_appearance.py (requires the macOS Swift toolchain)."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
classic = (root / "DynamicIsland/components/OSD/CustomOSDView.swift").read_text()
vertical = (root / "DynamicIsland/components/OSD/VerticalHUDView.swift").read_text()
palette = (root / "DynamicIsland/components/ColorCodedProgressBar.swift").read_text()
# Compile the production color rules without starting the app or its hardware managers.
rules = classic.split("enum OSDMaterial:", 1)[1].rsplit("#endif", 1)[0]
rules = "enum OSDMaterial:" + rules.replace(", Defaults.Serializable", "")
properties = vertical.split("    private var backgroundScheme:", 1)[1].split("    @ViewBuilder", 1)[0]
properties = ("    private var backgroundScheme:" + properties).replace("private var", "var")
palette = "enum ColorCodedPalette {" + palette.split("enum ColorCodedPalette {", 1)[1].split("// MARK: - Preview", 1)[0]
source = "import SwiftUI\n" + rules + palette + """
enum Channel { case volume, brightness }
struct State { var type: Channel; var value: CGFloat }
struct VerticalColors {
    var state: State
    var verticalHUDMaterial: OSDMaterial
    var colorScheme: ColorScheme
    var useColorCodedVolume: Bool
    var useAccentColor: Bool
""" + properties + """
}
func contrast(_ foreground: Color, _ background: Color, _ scheme: ColorScheme) -> Double {
    let a = OSDContrast.luminance(of: foreground, in: scheme)
    let b = OSDContrast.luminance(of: background, in: scheme)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}
for system in [ColorScheme.light, .dark] {
    for material in OSDMaterial.allCases {
        let scheme = material.colorScheme(for: system)
        assert(material != .solidDark || scheme == .dark)
        assert(material != .solidLight || scheme == .light)
        if material != .solidDark && material != .solidLight { assert(scheme == system) }
        let background: Color = scheme == .dark ? .black : .white
        for style in OSDIconColorStyle.allCases {
            assert(contrast(style.color(on: scheme), background, scheme) >= 4.5,
                   "Unreadable classic OSD: \\(system), \\(material), \\(style)")
        }
        for channel in [Channel.volume, .brightness] {
            for colored in [false, true] {
                for accent in [false, true] {
                    for value in [0.0, 0.15, 0.16, 0.5, 0.85, 0.86, 1.0] {
                        let hud = VerticalColors(state: State(type: channel, value: value),
                            verticalHUDMaterial: material, colorScheme: system,
                            useColorCodedVolume: colored, useAccentColor: accent)
                        assert(contrast(hud.unfilledForeground, background, scheme) >= 4.5)
                        let fill: Color = channel == .volume && colored
                            ? ColorCodedPalette.color(for: value, smooth: true)
                            : (accent ? .accentColor : hud.unfilledForeground)
                        assert(contrast(hud.filledForeground, fill, system) >= 4.5)
                        let labelBackground = value > 0.85 ? fill : background
                        assert(contrast(hud.valueLabelColor, labelBackground, system) >= 4.5)
                    }
                }
            }
        }
    }
    for color in [Color.black, .white, .blue, .yellow, .purple, .gray, .accentColor] {
        assert(contrast(OSDContrast.foreground(on: color, in: system), color, system) >= 4.5)
    }
    // Black glyphs must remain readable throughout the volume gradient.
    for step in 0...100 {
        for smooth in [false, true] {
            let color = ColorCodedPalette.color(for: Double(step) / 100, smooth: smooth)
            assert(contrast(.black, color, system) >= 4.5)
        }
    }
}
assert(OSDIconColorStyle.whiteTransparent.color(on: .dark) == Color.white.opacity(0.85))
assert(OSDIconColorStyle.darkGray.color(on: .light) == Color(white: 0.3))
print("OSD appearance: both system themes, all materials and icon styles, fill colors and levels passed.")
"""
with tempfile.TemporaryDirectory() as directory:
    main = Path(directory) / "main.swift"
    main.write_text(source)
    binary = Path(directory) / "check"
    subprocess.run(["swiftc", str(main), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
