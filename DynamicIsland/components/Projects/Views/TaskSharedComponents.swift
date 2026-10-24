/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI

// MARK: - Small shared glyphs used by list, gantt, detail and notch views.

extension ProjectColor {
    var color: Color {
        switch self {
        case .blue: return Color(hex: 0x0A84FF)
        case .purple: return Color(hex: 0xBF5AF2)
        case .pink: return Color(hex: 0xFF375F)
        case .red: return Color(hex: 0xFF453A)
        case .orange: return Color(hex: 0xFF9F0A)
        case .yellow: return Color(hex: 0xFFD60A)
        case .green: return Color(hex: 0x30D158)
        case .teal: return Color(hex: 0x40C8E0)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Completion checkbox. Summary parents never render one — completing several
/// tasks with one click is intentionally impossible (PRD 7.4).
struct TaskCheckbox: View {
    let isCompleted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(isCompleted ? Color.green : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(isCompleted ? String(localized: "标记为待办") : String(localized: "标记为已完成"))
        .accessibilityLabel(isCompleted ? String(localized: "已完成") : String(localized: "标记完成"))
    }
}

struct StatusDot: View {
    let status: ProjectTaskStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(status.localizedName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch status {
        case .todo: return Color.secondary.opacity(0.55)
        case .inProgress: return .blue
        case .completed: return .green
        }
    }
}

struct PriorityChip: View {
    let priority: ProjectTaskPriority

    var body: some View {
        if priority != .none {
            Text(priority.localizedName)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(tint.opacity(0.16), in: Capsule())
                .foregroundStyle(tint)
                .accessibilityLabel(String(localized: "优先级") + " " + priority.localizedName)
        } else {
            Text("—")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary.opacity(0.5))
        }
    }

    private var tint: Color {
        switch priority {
        case .none: return .secondary
        case .low: return .gray
        case .medium: return .orange
        case .high: return .red
        }
    }
}

struct ProjectDot: View {
    let colorHex: String
    var size: CGFloat = 9

    var body: some View {
        Circle()
            .fill(ProjectColor.color(forHex: colorHex).color)
            .frame(width: size, height: size)
    }
}

struct DueBadge: View {
    let text: String
    var kind: DueBadgeKind

    enum DueBadgeKind {
        case overdue
        case today
        case future
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(background, in: Capsule())
            .foregroundStyle(foreground)
    }

    private var background: Color {
        switch kind {
        case .overdue: return Color.red.opacity(0.14)
        case .today: return Color.blue.opacity(0.14)
        case .future: return .clear
        }
    }

    private var foreground: Color {
        switch kind {
        case .overdue: return .red
        case .today: return .blue
        case .future: return .secondary
        }
    }
}

/// Due text + badge kind for a task relative to today.
enum DueDisplay {
    case overdue(days: Int)
    case today
    case future(CalendarDate)

    static func resolve(_ task: ProjectTask, today: CalendarDate) -> DueDisplay? {
        guard let due = task.dueDate else { return nil }
        if !task.isCompleted && due < today { return .overdue(days: today.days(since: due)) }
        if due == today { return .today }
        return .future(due)
    }

    var text: String {
        switch self {
        case .overdue(let days):
            return days <= 0 ? String(localized: "今天之前到期") : String(localized: "逾期\(days)天")
        case .today:
            return String(localized: "今天")
        case .future(let date):
            return date.shortDisplayText
        }
    }

    var badgeKind: DueBadge.DueBadgeKind {
        switch self {
        case .overdue: return .overdue
        case .today: return .today
        case .future: return .future
        }
    }
}

/// Availability gates and validation messages shared by forms.
enum ProjectsValidation {
    static func titleError(_ title: String, limit: Int) -> String? {
        let clean = title.trimmedForStorage
        if clean.isEmpty { return String(localized: "标题不能为空") }
        if clean.count > limit { return String(localized: "标题不能超过 \(limit) 个字符") }
        return nil
    }
}
