"""Run: python3 tests/test_notch_appearance.py (macOS Swift toolchain)."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
palette = (root / 'DynamicIsland/extensions/Color+AccentColor.swift').read_text()
palette = palette.split('extension Color {', 1)[1].split('    /// Returns the accent color', 1)[0]
contrast = (root / 'DynamicIsland/components/OSD/CustomOSDView.swift').read_text()
contrast = contrast.split('enum OSDContrast {', 1)[1].split('#endif', 1)[0]
appearance = (root / 'DynamicIsland/models/NotchAppearance.swift').read_text().replace('import Defaults', '').replace(', Defaults.Serializable', '')
source = appearance + '\nextension Color {' + palette + '}\nenum OSDContrast {' + contrast + '''
func contrast(_ foreground: Color, _ background: Color, _ scheme: ColorScheme) -> Double {
    let a = OSDContrast.luminance(of: foreground, in: scheme)
    let b = OSDContrast.luminance(of: background, in: scheme)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}
assert(NotchAppearance.legacyAppearance(lightMode: true) == .light)
assert(NotchAppearance.legacyAppearance(lightMode: false) == .dark)
for system in [ColorScheme.light, .dark] {
    assert(NotchAppearance.light.colorScheme(for: system) == .light)
    assert(NotchAppearance.dark.colorScheme(for: system) == .dark)
    assert(NotchAppearance.system.colorScheme(for: system) == system)
}
// Resolve repeatedly in both orders: switching must not cache the previous appearance.
for scheme in [ColorScheme.dark, .light, .dark, .light] {
    var environment = EnvironmentValues()
    environment.colorScheme = scheme
    let background = Color.notchBackground.resolve(in: environment)
    assert(abs(background.red - (scheme == .light ? 0.96 : 0)) < 0.01)
    assert(background.opacity == 1)
    assert(contrast(.primary, .notchBackground, scheme) >= 4.5)
    for tint in [Color.white, .yellow, .cyan, .green, .blue, .purple, .red, .black] {
        if scheme == .light {
            assert(contrast(tint.notchReadableTint(), .notchBackground, scheme) >= 4.5)
        } else {
            let actual = tint.notchReadableTint().resolve(in: environment)
            let expected = tint.resolve(in: environment)
            assert(abs(actual.red - expected.red) < 0.005)
            assert(abs(actual.green - expected.green) < 0.005)
            assert(abs(actual.blue - expected.blue) < 0.005)
        }
    }
}
print("Notch appearance: three modes, legacy migration, semantic text contrast and artwork tints passed.")
'''
with tempfile.TemporaryDirectory() as directory:
    main = Path(directory) / 'main.swift'
    main.write_text(source)
    binary = Path(directory) / 'check'
    subprocess.run(['swiftc', str(main), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
