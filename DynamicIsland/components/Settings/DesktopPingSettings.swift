import SwiftUI

struct DesktopPingSettings: View {
    @ObservedObject private var manager = DesktopPingManager.shared
    private let directions = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]

    var body: some View {
        Form {
            Section {
                Toggle("Enable Desktop Pings", isOn: $manager.configuration.enabled)
                LabeledContent("Status") { Text(manager.status).foregroundStyle(.secondary) }
                if manager.needsPermission {
                    Button("Open Accessibility Settings") { manager.requestPermission() }
                }
                if let failure = manager.failure {
                    Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    Button("Try Again") { manager.retry() }
                }
                if manager.configuration.enabled {
                    Toggle("Pause Desktop Pings", isOn: $manager.configuration.paused)
                }
            } footer: {
                Text("Hold the trigger and drag to open the wheel. Release on a signal to send it. Release in the center, right-click, or press Esc to cancel. ⌃⌥P pauses or resumes.")
            }
            Section("Trigger") {
                Picker("Trigger Key", selection: $manager.configuration.trigger) {
                    ForEach(DesktopPingConfiguration.Trigger.allCases, id: \.self) { trigger in
                        Text(trigger.label).tag(trigger)
                    }
                }
                Toggle("Send a Ping on Trigger + Click", isOn: $manager.configuration.clickPing)
                if manager.configuration.clickPing {
                    pingPicker("Click Signal", selection: $manager.configuration.clickPingID)
                }
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
                Toggle("Mute Ping Sounds", isOn: $manager.configuration.muted)
                LabeledContent("Ping Volume") {
                    Slider(value: $manager.configuration.volume, in: 0...100, step: 1)
                        .disabled(manager.configuration.muted)
                    Text("\(Int(manager.configuration.volume))%").monospacedDigit().frame(width: 40)
                }
                Toggle("Wheel Tick Sound", isOn: $manager.configuration.tickSound)
            }
            Section {
                ForEach(0..<8, id: \.self) { slot in
                    HStack {
                        Text(directions[slot]).font(.title3).frame(width: 22).accessibilityHidden(true)
                        pingPicker("Slot \(slot + 1)", selection: Binding(
                            get: { manager.configuration.wheel[slot] },
                            set: { manager.configuration.place($0, at: slot) }
                        ))
                        Button { manager.preview(manager.configuration.wheel[slot]) } label: {
                            Image(systemName: "play.fill")
                        }
                        .accessibilityLabel(Text("Preview Signal"))
                        .help(Text("Preview Signal"))
                        .disabled(!manager.configuration.enabled || manager.configuration.paused || manager.needsPermission || manager.failure != nil)
                    }
                }
                Button("Reset Wheel Layout") { manager.configuration.wheel = DesktopPingConfiguration.defaultWheel }
            } header: { Text("Signal Wheel") } footer: {
                Text("Slots run clockwise from the top. Choosing a signal already on the wheel swaps the two slots. Desktop pings remain visible when Eave is hidden from screen capture; share the entire display to include them.")
            }
        }
        .formStyle(.grouped)
    }

    private func pingPicker(_ title: LocalizedStringKey, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Array(DesktopPingConfiguration.pingIDs.enumerated()), id: \.element) { index, id in
                HStack {
                    if let root = Bundle.main.resourceURL,
                       let image = NSImage(contentsOf: root.appendingPathComponent("DesktopPing/textures/\(DesktopPingConfiguration.icons[index]).png")) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 18, height: 18)
                    }
                    Text(LocalizedStringKey(DesktopPingConfiguration.titles[index]))
                }.tag(id)
            }
        }
    }
}
