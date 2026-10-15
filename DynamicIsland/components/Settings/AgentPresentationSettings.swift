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
                    cardButton(card)
                }
            }
            .padding(.vertical, 6)
            .settingsHighlight(id: highlightID("Agent cards"))
            Text("Click to show or hide cards. Drag to reorder. Charts use the full width of the notch.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Display quota as", selection: $limitDisplay) {
                ForEach(AgentLimitDisplay.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            Picker("Quota beside the camera", selection: $limitFocus) {
                ForEach(AgentLimitFocus.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
        Section {
            Toggle("Show Codex activity in the closed notch", isOn: $liveActivity)
                .toggleStyle(.switch)
                .settingsHighlight(id: highlightID("While agents work"))
            if liveActivity {
                Picker("Beside the camera", selection: $readout) {
                    ForEach(AgentReadout.allCases, id: \.self) { Text($0.title).tag($0) }
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
            if !codexEnabled {
                Text("Enable the Codex provider to show its live activity.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("While agents work")
        } footer: {
            Text("Shows running Codex tasks. Click the notch activity to open details. If quota is unavailable, elapsed time is shown.")
        }
    }

    private func cardButton(_ card: AgentCard) -> some View {
        let included = !hiddenCards.contains(card.rawValue)
        return Button {
            if included { hiddenCards.append(card.rawValue) }
            else { hiddenCards.removeAll { $0 == card.rawValue } }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: card.symbol).font(.system(size: 24)).foregroundStyle(included ? Color.accentColor : .secondary)
                Text(card.title).font(.callout.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 96)
            .background(.primary.opacity(included ? 0.05 : 0.025), in: RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topTrailing) {
                Image(systemName: included ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(included ? Color.accentColor : .secondary)
                    .padding(8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
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
