// SPDX-License-Identifier: GPL-3.0-or-later
// Layout and installed-app mark lookup adapted from Vorssaint's NotchAgentStrip
// and AgentMarks. Copyright (C) 2026 Vorssaint.

import AppKit
import SwiftUI
import Defaults

struct CodexLiveActivity: View {
    let started: Date
    let centerWidth: CGFloat
    let height: CGFloat
    var snapshot = UsageSnapshot()
    var openDetails: () -> Void
    @Default(.agentReadout) private var readout
    @Default(.agentLimitDisplay) private var limitDisplay
    @Default(.agentLimitFocus) private var limitFocus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    private let tint = Color(red: 0.49, green: 0.60, blue: 1)

    private static let mark: NSImage? = {
        for identifier in ["com.openai.codex", "com.openai.chat"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
               let image = Bundle(url: url)?.image(forResource: "chatgptTemplate") {
                return image
            }
        }
        return nil
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = readout.reading(snapshot, started: started, now: context.date,
                                          display: limitDisplay, focus: limitFocus)
            let fontSize = min(16, max(12, height - 16))
            let wingWidth = max(58, (elapsed as NSString).size(withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
            ]).width + 20)
            HStack(spacing: 0) {
                Button(action: openDetails) {
                    Group {
                        if let mark = Self.mark {
                            Image(nsImage: mark).renderingMode(.template).resizable().scaledToFit()
                        } else {
                            Image(systemName: "sparkles").resizable().scaledToFit()
                        }
                    }
                    .frame(width: 20, height: 20)
                    .opacity(breathing && !reduceMotion ? 0.5 : 1)
                    .scaleEffect(breathing && !reduceMotion ? 0.94 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: breathing)
                    .frame(width: wingWidth, height: height, alignment: .leading)
                    .contentShape(Rectangle())
                }
                Color.clear.frame(width: centerWidth)
                Button(action: openDetails) {
                    Text(elapsed)
                        .font(.system(size: fontSize, weight: .medium)).monospacedDigit()
                        .lineLimit(1)
                        .frame(width: wingWidth, height: height, alignment: .trailing)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Codex task running"))
            .accessibilityValue(elapsed)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { openDetails() }
            .help("Open Codex details")
        }
        .onAppear { breathing = true }
    }

}
