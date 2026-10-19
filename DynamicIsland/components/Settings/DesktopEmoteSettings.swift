import SwiftUI
import UniformTypeIdentifiers

struct DesktopEmoteSettings: View {
    @ObservedObject var manager: DesktopPingManager
    @State private var importing = false
    @State private var busy = false
    @State private var importError: String?

    var body: some View {
        Section("Emotes") {
            Toggle("Enable emotes", isOn: $manager.configuration.emote.enabled)
            Group {
                Picker("Emote Trigger", selection: $manager.configuration.emote.trigger) {
                    ForEach(DesktopPingConfiguration.Trigger.allCases, id: \.self) { key in
                        Text(key.label).tag(key).disabled(key == manager.configuration.trigger)
                    }
                }
                if manager.configuration.emote.trigger == manager.configuration.trigger {
                    Text("Choose different trigger keys for pings and emotes. Emote input is disabled while they match.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Toggle("Send an Emote on Trigger + Click", isOn: $manager.configuration.emote.click)
                LabeledContent("Emote Size") {
                    Slider(value: $manager.configuration.emote.size, in: 80...300, step: 1)
                    Text("\(Int(manager.configuration.emote.size)) pt").monospacedDigit().frame(width: 52)
                }
                Toggle("Play emote sounds", isOn: $manager.configuration.emote.sound)
                    .disabled(manager.configuration.muted)
                Text("Emote sounds use the desktop sounds switch and volume.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!manager.configuration.emote.enabled)
        }
        Group {
            Section("Emote Wheel") {
                DesktopPingWheelEditor(configuration: $manager.configuration, preview: manager.previewEmote, emotes: true)
            }
            Section("Your Emotes") {
                HStack {
                    Button("Add Images…") { importing = true }.disabled(busy || manager.configuration.emote.custom.count >= 24)
                    Spacer()
                    Text("\(manager.configuration.emote.custom.count) / 24").foregroundStyle(.secondary)
                    if busy { ProgressView().controlSize(.small) }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg, .gif, .webP], allowsMultipleSelection: true) { result in
                    switch result {
                    case .success(let urls): importImages(urls)
                    case .failure(let error): importError = error.localizedDescription
                    }
                }
                Text("PNG, JPEG, GIF or WebP, up to 8 MB. Animations: up to 5 MB and 1024 × 1024. Images stay on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                if let importError { Text(importError).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                ForEach(manager.configuration.emote.custom) { item in
                    HStack {
                        Text(item.name).lineLimit(1)
                        Spacer()
                        Button { manager.previewEmote(item.id) } label: { Image(systemName: "play.fill") }
                            .accessibilityLabel(Text("Preview Emote"))
                        Button(role: .destructive) {
                            var config = manager.configuration
                            config.emote.custom.removeAll { $0.id == item.id }
                            manager.configuration = config.normalized
                            DesktopEmoteLibrary.remove(item)
                        } label: { Image(systemName: "trash") }
                        .accessibilityLabel(Text("Remove Emote"))
                        .disabled(busy)
                    }
                }
            }
        }
        .disabled(!manager.configuration.emote.enabled)
    }

    private func importImages(_ urls: [URL]) {
        busy = true
        importError = nil
        Task { @MainActor in
            var errors: [String] = []
            for url in urls {
                let existing = manager.configuration.emote.custom
                do {
                    let item = try await Task.detached(priority: .userInitiated) {
                        try DesktopEmoteLibrary.importImage(url, existing: existing)
                    }.value
                    manager.configuration.emote.custom.append(item)
                } catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            importError = errors.isEmpty ? nil : errors.joined(separator: "\n")
            busy = false
        }
    }
}
