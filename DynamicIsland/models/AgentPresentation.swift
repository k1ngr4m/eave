// SPDX-License-Identifier: GPL-3.0-or-later
// Card ordering and readout behavior adapted from Vorssaint's NotchAgentSupport.
// Copyright (C) 2026 Vorssaint.

import Foundation
import Defaults

enum AgentCard: String, CaseIterable, Identifiable {
    case limits, spend, live, trend, models, projects, activity
    var id: String { rawValue }
    var title: String {
        switch self {
        case .limits: String(localized: "Quota")
        case .spend: String(localized: "Spend")
        case .live: String(localized: "Current tasks")
        case .trend: String(localized: "Trend")
        case .models: String(localized: "Models")
        case .projects: String(localized: "Projects")
        case .activity: String(localized: "Activity")
        }
    }
    var symbol: String {
        switch self {
        case .limits: "gauge.with.dots.needle.33percent"
        case .spend: "dollarsign.circle"
        case .live: "waveform.path.ecg"
        case .trend: "chart.bar.fill"
        case .models: "cpu"
        case .projects: "folder"
        case .activity: "square.grid.3x3.fill"
        }
    }
    var fullWidth: Bool { self == .limits || self == .trend || self == .activity }

    static func ordered(_ saved: [String]) -> [Self] {
        var seen = Set<Self>()
        return (saved.compactMap(Self.init(rawValue:)) + allCases).filter { seen.insert($0).inserted }
    }

    static func moving(_ source: Self, to target: Self, in saved: [String]) -> [String] {
        var order = ordered(saved)
        let from = order.firstIndex(of: source)!
        let to = order.firstIndex(of: target)!
        order.remove(at: from)
        order.insert(source, at: to)
        return order.map(\.rawValue)
    }

    static func rows(order: [String], hidden: [String], wide: Bool) -> [[Self]] {
        var rows: [[Self]] = []
        for card in ordered(order) where !hidden.contains(card.rawValue) {
            if wide, !card.fullWidth, let last = rows.last, last.count == 1, !last[0].fullWidth {
                rows[rows.count - 1].append(card)
            } else { rows.append([card]) }
        }
        return rows
    }
}

enum AgentLimitDisplay: String, CaseIterable, Defaults.Serializable {
    case remaining, used
    var title: String { self == .remaining ? String(localized: "Remaining") : String(localized: "Used") }
    func fraction(_ limit: UsageLimit) -> Double {
        let used = max(0, min(1, limit.fraction))
        return self == .remaining ? 1 - used : used
    }
}

enum AgentLimitFocus: String, CaseIterable, Defaults.Serializable {
    case mostUsed, session, week
    var title: String {
        switch self {
        case .mostUsed: String(localized: "Most used")
        case .session: String(localized: "Session")
        case .week: String(localized: "Week")
        }
    }
    func limit(in snapshot: UsageSnapshot, at now: Date) -> UsageLimit? {
        let candidates: [UsageLimit?] = switch self {
        case .mostUsed: [snapshot.sessionLimit, snapshot.weekLimit]
        case .session: [snapshot.sessionLimit]
        case .week: [snapshot.weekLimit]
        }
        return candidates.compactMap { $0 }.filter { $0.limit > 0 && ($0.resetsAt.map { $0 > now } ?? true) }
            .max { $0.fraction < $1.fraction }
    }
}

enum AgentReadout: String, CaseIterable, Defaults.Serializable {
    case elapsed, tokens, cost, limit
    var title: String {
        switch self {
        case .elapsed: String(localized: "Elapsed time")
        case .tokens: String(localized: "Output tokens")
        case .cost: String(localized: "Spend")
        case .limit: String(localized: "Quota")
        }
    }
    func reading(_ snapshot: UsageSnapshot, started: Date, now: Date,
                 display: AgentLimitDisplay, focus: AgentLimitFocus) -> String {
        let tasks = snapshot.codexDetails?.activeTasks(at: now) ?? []
        switch self {
        case .elapsed: return Self.elapsedText(since: started, at: now)
        case .tokens:
            return tasks.reduce(0) { $0 + $1.totals.outputTokens }
                .formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
        case .cost:
            let amount = tasks.reduce(0) { $0 + $1.totals.costUSD }.formatted(.currency(code: "USD"))
            return (tasks.contains { $0.totals.hasUnpricedModel } ? "≈" : "") + amount
        case .limit:
            guard let limit = focus.limit(in: snapshot, at: now) else { return Self.elapsedText(since: started, at: now) }
            return display.fraction(limit).formatted(.percent.precision(.fractionLength(0)))
        }
    }

    static func elapsedText(since started: Date, at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(started)))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
