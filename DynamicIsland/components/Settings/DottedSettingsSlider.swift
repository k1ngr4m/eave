import SwiftUI
import AppKit

/// A dotted track with a capsule thumb and an optional inline value.
struct DottedSettingsSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let label: LocalizedStringKey
    let valueText: String?
    var valueLabel: Text? = nil
    var width: CGFloat? = 190
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isEditing = false
    @State private var hapticGate = SliderHapticGate()
    // Same standard-defaults key as Defaults.Keys.enableHaptics.
    @AppStorage("enableHaptics") private var enableHaptics = true

    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool

    private var fraction: Double {
        min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geometry in
                let travel = max(geometry.size.width - 12, 1)
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 6 + travel * fraction)
                    HStack(spacing: 0) {
                        ForEach(0..<15) { index in
                            Circle()
                                .fill(Color.secondary.opacity(0.45))
                                .frame(width: 4, height: 4)
                            if index < 14 { Spacer(minLength: 0) }
                        }
                    }
                    .padding(.horizontal, 4)
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: 10, height: 22)
                        .shadow(color: .blue.opacity(0.18), radius: 2, y: 2)
                        .offset(x: 1 + travel * fraction)
                }
                .frame(height: 34)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    guard isEnabled else { return }
                    isFocused = true
                    if !isEditing {
                        isEditing = true
                        hapticGate = SliderHapticGate()
                        onEditingChanged(true)
                    }
                    let previousValue = value
                    value = Self.snappedValue(
                        fraction: (drag.location.x - 6) / travel, range: range, step: step
                    )
                    if hapticGate.shouldPerform(from: previousValue, to: value,
                                                enabled: enableHaptics, now: ProcessInfo.processInfo.systemUptime) {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                }.onEnded { _ in finishEditing() })
            }
            if valueLabel != nil || valueText != nil {
                (valueLabel ?? Text(valueText ?? ""))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
                    .frame(minWidth: 26)
                    .padding(.trailing, 10)
            }
        }
        .frame(width: width, height: 34)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(isFocused ? 0.7 : 0), lineWidth: 2)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .focusable(isEnabled)
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { adjust(by: -keyboardStep) }
        .onKeyPress(.downArrow) { adjust(by: -keyboardStep) }
        .onKeyPress(.rightArrow) { adjust(by: keyboardStep) }
        .onKeyPress(.upArrow) { adjust(by: keyboardStep) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(valueLabel ?? Text(valueText ?? value.formatted()))
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { finishEditing() }
        }
        .onDisappear { finishEditing() }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: _ = adjust(by: keyboardStep)
            case .decrement: _ = adjust(by: -keyboardStep)
            @unknown default: break
            }
        }
    }

    private var keyboardStep: Double { step ?? (range.upperBound - range.lowerBound) / 100 }

    private func finishEditing() {
        guard isEditing else { return }
        isEditing = false
        onEditingChanged(false)
    }

    private func adjust(by delta: Double) -> KeyPress.Result {
        guard isEnabled else { return .ignored }
        onEditingChanged(true)
        value = Self.snappedValue(
            fraction: (value + delta - range.lowerBound) / (range.upperBound - range.lowerBound),
            range: range, step: step
        )
        onEditingChanged(false)
        return .handled
    }

    static func snappedValue(fraction: Double, range: ClosedRange<Double>, step: Double?) -> Double {
        let raw = range.lowerBound + min(max(fraction, 0), 1) * (range.upperBound - range.lowerBound)
        guard let step else { return raw }
        let snapped = range.lowerBound + ((raw - range.lowerBound) / step).rounded() * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}

/// Keeps existing setting labels, units and commit callbacks around the shared track.
struct SettingsSlider<Label: View>: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double?
    private let onEditingChanged: (Bool) -> Void
    private let label: Label
    private let valueLabel: Text?

    init<V: BinaryFloatingPoint>(
        value: Binding<V>, in range: ClosedRange<V>, step: V? = nil, valueLabel: Text? = nil,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder label: () -> Label
    ) {
        _value = Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = V($0) })
        self.range = Double(range.lowerBound)...Double(range.upperBound)
        self.step = step.map { Double($0) }
        self.onEditingChanged = onEditingChanged
        self.label = label()
        self.valueLabel = valueLabel
    }

    var body: some View {
        HStack(spacing: 12) {
            label
            Spacer(minLength: 12)
            DottedSettingsSlider(value: $value, range: range, step: step,
                                 label: "", valueText: nil,
                                 valueLabel: valueLabel ?? Text(value.formatted(.number.precision(.fractionLength(0...2)))),
                                 onEditingChanged: onEditingChanged)
        }
        .accessibilityValue(valueLabel ?? Text(value.formatted()))
        .accessibilityRepresentation {
            if let step {
                Slider(value: $value, in: range, step: step,
                       onEditingChanged: onEditingChanged) { label }
            } else {
                Slider(value: $value, in: range,
                       onEditingChanged: onEditingChanged) { label }
            }
        }
    }
}

extension SettingsSlider where Label == EmptyView {
    init<V: BinaryFloatingPoint>(
        value: Binding<V>, in range: ClosedRange<V>, step: V? = nil, valueLabel: Text? = nil,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(value: value, in: range, step: step, valueLabel: valueLabel,
                  onEditingChanged: onEditingChanged) { EmptyView() }
    }
}

/// One light tick per changed value, capped during fast or continuous dragging.
struct SliderHapticGate {
    private var lastFeedbackTime = -Double.infinity

    mutating func shouldPerform(from oldValue: Double, to newValue: Double,
                                enabled: Bool, now: TimeInterval) -> Bool {
        guard enabled, oldValue != newValue, now - lastFeedbackTime >= 0.06 else { return false }
        lastFeedbackTime = now
        return true
    }
}
