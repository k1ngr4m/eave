import SwiftUI

struct DesktopPingSettings: View {
    @ObservedObject private var manager = DesktopPingManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable desktop pings", isOn: $manager.configuration.enabled)
                AccessibilitySettingsPermissionRow(message: "Allows Desktop Pings to detect the trigger key and mouse gestures.")
                if let failure = manager.failure {
                    Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    Button("Try Again") { manager.retry() }
                }
            } footer: {
                Text("Hold the trigger and drag to open the wheel. Release on a signal to send it. Release in the center, right-click, or press Esc to cancel. ⌃⌥P pauses or resumes.")
            }
            Group {
                Section("Trigger") {
                    Picker("Trigger Key", selection: $manager.configuration.trigger) {
                        ForEach(DesktopPingConfiguration.Trigger.allCases, id: \.self) { trigger in
                            Text(trigger.label).tag(trigger)
                        }
                    }
                    Toggle("Send a Ping on Trigger + Click", isOn: $manager.configuration.clickPing)
                    LabeledContent("Drag Threshold") {
                        Slider(value: $manager.configuration.dragThreshold, in: 2...40, step: 1)
                        Text("\(Int(manager.configuration.dragThreshold)) pt").monospacedDigit().frame(width: 52)
                    }
                    Text("The trigger replaces that key’s normal drag action while Desktop Pings is active. Change it or pause to use other apps’ drag shortcuts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Signal and Sound") {
                    LabeledContent("Signal Size") {
                        Slider(value: $manager.configuration.size, in: 60...220, step: 1)
                        Text("\(Int(manager.configuration.size)) pt").monospacedDigit().frame(width: 52)
                    }
                    LabeledContent("Signal Duration") {
                        Slider(value: $manager.configuration.duration, in: 1...8, step: 0.1)
                        Text(manager.configuration.duration, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit().frame(width: 36)
                        Text("seconds")
                    }
                    Toggle("Play desktop sounds", isOn: Binding(
                        get: { !manager.configuration.muted },
                        set: { manager.configuration.muted = !$0 }
                    ))
                    Text("Desktop sounds control ping and emote audio.")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Ping Volume") {
                        Slider(value: $manager.configuration.volume, in: 0...100, step: 1)
                            .disabled(manager.configuration.muted)
                        Text("\(Int(manager.configuration.volume))%").monospacedDigit().frame(width: 40)
                    }
                    Toggle("Play wheel tick sound", isOn: $manager.configuration.tickSound)
                        .disabled(manager.configuration.muted)
                }
                Section {
                    DesktopPingWheelEditor(configuration: $manager.configuration, preview: manager.preview)
                } header: { Text("Signal Wheel") }
                DesktopEmoteSettings(manager: manager)
            }
            .disabled(!manager.configuration.enabled)
        }
        .formStyle(.grouped)
    }

}
