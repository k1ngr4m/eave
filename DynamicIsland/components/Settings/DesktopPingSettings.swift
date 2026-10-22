import SwiftUI

struct DesktopPingSettings: View {
    @ObservedObject private var manager = DesktopPingManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable desktop pings", systemImage: "power", isOn: $manager.configuration.enabled)
            }
            Section {
                AccessibilitySettingsPermissionRow(message: "Allows Desktop Pings to detect the trigger key and mouse gestures.")
                if let failure = manager.failure {
                    Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    Button("Try Again") { manager.retry() }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Hold the trigger and drag to open the wheel. Release on a signal to send it. Release in the center, right-click, or press Esc to cancel. ⌃⌥P pauses or resumes.")
            }
            Group {
                Section("Trigger") {
                    HStack(spacing: 12) {
                        Label("Trigger Key", systemImage: "keyboard").accessibilityHidden(true)
                        Spacer(minLength: 12)
                        Picker(selection: $manager.configuration.trigger) {
                            ForEach(DesktopPingConfiguration.Trigger.allCases, id: \.self) { trigger in
                                Text(trigger.label).tag(trigger)
                            }
                        } label: {
                            Label("Trigger Key", systemImage: "keyboard")
                        }
                            .labelsHidden()
                    }
                    Toggle("Send a Ping on Trigger + Click", systemImage: "keyboard", isOn: $manager.configuration.clickPing)
                    LabeledContent() {
                        SettingsSlider(value: $manager.configuration.dragThreshold, in: 2...40, step: 1, valueLabel: Text("\(Int(manager.configuration.dragThreshold)) pt"))
                    } label: {
                        Label("Drag Threshold", systemImage: "slider.horizontal.3")
                    }
                    Text("The trigger replaces that key’s normal drag action while Desktop Pings is active. Change it or pause to use other apps’ drag shortcuts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Signal and Sound") {
                    LabeledContent() {
                        SettingsSlider(value: $manager.configuration.size, in: 60...220, step: 1, valueLabel: Text("\(Int(manager.configuration.size)) pt"))
                    } label: {
                        Label("Signal Size", systemImage: "arrow.left.and.right")
                    }
                    LabeledContent() {
                        SettingsSlider(value: $manager.configuration.duration, in: 1...8, step: 0.1, valueLabel: Text(manager.configuration.duration, format: .number.precision(.fractionLength(1))) + Text(" ") + Text("seconds"))
                    } label: {
                        Label("Signal Duration", systemImage: "clock")
                    }
                    Toggle("Play desktop sounds", systemImage: "speaker.wave.2", isOn: Binding(
                        get: { !manager.configuration.muted },
                        set: { manager.configuration.muted = !$0 }
                    ))
                    Text("Desktop sounds control ping and emote audio.")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent() {
                        SettingsSlider(value: $manager.configuration.volume, in: 0...100, step: 1, valueLabel: Text("\(Int(manager.configuration.volume))%"))
                            .disabled(manager.configuration.muted)
                    } label: {
                        Label("Ping Volume", systemImage: "speaker.wave.2")
                    }
                    Toggle("Play wheel tick sound", systemImage: "speaker.wave.2", isOn: $manager.configuration.tickSound)
                        .disabled(manager.configuration.muted)
                }
                Section {
                    DesktopPingWheelEditor(configuration: $manager.configuration, preview: manager.preview)
                } header: { Text("Signal Wheel") }
                DesktopEmoteSettings(manager: manager)
            }
            .disabled(!manager.configuration.enabled)
        }

    }

}
