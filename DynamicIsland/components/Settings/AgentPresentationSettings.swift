// SPDX-License-Identifier: GPL-3.0-or-later
// Card selection and work preview adapted from Vorssaint's NotchAgentsSettings.
// Copyright (C) 2026 Vorssaint.

import SwiftUI
import Defaults

struct AgentPresentationSettings: View {
    var highlightID: (String) -> String
    @Default(.agentCardOrder) private var cardOrder
    @Default(.agentHiddenCards) private var hiddenCards
    @Default(.agentReadout) private var readout
    @Default(.agentLimitDisplay) private var limitDisplay
    @Default(.agentLimitFocus) private var limitFocus
    @Default(.showCodexLiveActivity) private var liveActivity
    @Default(.enableCodexProvider) private var codexEnabled
    @State private var previewStarted = Date().addingTimeInterval(-72)
    private var cards: [AgentCard] { AgentCard.ordered(cardOrder) }

    var body: some View {
        Section("Agent cards") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(cards) { card in
                    cardSelection(card)
                }
            }
            .padding(.vertical, 6)
            .settingsHighlight(id: highlightID("Agent cards"))
            Text("Click to show or hide cards. Drag to reorder. Charts use the full width of the notch.")
                .font(.caption).foregroundStyle(.secondary)
            Picker(selection: $limitDisplay) {
                ForEach(AgentLimitDisplay.allCases, id: \.self) { Text($0.title).tag($0) }
            } label: {
                Label("Display quota as", systemImage: "display")
            }.pickerStyle(.segmented)
            HStack(spacing: 12) {
                Label("Quota beside the camera", systemImage: "camera").accessibilityHidden(true)
                Spacer(minLength: 12)
                Picker(selection: $limitFocus) {
                    ForEach(AgentLimitFocus.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Label("Quota beside the camera", systemImage: "camera")
                }
                    .labelsHidden()
            }
        }
        Section {
            Toggle("Show Codex activity in the closed notch", systemImage: "power", isOn: $liveActivity)
                .disabled(!codexEnabled)
                .settingsHighlight(id: highlightID("While agents work"))
            Group {
                HStack(spacing: 12) {
                    Label("Beside the camera", systemImage: "camera").accessibilityHidden(true)
                    Spacer(minLength: 12)
                    Picker(selection: $readout) {
                        ForEach(AgentReadout.allCases, id: \.self) { Text($0.title).tag($0) }
                    } label: {
                        Label("Beside the camera", systemImage: "camera")
                    }
                        .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 6) {
                    CodexLiveActivity(started: previewStarted, centerWidth: 64, height: 30,
                                      snapshot: previewSnapshot, openDetails: {})
                        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
                        .fixedSize()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    Text("Example preview").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .disabled(!liveActivity || !codexEnabled)
            if !codexEnabled {
                Text("Enable the Codex provider to show its live activity.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Label("While agents work", systemImage: "slider.horizontal.3")
        } footer: {
            Text("Shows running Codex tasks. Click the notch activity to open details. If quota is unavailable, it is marked as unavailable.")
        }
    }

    private func cardSelection(_ card: AgentCard) -> some View {
        let included = !hiddenCards.contains(card.rawValue)
        return VStack(spacing: 8) {
            Image(systemName: card.symbol)
                .font(.system(size: 24))
                .foregroundStyle(included ? Color.accentColor : .secondary)
                .frame(height: 60)
                .accessibilityHidden(true)
            Toggle(isOn: Binding(
                get: { !hiddenCards.contains(card.rawValue) },
                set: { shown in
                    hiddenCards.removeAll { $0 == card.rawValue }
                    if !shown { hiddenCards.append(card.rawValue) }
                }
            )) { Text(card.title) }
            .toggleStyle(.checkbox)
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        .contentShape(Rectangle())
        .draggable("eave-agent-card:" + card.rawValue)
        .dropDestination(for: String.self) { items, _ in
            guard items.count == 1,
                  let source = cards.first(where: { "eave-agent-card:" + $0.rawValue == items[0] }) else { return false }
            withAnimation { cardOrder = AgentCard.moving(source, to: card, in: cardOrder) }
            return true
        }
        .accessibilityLabel(card.title)
        .accessibilityValue(included ? String(localized: "Shown") : String(localized: "Hidden"))
        .accessibilityAction(named: Text("Move Up")) { move(card, by: -1) }
        .accessibilityAction(named: Text("Move Down")) { move(card, by: 1) }
        .contextMenu {
            Button("Move Up") { move(card, by: -1) }.disabled(cards.first == card)
            Button("Move Down") { move(card, by: 1) }.disabled(cards.last == card)
        }
    }

    private func move(_ card: AgentCard, by offset: Int) {
        guard let index = cards.firstIndex(of: card), cards.indices.contains(index + offset) else { return }
        withAnimation { cardOrder = AgentCard.moving(card, to: cards[index + offset], in: cardOrder) }
    }

    private var previewSnapshot: UsageSnapshot {
        var snapshot = UsageSnapshot()
        var details = CodexUsageDetails()
        details.tasks = [CodexLiveTask(id: "preview", started: previewStarted, lastActivity: .now, model: "", project: "",
                                      totals: UsageTotals(outputTokens: 20_000, costUSD: 4.56))]
        snapshot.codexDetails = details
        snapshot.sessionLimit = UsageLimit(used: 35, limit: 100)
        snapshot.weekLimit = UsageLimit(used: 60, limit: 100)
        return snapshot
    }
}
