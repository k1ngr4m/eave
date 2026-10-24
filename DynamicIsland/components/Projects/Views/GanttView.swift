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

// MARK: - Scale

enum GanttScale: String, CaseIterable {
    case week   // ~48 pt per day, grouped by week (PRD 9.3)
    case month  // ~16 pt per day, grouped by month

    var dayWidth: CGFloat {
        switch self {
        case .week: return 48
        case .month: return 16
        }
    }

    var localizedName: String {
        switch self {
        case .week: return String(localized: "周")
        case .month: return String(localized: "月")
        }
    }
}

struct GanttDragPreview: Equatable {
    let taskID: UUID
    let start: CalendarDate
    let due: CalendarDate
    let movedDays: Int
    let isResize: Bool
}

/// Toolbar row above the gantt: scale switch, 今天 and 显示全部排期 (PRD 9.2).
struct GanttToolbar: View {
    @ObservedObject var uiState = ProjectsWindowState.shared
    let onToday: () -> Void
    let onShowAll: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $uiState.ganttScale) {
                Text(GanttScale.week.localizedName).tag(GanttScale.week)
                Text(GanttScale.month.localizedName).tag(GanttScale.month)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)
            .accessibilityLabel(String(localized: "时间尺度"))

            Button(String(localized: "今天"), action: onToday)
                .controlSize(.small)
            Button(String(localized: "显示全部排期"), action: onShowAll)
                .controlSize(.small)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

/// Main gantt container: fixed name column, horizontally pannable timeline,
/// project grouping, drag/resize interactions and the unscheduled fold-out.
struct GanttContainerView: View {
    @EnvironmentObject private var vm: ProjectWorkspaceViewModel
    @ObservedObject var uiState = ProjectsWindowState.shared
    @State private var hOffset: CGFloat = 0
    @State private var viewportWidth: CGFloat = 600
    @State private var preview: GanttDragPreview?
    @State private var timelineStart: CalendarDate = .today
    @State private var timelineEnd: CalendarDate = .today

    private let rowHeight: CGFloat = 40
    private let nameColumnWidth: CGFloat = 250

    var body: some View {
        VStack(spacing: 0) {
            GanttToolbar(onToday: scrollToToday, onShowAll: showAllSchedule)
            Divider().opacity(0.5)
            headerRow
            Divider().opacity(0.5)
            ganttBody
            Divider().opacity(0.5)
            unscheduledFoldout
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            computeRange()
            scrollCoordinator.install { delta in pan(delta) }
        }
        .onDisappear {
            scrollCoordinator.uninstall()
        }
        .onChange(of: vm.workspace) { _, _ in computeRange() }
        .onChange(of: uiState.ganttScale) { _, _ in computeRange() }
        .overlay(escapeCatcher)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            preview = nil // deactivate cancels the gesture preview (PRD 9.5)
        }
    }

    // MARK: Timeline geometry

    private var totalDays: Int {
        timelineEnd.days(since: timelineStart) + 1
    }

    private var timelineWidth: CGFloat {
        CGFloat(totalDays) * uiState.ganttScale.dayWidth
    }

    private func offset(of date: CalendarDate) -> CGFloat {
        CGFloat(date.days(since: timelineStart)) * uiState.ganttScale.dayWidth
    }

    private func date(atX x: CGFloat) -> CalendarDate {
        timelineStart.adding(days: Int(round(x / uiState.ganttScale.dayWidth)))
    }

    private func computeRange() {
        let firstWeekday = Calendar.current.firstWeekday
        let today = vm.todayAnchor
        let scheduled = vm.workspace.tasks.compactMap(\.startDate) + vm.workspace.tasks.compactMap(\.dueDate)
        let earliest = (scheduled.min() ?? today).adding(days: -14).startOfWeek(firstWeekday: firstWeekday)
        let latest = ((scheduled.max() ?? today).adding(days: 45))
        // Bounded window: covers normal plans and full-schedule reveal without
        // generating unbounded day views (PRD 9.3, 15.3).
        timelineStart = min(earliest, today.startOfWeek(firstWeekday: firstWeekday).adding(days: -7))
        timelineEnd = max(latest, today.adding(days: 60))
    }

    private func scrollToToday() {
        let todayOffset = offset(of: vm.todayAnchor)
        withAnimation(.easeOut(duration: 0.2)) {
            hOffset = max(0, todayOffset - (viewportWidth - nameColumnWidth) / 2 + uiState.ganttScale.dayWidth * 2)
        }
    }

    private func showAllSchedule() {
        computeRange()
        withAnimation(.easeOut(duration: 0.2)) { hOffset = 0 }
    }

    private var maxHOffset: CGFloat {
        max(0, CGFloat(totalDays) * uiState.ganttScale.dayWidth - (viewportWidth - nameColumnWidth))
    }

    private func pan(_ delta: CGFloat) {
        hOffset = min(max(0, hOffset + delta), maxHOffset)
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text(String(localized: "任务名称"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: nameColumnWidth, height: 44, alignment: .leading)
                .padding(.leading, 16)
            ZStack(alignment: .leading) {
                timelineHeader
                    .offset(x: -hOffset)
            }
            .frame(width: max(0, viewportWidth - nameColumnWidth), height: 44)
            .clipped()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var timelineHeader: some View {
        Canvas { context, size in
            let scale = uiState.ganttScale
            let firstVisibleDay = max(0, Int(floor(hOffset / scale.dayWidth)))
            let lastVisibleDay = min(totalDays - 1, Int(ceil((hOffset + size.width) / scale.dayWidth)))
            guard firstVisibleDay <= lastVisibleDay else { return }

            let calendar = Calendar.current
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "yyyy年M月"

            // Group labels: week row or month row.
            var cursor = firstVisibleDay
            while cursor <= lastVisibleDay {
                let date = timelineStart.adding(days: cursor)
                var groupLength: Int
                if scale == .week {
                    let daysToWeekEnd = (calendar.firstWeekday - date.weekdaySundayFirst + 6) % 7
                    groupLength = daysToWeekEnd + 1
                } else {
                    if let range = calendar.range(of: .day, in: .month, for: date.localNoon),
                       let year = calendar.dateComponents([.year], from: date.localNoon).year,
                       let month = calendar.dateComponents([.month], from: date.localNoon).month,
                       let lastDay = CalendarDate(year: year, month: month, day: range.count) {
                        groupLength = lastDay.days(since: date) + 1
                    } else {
                        groupLength = 1
                    }
                }
                let clamped = min(max(1, groupLength), lastVisibleDay - cursor + 1)
                let x = CGFloat(cursor) * scale.dayWidth
                let width = CGFloat(clamped) * scale.dayWidth
                if x + width > hOffset && x < hOffset + size.width {
                    context.draw(Text(monthFormatter.string(from: date.localNoon))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary),
                        at: CGPoint(x: x + width / 2, y: 10))
                }
                cursor += clamped
            }

            // Day cells + grid.
            for day in firstVisibleDay...lastVisibleDay {
                let date = timelineStart.adding(days: day)
                let x = CGFloat(day) * scale.dayWidth
                let isToday = date == vm.todayAnchor
                let content: String
                if scale == .week {
                    content = "\(date.day)\n\(weekdayText(date))"
                } else {
                    content = "\(date.day)"
                }
                context.draw(Text(content)
                    .font(.system(size: scale == .week ? CGFloat(9) : CGFloat(8)))
                    .foregroundStyle(isToday ? Color.accentColor : Color.secondary),
                    at: CGPoint(x: x + scale.dayWidth / 2, y: 27))
                if day > firstVisibleDay {
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 18))
                    line.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(line, with: .color(Color(nsColor: .separatorColor).opacity(0.25)), lineWidth: 0.5)
                }
            }
        }
        .frame(width: timelineWidth, height: 44)
    }

    private func weekdayText(_ date: CalendarDate) -> String {
        Calendar.current.shortWeekdaySymbols[date.weekdaySundayFirst]
    }

    // MARK: Body

    private var ganttBody: some View {
        GeometryReader { geo in
            let rows = ganttRows()
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { _, row in
                        ganttRow(row, timelineViewportWidth: max(0, geo.size.width - nameColumnWidth))
                    }
                }
            }
            .background(alignment: .topTrailing) {
                weekendShading
                    .frame(width: max(0, geo.size.width - nameColumnWidth), height: geo.size.height)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                todayMarker
                    .frame(width: max(0, geo.size.width - nameColumnWidth))
                    .allowsHitTesting(false)
            }
            .onChange(of: geo.size.width) { _, newValue in viewportWidth = newValue }
            .onAppear { viewportWidth = geo.size.width }
        }
    }

    private var weekendShading: some View {
        Canvas { context, size in
            let scale = uiState.ganttScale
            let firstVisibleDay = max(0, Int(floor(hOffset / scale.dayWidth)))
            let lastVisibleDay = min(totalDays - 1, Int(ceil((hOffset + size.width) / scale.dayWidth)))
            guard firstVisibleDay <= lastVisibleDay else { return }
            for day in firstVisibleDay...lastVisibleDay {
                let date = timelineStart.adding(days: day)
                if date.isWeekend {
                    let x = CGFloat(day) * scale.dayWidth - hOffset
                    let rect = CGRect(x: x, y: 0, width: scale.dayWidth, height: size.height)
                    context.fill(Path(rect), with: .color(Color(nsColor: .quaternarySystemFill).opacity(0.5)))
                }
            }
        }
    }

    private var todayMarker: some View {
        let x = nameColumnWidth + offset(of: vm.todayAnchor) - hOffset
        return Rectangle()
            .fill(Color.accentColor)
            .frame(width: 1.5)
            .offset(x: x)
            .opacity(0.9)
    }

    /// Local AppKit hook translating horizontal trackpad/wheel input into
    /// timeline panning while the gantt is visible; vertical scrolling stays
    /// native on the outer ScrollView (PRD 9.2).
    @State private var scrollCoordinator = GanttScrollCoordinator()

    private var escapeCatcher: some View {
        Button {
            preview = nil // Esc discards the drag preview (PRD 9.5)
        } label: { EmptyView() }
        .keyboardShortcut(.cancelAction)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: Rows

    struct GanttRow: Identifiable {
        enum Kind {
            case taskGroup(ProjectTask, children: [ProjectTask])
            case child(ProjectTask)
            case projectSummary(Project)
            case inboxSummary
        }

        let id: String
        let kind: Kind
    }

    private func ganttRows() -> [GanttRow] {
        var rows: [GanttRow] = []
        let navigationProjectID: UUID? = {
            switch uiState.selection {
            case .project(let id): return id
            default: return nil
            }
        }()

        func appendTasks(projectID: UUID?) {
            let archived = Set(vm.workspace.projects.filter(\.isArchived).map(\.id))
            var topLevel = TaskRules.topLevelTasks(in: vm.workspace.tasks, projectID: projectID)
            if projectID == nil {
                topLevel = topLevel.filter { $0.projectID == nil || !archived.contains($0.projectID!) }
            }
            topLevel = TaskRules.sortTasks(topLevel, by: uiState.sortField)
            for task in topLevel {
                let children = TaskRules.children(of: task.id, in: vm.workspace.tasks)
                rows.append(GanttRow(id: task.id.uuidString,
                                     kind: .taskGroup(task, children: children)))
                if uiState.expandedTaskIDs.contains(task.id) {
                    for child in TaskRules.sortTasks(children, by: .createdAt) {
                        rows.append(GanttRow(id: "child-\(child.id.uuidString)", kind: .child(child)))
                    }
                }
            }
        }

        if let navigationProjectID {
            appendTasks(projectID: navigationProjectID)
        } else if case .allTasks = uiState.selection {
            for project in vm.workspace.projects.filter({ !$0.isArchived }) {
                rows.append(GanttRow(id: "proj-\(project.id.uuidString)", kind: .projectSummary(project)))
                appendTasks(projectID: project.id)
            }
            rows.append(GanttRow(id: "inbox-group", kind: .inboxSummary))
            appendTasks(projectID: nil)
        } else {
            rows.append(GanttRow(id: "inbox-group", kind: .inboxSummary))
            appendTasks(projectID: nil)
        }
        return rows
    }

    @ViewBuilder
    private func ganttRow(_ row: GanttRow, timelineViewportWidth: CGFloat) -> some View {
        switch row.kind {
        case .projectSummary(let project):
            HStack(spacing: 0) {
                projectNameCell(title: project.title, colorHex: project.colorHex)
                timelineCell(timelineViewportWidth) {
                    summaryBar(forTasks: vm.workspace.tasks.filter { $0.projectID == project.id },
                               color: ProjectColor.color(forHex: project.colorHex).color)
                }
            }
            .frame(height: rowHeight)
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
        case .inboxSummary:
            HStack(spacing: 0) {
                projectNameCell(title: String(localized: "收集箱"), colorHex: nil)
                timelineCell(timelineViewportWidth) {
                    summaryBar(forTasks: vm.workspace.tasks.filter { $0.parentTaskID == nil && $0.projectID == nil },
                               color: .secondary)
                }
            }
            .frame(height: rowHeight)
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
        case .taskGroup(let task, let children):
            HStack(spacing: 0) {
                taskNameCell(task, hasChildren: !children.isEmpty, indent: 0)
                timelineCell(timelineViewportWidth) {
                    if children.isEmpty {
                        draggableBar(for: task)
                    } else {
                        summaryBar(forTasks: children, color: .blue,
                                   unscheduledText: children.allSatisfy { $0.startDate == nil && $0.dueDate == nil })
                    }
                }
            }
            .frame(height: rowHeight)
        case .child(let child):
            HStack(spacing: 0) {
                taskNameCell(child, hasChildren: false, indent: 1)
                timelineCell(timelineViewportWidth) {
                    draggableBar(for: child)
                }
            }
            .frame(height: rowHeight)
        }
    }

    /// Positions bar content at `-hOffset` and clips to the timeline viewport,
    /// so the name column stays put while the timeline pans (PRD 9.2).
    @ViewBuilder
    private func timelineCell<Content: View>(_ width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            content()
                .frame(width: timelineWidth, height: rowHeight, alignment: .leading)
                .offset(x: -hOffset)
        }
        .frame(width: width, height: rowHeight, alignment: .leading)
        .clipped()
    }

    private func projectNameCell(title: String, colorHex: String?) -> some View {
        HStack(spacing: 7) {
            if let colorHex {
                ProjectDot(colorHex: colorHex)
            }
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer()
        }
        .frame(width: nameColumnWidth, alignment: .leading)
        .padding(.leading, 12)
    }

    private func taskNameCell(_ task: ProjectTask, hasChildren: Bool, indent: Int) -> some View {
        HStack(spacing: 7) {
            if indent > 0 { Spacer().frame(width: 18) }
            if hasChildren {
                Button { uiState.toggleExpanded(task.id) } label: {
                    Image(systemName: uiState.expandedTaskIDs.contains(task.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "展开子任务"))
            } else {
                Color.clear.frame(width: 10)
            }
            TaskCheckbox(isCompleted: task.isCompleted) {
                vm.toggleCompletion(task.id)
            }
            Text(task.title)
                .font(.system(size: 12, weight: hasChildren ? .semibold : .regular))
                .strikethrough(task.isCompleted, color: .secondary)
                .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
                .lineLimit(1)
            if hasChildren {
                let progress = TaskRules.summaryProgress(taskID: task.id, tasks: vm.workspace.tasks)
                Text("\(progress.completed)/\(progress.total)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if TaskRules.isOverdue(task, today: vm.todayAnchor) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .help(String(localized: "已逾期"))
            }
            Spacer()
        }
        .frame(width: nameColumnWidth, alignment: .leading)
        .padding(.leading, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            uiState.detailTaskID = task.id
            uiState.detailVisible = true
        }
    }

    // MARK: Bars

    @ViewBuilder
    private func draggableBar(for task: ProjectTask) -> some View {
        let scale = uiState.ganttScale
        let isPreviewing = preview?.taskID == task.id
        let start = isPreviewing ? preview!.start : task.startDate
        let due = isPreviewing ? preview!.due : task.dueDate

        if let start, let due {
            let x = offset(of: start)
            let width = max(scale.dayWidth - 4, CGFloat(due.days(since: start) + 1) * scale.dayWidth - 4)
            GanttDraggableBar(task: task,
                              x: x,
                              width: width,
                              scale: scale,
                              deadlineBar: false,
                              isDeadlineOnly: task.startDate == nil,
                              isSelected: uiState.detailTaskID == task.id,
                              preview: isPreviewing ? preview : nil,
                              today: vm.todayAnchor,
                              offset: { offset(of: $0) },
                              date: { date(atX: $0) },
                              hOffset: hOffset,
                              viewportWidth: timelineViewportWidthForDrag,
                              onPan: { pan($0) },
                              onPreview: { preview = $0 },
                              onSelect: {
                                  uiState.detailTaskID = task.id
                                  uiState.detailVisible = true
                              },
                              onCommit: commitDrag)
        } else if let dueOnly = due {
            let x = offset(of: dueOnly)
            GanttDraggableBar(task: task,
                              x: x,
                              width: scale.dayWidth - 4,
                              scale: scale,
                              deadlineBar: true,
                              isDeadlineOnly: true,
                              isSelected: uiState.detailTaskID == task.id,
                              preview: isPreviewing ? preview : nil,
                              today: vm.todayAnchor,
                              offset: { offset(of: $0) },
                              date: { date(atX: $0) },
                              hOffset: hOffset,
                              viewportWidth: timelineViewportWidthForDrag,
                              onPan: { pan($0) },
                              onPreview: { preview = $0 },
                              onSelect: {
                                  uiState.detailTaskID = task.id
                                  uiState.detailVisible = true
                              },
                              onCommit: commitDrag)
        }
    }

    private var timelineViewportWidthForDrag: CGFloat {
        max(0, viewportWidth - nameColumnWidth)
    }

    private func commitDrag(_ taskID: UUID, start: CalendarDate, due: CalendarDate, isResize: Bool) {
        preview = nil
        guard let task = vm.task(taskID) else { return }
        if task.startDate == start && task.dueDate == due {
            return // unchanged gesture leaves no save/undo record (PRD 9.5)
        }
        if task.startDate == nil {
            // Deadline-only task: body moves only the due date (PRD G02);
            // edge extensions follow PRD 9.6.
            if isResize {
                if let oldDue = task.dueDate, start == oldDue {
                    vm.updateTask(taskID, startDate: oldDue, dueDate: due)
                } else if let oldDue = task.dueDate, due == oldDue {
                    vm.updateTask(taskID, startDate: start, dueDate: oldDue)
                } else {
                    vm.updateTask(taskID, startDate: min(start, due), dueDate: max(start, due))
                }
            } else {
                vm.updateTask(taskID, dueDate: due)
            }
            return
        }
        vm.updateTask(taskID, startDate: start, dueDate: due)
    }

    @ViewBuilder
    private func summaryBar(forTasks tasks: [ProjectTask], color: Color, unscheduledText: Bool = false) -> some View {
        if tasks.isEmpty {
            ganttPlaceholderText(String(localized: "暂无任务"))
        } else if let range = TaskRules.scheduledRange(ofTasks: tasks) {
            let scale = uiState.ganttScale
            let x = offset(of: range.lowerBound)
            let width = CGFloat(range.upperBound.days(since: range.lowerBound) + 1) * scale.dayWidth - 4
            let leaves = tasks.filter { $0.parentTaskID == nil }
            let fraction = leaves.isEmpty ? 0 : Double(leaves.filter(\.isCompleted).count) / Double(leaves.count)
            let summaryX = x + 2
            let summaryWidth = max(6, width)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.16))
                    .frame(width: summaryWidth, height: 12)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.75))
                        .frame(width: geo.size.width * fraction, height: 12)
                }
                .frame(width: summaryWidth, height: 12)
            }
            .offset(x: summaryX)
            .help(summaryTooltip(tasks, range: range))
        } else if unscheduledText || tasks.allSatisfy({ $0.startDate == nil && $0.dueDate == nil }) {
            ganttPlaceholderText(String(localized: "未排期"))
        }
    }

    private func ganttPlaceholderText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 8)
    }

    private func summaryTooltip(_ tasks: [ProjectTask], range: ClosedRange<CalendarDate>) -> String {
        let done = tasks.filter(\.isCompleted).count
        var text = "\(range.lowerBound.shortDisplayText) – \(range.upperBound.shortDisplayText) · \(String(localized: "完成 \(done)/\(tasks.count)"))"
        if uiState.hasActiveFilters {
            text += " · " + String(localized: "完整范围（含被筛选隐藏的任务）")
        }
        return text
    }

    // MARK: Unscheduled fold-out (PRD 9.7)

    private var unscheduledFoldout: some View {
        let unscheduled = unscheduledTasksForGantt
        return Group {
            if !unscheduled.isEmpty {
                VStack(spacing: 0) {
                    Divider().opacity(0.5)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            uiState.showsUnscheduledFoldout.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: uiState.showsUnscheduledFoldout ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(String(localized: "待安排 · \(unscheduled.count)"))
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if uiState.showsUnscheduledFoldout {
                        ForEach(unscheduled) { task in
                            HStack(spacing: 10) {
                                TaskCheckbox(isCompleted: task.isCompleted) {
                                    vm.toggleCompletion(task.id)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(task.title)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                    if let parentID = task.parentTaskID, let parent = vm.task(parentID) {
                                        Text(parent.title)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    uiState.detailTaskID = task.id
                                    uiState.detailVisible = true
                                }
                                Spacer()
                                Button(String(localized: "安排日期")) {
                                    uiState.detailTaskID = task.id
                                    uiState.detailVisible = true
                                }
                                .buttonStyle(.link)
                                .font(.system(size: 12))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 5)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
    }

    private var unscheduledTasksForGantt: [ProjectTask] {
        let navigationProjectID: UUID? = {
            switch uiState.selection {
            case .project(let id): return id
            default: return nil
            }
        }()
        var tasks = vm.workspace.tasks.filter { task in
            guard task.startDate == nil, task.dueDate == nil else { return false }
            return task.projectID == navigationProjectID
        }
        if navigationProjectID == nil {
            let archived = Set(vm.workspace.projects.filter(\.isArchived).map(\.id))
            tasks = tasks.filter { $0.projectID == nil || !archived.contains($0.projectID!) }
        }
        return TaskRules.sortTasks(tasks, by: uiState.sortField)
    }
}

// MARK: - Wheel catcher

/// Local scroll-wheel monitor installed only while a gantt view is on screen:
/// horizontal-dominant deltas pan the timeline, everything else passes through.
@MainActor
final class GanttScrollCoordinator {
    private var monitor: Any?
    private var onPan: ((CGFloat) -> Void)?

    func install(onPan: @escaping (CGFloat) -> Void) {
        guard monitor == nil else { return }
        self.onPan = onPan
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  event.window === ProjectsWindowController.shared.window,
                  abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
                  abs(event.scrollingDeltaX) > 0.01 else {
                return event
            }
            self.onPan?(event.scrollingDeltaX)
            return nil
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        onPan = nil
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - Draggable bar

/// One task bar: body drag moves the whole range (duration preserved), edges
/// resize a single endpoint, deadline bars move/extend per PRD 9.6. All state
/// is preview-only until release; Esc / deactivation discards (PRD 9.5).
struct GanttDraggableBar: View {
    let task: ProjectTask
    let x: CGFloat
    let width: CGFloat
    let scale: GanttScale
    let deadlineBar: Bool
    let isDeadlineOnly: Bool
    let isSelected: Bool
    let preview: GanttDragPreview?
    let today: CalendarDate
    let offset: (CalendarDate) -> CGFloat
    let date: (CGFloat) -> CalendarDate
    let hOffset: CGFloat
    let viewportWidth: CGFloat
    let onPan: (CGFloat) -> Void
    let onPreview: (GanttDragPreview?) -> Void
    let onSelect: () -> Void
    let onCommit: (UUID, CalendarDate, CalendarDate, Bool) -> Void

    @State private var activePreview: GanttDragPreview?
    @State private var edgeAutoPanTimer: Timer?

    private var effectivePreview: GanttDragPreview? { activePreview ?? preview }

    private var edgeGrabWidth: CGFloat {
        min(8, max(4, scale.dayWidth / 4))
    }

    var body: some View {
        let displayStart = effectivePreview?.start ?? task.startDate ?? task.dueDate ?? .today
        let displayDue = effectivePreview?.due ?? task.dueDate ?? task.startDate ?? .today
        let barX = deadlineBar ? offset(displayDue) : offset(displayStart)
        let barWidth = deadlineBar
            ? scale.dayWidth - 4
            : max(scale.dayWidth - 4, CGFloat(displayDue.days(since: displayStart) + 1) * scale.dayWidth - 4)
        let isCompleted = task.isCompleted
        let overdue = TaskRules.isOverdue(task, today: today)
        let barColor: Color = isCompleted ? .green : (overdue ? .red : .blue)
        let clipped = barX < hOffset || barX + barWidth > hOffset + viewportWidth

        return RoundedRectangle(cornerRadius: 4)
            .fill(barColor.opacity(isCompleted ? 0.5 : 0.85))
            .frame(width: max(6, barWidth), height: 18)
            .overlay(alignment: .leading) {
                if deadlineBar {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.white)
                        .padding(.leading, 3)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .leading) {
                if clipped {
                    Image(systemName: "chevron.compact.left")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(barColor)
                        .offset(x: -8)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .trailing) {
                if clipped {
                    Image(systemName: "chevron.compact.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(barColor)
                        .offset(x: 8)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if effectivePreview != nil {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white, lineWidth: 1.5)
                } else if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.6), lineWidth: 1.2)
                }
            }
            .overlay {
                if overdue && !isCompleted {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 2)
                        .allowsHitTesting(false)
                }
            }
            .offset(x: barX + 2)
            .contentShape(Rectangle().inset(by: -5))
            .help(tooltip)
            .onTapGesture(perform: onSelect)
            .gesture(dragGesture)
            .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.85), value: barX)
            .onAppear { activePreview = nil }
            .onDisappear {
                edgeAutoPanTimer?.invalidate()
                edgeAutoPanTimer = nil
                activePreview = nil
            }
    }

    private var tooltip: String {
        var parts: [String] = [task.title]
        if let s = task.startDate, let d = task.dueDate {
            parts.append("\(s.shortDisplayText) – \(d.shortDisplayText)")
            parts.append(String(localized: "\(d.days(since: s) + 1) 天"))
        } else if let d = task.dueDate {
            parts.append(String(localized: "截止 \(d.shortDisplayText)"))
        } else if let s = task.startDate {
            parts.append(String(localized: "开始 \(s.shortDisplayText)"))
        }
        parts.append(task.status.localizedName)
        if TaskRules.isOverdue(task, today: today) {
            parts.append(String(localized: "已逾期"))
        }
        return parts.joined(separator: " · ")
    }

    private func cleanup() {
        edgeAutoPanTimer?.invalidate()
        edgeAutoPanTimer = nil
        activePreview = nil
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                let grabOffset = value.startLocation.x
                let edgeWidth = edgeGrabWidth

                if isDeadlineOnly {
                    handleDeadlineDrag(grabOffset: grabOffset, value: value)
                } else if task.startDate != nil && grabOffset <= edgeWidth {
                    resizeLeading(value: value)
                } else if task.startDate != nil && grabOffset >= width - edgeWidth {
                    resizeTrailing(value: value)
                } else {
                    moveWholeBar(value: value)
                }
                autoPanIfNeeded(value: value)
            }
            .onEnded { _ in
                guard let final = activePreview else {
                    cleanup()
                    return
                }
                activePreview = nil
                onPreview(nil)
                onCommit(task.id, final.start, final.due, final.isResize)
            }
    }

    /// Preview dates during a body move; snap to whole calendar days.
    private func moveWholeBar(value: DragGesture.Value) {
        let anchorDate = task.startDate ?? task.dueDate!
        let duration = (task.dueDate?.days(since: anchorDate) ?? 0)
        let originalGrabDate = date(offset(anchorDate) + value.startLocation.x)
        let currentGrabDate = date(offset(anchorDate) + value.startLocation.x + value.translation.width)
        let movedDays = currentGrabDate.days(since: originalGrabDate)
        guard movedDays != 0 else {
            activePreview = nil
            return
        }
        let newStart = anchorDate.adding(days: movedDays)
        let newDue = newStart.adding(days: duration)
        activePreview = GanttDragPreview(taskID: task.id, start: newStart, due: newDue,
                                         movedDays: movedDays, isResize: false)
    }

    private func resizeLeading(value: DragGesture.Value) {
        let anchorDate = task.startDate!
        let due = task.dueDate ?? anchorDate
        let originalGrabDate = date(offset(anchorDate) + value.startLocation.x)
        let currentGrabDate = date(offset(anchorDate) + value.startLocation.x + value.translation.width)
        let newStart = min(currentGrabDate, due)
        guard newStart != task.startDate else {
            activePreview = nil
            return
        }
        activePreview = GanttDragPreview(taskID: task.id, start: newStart, due: due,
                                         movedDays: newStart.days(since: originalGrabDate), isResize: true)
    }

    private func resizeTrailing(value: DragGesture.Value) {
        let start = task.startDate!
        let anchorDate = task.dueDate ?? start
        let originalGrabDate = date(offset(anchorDate) + value.startLocation.x)
        let currentGrabDate = date(offset(anchorDate) + value.startLocation.x + value.translation.width)
        let newDue = max(currentGrabDate, start)
        guard newDue != task.dueDate else {
            activePreview = nil
            return
        }
        activePreview = GanttDragPreview(taskID: task.id, start: start, due: newDue,
                                         movedDays: newDue.days(since: originalGrabDate), isResize: true)
    }

    /// Deadline-only bar: body moves the due date; left edge extends the start
    /// forward (keeps due); right edge pushes due (old due becomes start, PRD 9.6).
    private func handleDeadlineDrag(grabOffset: CGFloat, value: DragGesture.Value) {
        guard let due = task.dueDate else { return }
        if grabOffset <= edgeGrabWidth {
            let currentGrabDate = date(offset(due) + value.startLocation.x + value.translation.width)
            let newStart = min(currentGrabDate, due)
            guard newStart != due else {
                activePreview = nil
                return
            }
            activePreview = GanttDragPreview(taskID: task.id, start: newStart, due: due,
                                             movedDays: newStart.days(since: due), isResize: true)
        } else if grabOffset >= width - edgeGrabWidth {
            let currentGrabDate = date(offset(due) + value.startLocation.x + value.translation.width)
            let newDue = max(currentGrabDate, due)
            guard newDue != due else {
                activePreview = nil
                return
            }
            activePreview = GanttDragPreview(taskID: task.id, start: due, due: newDue,
                                             movedDays: newDue.days(since: due), isResize: true)
        } else {
            let originalGrabDate = date(offset(due) + value.startLocation.x)
            let currentGrabDate = date(offset(due) + value.startLocation.x + value.translation.width)
            let movedDays = currentGrabDate.days(since: originalGrabDate)
            guard movedDays != 0 else {
                activePreview = nil
                return
            }
            let newDue = due.adding(days: movedDays)
            // Body move keeps the start empty; preview positions off the due.
            activePreview = GanttDragPreview(taskID: task.id, start: newDue, due: newDue,
                                             movedDays: movedDays, isResize: false)
        }
    }

    /// Pans the timeline when dragging near either viewport edge, so targets
    /// outside the current viewport are reachable (PRD 9.5).
    private func autoPanIfNeeded(value: DragGesture.Value) {
        let edgeZone: CGFloat = 36
        let localX = value.location.x + (offset(task.startDate ?? task.dueDate ?? .today) - hOffset)
        var delta: CGFloat = 0
        if localX < edgeZone {
            delta = -8
        } else if localX > viewportWidth - edgeZone {
            delta = 8
        }
        if delta != 0 {
            if edgeAutoPanTimer == nil {
                onPan(delta)
                let panCallback = onPan
                edgeAutoPanTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                    Task { @MainActor in
                        panCallback(delta)
                    }
                }
            }
        } else if edgeAutoPanTimer != nil {
            edgeAutoPanTimer?.invalidate()
            edgeAutoPanTimer = nil
        }
    }
}
