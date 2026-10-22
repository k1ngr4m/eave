import SwiftUI

@main
struct DottedSettingsSliderChecks {
    @MainActor static func main() {
        let range = 100.0...300.0
        for (position, expected) in [(-1.0, 100.0), (0, 100), (0.24, 100), (0.26, 200), (0.5, 200), (0.74, 200), (0.76, 300), (1, 300), (2, 300)] {
            precondition(DottedSettingsSlider.snappedValue(fraction: position, range: range, step: 100) == expected)
        }
        // Also covers zero-centred ranges used by width/height adjustments.
        precondition(DottedSettingsSlider.snappedValue(fraction: 0.5, range: -50...50, step: 1) == 0)
        // Continuous settings must not acquire an implicit step.
        precondition(abs(DottedSettingsSlider.snappedValue(fraction: 0.12345, range: 0...1, step: nil) - 0.12345) < 1e-10)
        precondition(abs(DottedSettingsSlider.snappedValue(fraction: 0.5, range: 0.3...1, step: 0.05) - 0.65) < 1e-10)
        precondition(DottedSettingsSlider.snappedValue(fraction: 0.5, range: 100...10000, step: 100) == 5100)
        precondition(DottedSettingsSlider.snappedValue(fraction: -1, range: -100...100, step: nil) == -100)
        precondition(DottedSettingsSlider.snappedValue(fraction: 2, range: -100...100, step: nil) == 100)
        var haptics = SliderHapticGate()
        precondition(!haptics.shouldPerform(from: 0, to: 0, enabled: true, now: 1))
        precondition(!haptics.shouldPerform(from: 0, to: 1, enabled: false, now: 1))
        precondition(haptics.shouldPerform(from: 0, to: 1, enabled: true, now: 1))
        precondition(!haptics.shouldPerform(from: 1, to: 2, enabled: true, now: 1.03))
        precondition(haptics.shouldPerform(from: 2, to: 1, enabled: true, now: 1.07))
        precondition(!haptics.shouldPerform(from: 1, to: 1, enabled: true, now: 2))
        haptics = SliderHapticGate()
        precondition(haptics.shouldPerform(from: 1, to: 2, enabled: true, now: 2))
        print("PASS: haptic changes, throttle, disabled preference and new drags;")
        print("PASS: slider endpoints, clamping, step boundaries and zero-centred ranges")
    }
}
