/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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
import Defaults
import EventKit

// MARK: - Shared auto-scroll helpers

/// Partition events into all-day and timed groups.
func partitionEvents(_ events: [EventModel]) -> (allDay: [EventModel], timed: [EventModel]) {
    (events.filter { $0.isAllDay }, events.filter { !$0.isAllDay })
}

/// Determine which timed event to scroll to, based on a reference time.
/// For today, pass Date() to find in-progress/upcoming events.
/// For other dates, pass startOfDay to scroll to the first event of that day.
func scrollTargetForTimedEvents(timed: [EventModel], referenceTime: Date) -> EventModel? {
    // Prefer an event that carries a conference (Join Meeting) link and is
    // currently active, so its Join button is scrolled into view (#566 feedback:
    // all-day events used to push these out of the visible area).
    let activeConference = timed.first(where: { event in
        guard event.conferenceURL != nil else { return false }
        if event.type.isReminder {
            return event.start <= referenceTime && referenceTime < event.start.addingTimeInterval(3600)
        }
        return event.start <= referenceTime && event.end > referenceTime
    })
    let inProgress = timed.first(where: { event in
        if event.type.isReminder {
            // Reminders are point-in-time; treat as "in progress" only within 1h of start
            return event.start <= referenceTime && referenceTime < event.start.addingTimeInterval(3600)
        }
        return event.start <= referenceTime && event.end > referenceTime
    })
    let nextUpcoming = timed.first(where: { $0.start > referenceTime })
    let lastTimed = timed.last
    return activeConference ?? inProgress ?? nextUpcoming ?? lastTimed
}

/// Reference time for auto-scroll: current time for today, startOfDay for past/future days.
func scrollReferenceTime(for date: Date) -> Date {
    Calendar.current.isDateInToday(date) ? Date() : Calendar.current.startOfDay(for: date)
}

// MARK: - Compact all-day events strip

/// Shared layout metrics for the all-day events strip.
///
/// The strip height and the space reserved for it in the timed-events list must
/// stay in sync across `AllDayEventsStrip` and `EventListView`. Centralising the values here avoids the hardcoded
/// `28` / `3` / `41` / `30` duplicated in multiple views (#566 review).
private enum AllDayStripMetrics {
    /// Height of the horizontal chip row inside `AllDayEventsStrip`.
    static let chipRowHeight: CGFloat = 28
    /// Vertical padding applied around the chips and the strip content.
    static let verticalPadding: CGFloat = 3
    /// Top inset pushed onto the timed `List` so `scrollTo(.top)` lands the
    /// target event fully below the floating all-day overlay
    /// (chip row + 1pt divider + 1pt margin ≈ 30pt). Shared by `EventListView`
    /// so the list reserves exactly the same space.
    /// (#566 review: de-duplicate the hardcoded 28/3/41/30)
    static let listTopInset: CGFloat = 30
}

/// Horizontal, single-row strip of all-day events.
///
/// The Dynamic Island calendar panel is height-constrained (`CalendarView` is
/// capped at a fixed height). The previous design stacked one full row per
/// all-day event in a pinned top section, so two all-day events could consume
/// the entire panel and leave no room for the timed-events scroll area below
/// (#566 follow-up). This strip keeps the all-day section at a constant
/// single-row height regardless of how many all-day events exist — extra
/// events scroll horizontally within the strip instead of growing vertically.
private struct AllDayEventsStrip: View {
    @Environment(\.openURL) private var openURL
    let events: [EventModel]
    var onToggleReminder: ((String, Bool) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(events) { event in
                        allDayChip(event)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, AllDayStripMetrics.verticalPadding)
            }
            .frame(height: AllDayStripMetrics.chipRowHeight)
            .clipped()

            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 4)
        }
    }

    private func allDayChip(_ event: EventModel) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(event.calendar.color))
                .frame(width: 8, height: 8)

            Text(event.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(Color.primary)
                .lineLimit(1)

            if event.isAllDay {
                Text("All-day")
                    .font(.caption2)
                    .foregroundColor(Color.secondary)
                    .lineLimit(1)
            }

            if event.type.isReminder, let onToggleReminder {
                reminderToggle(for: event, using: onToggleReminder)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, AllDayStripMetrics.verticalPadding)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
        .contentShape(Capsule())
        .onTapGesture {
            if let url = event.calendarAppURL() {
                openURL(url)
            }
        }
    }

    private func reminderToggle(for event: EventModel, using onToggleReminder: @escaping (String, Bool) -> Void) -> some View {
        let isCompleted: Bool
        if case .reminder(let completed) = event.type {
            isCompleted = completed
        } else {
            isCompleted = false
        }
        return ReminderToggle(
            isOn: Binding(
                get: { isCompleted },
                set: { newValue in onToggleReminder(event.id, newValue) }
            ),
            color: Color(event.calendar.color)
        )
    }
}

struct Config: Equatable {
    var past: Int = 7
    var future: Int = 14
    var steps: Int = 1
    var spacing: CGFloat = 0
    var showsText: Bool = true
    var offset: Int = 2
}

/// Reports the measured width of a single date cell, used to translate a
/// mouse drag (in points) into a scroll-position step.
private struct CellWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct WheelPicker: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int?
    @State private var haptics: Bool = false
    @State private var byClick: Bool = false
    /// Tracks a mouse press-drag so an external mouse can scrub dates like a
    /// trackpad two-finger scroll (macOS ScrollView doesn't pan on mouse drag).
    @State private var dragAnchorPos: Int? = nil
    @State private var measuredCellWidth: CGFloat = 40
    let config: Config

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: config.spacing) {
                let spacerNum = config.offset
                let dateCount = totalDateItems()
                let totalItems = dateCount + 2 * spacerNum
                ForEach(0..<totalItems, id: \.self) { index in
                    if index < spacerNum || index >= spacerNum + dateCount {
                        Spacer()
                            .frame(width: 24, height: 24)
                            .id(index)
                    } else {
                        let date = dateForItemIndex(index: index, spacerNum: spacerNum)
                        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        dateButton(date: date, isSelected: isSelected, id: index) {
                            selectedDate = date
                            byClick = true
                            withAnimation {
                                scrollPosition = index
                            }
                            if Defaults[.enableHaptics] {
                                haptics.toggle()
                            }
                        }
                    }
                }
            }
            .frame(height: 50)
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .safeAreaPadding(.horizontal)
        .sensoryFeedback(.alignment, trigger: haptics)
        .onChange(of: scrollPosition) { _, newValue in
            if !byClick {
                handleScrollChange(newValue: newValue, config: config)
            } else {
                byClick = false
            }
        }
        .onAppear {
            scrollToToday(config: config)
        }
        .onChange(of: selectedDate) { _, newValue in
            let targetIndex = indexForDate(newValue)
            if scrollPosition != targetIndex {
                byClick = true
                withAnimation {
                    scrollPosition = targetIndex
                }
            }
        }
        .onPreferenceChange(CellWidthKey.self) { measuredCellWidth = $0 }
        // Mouse press-drag scrubs dates (trackpad two-finger scroll still works
        // natively — that arrives as a scroll event, not a drag gesture, so the
        // two never conflict). Steps = drag points / measured cell width.
        // `.simultaneousGesture` (not `.gesture`) so the drag runs alongside the
        // strip's own gestures instead of swallowing the date-cell taps.
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if dragAnchorPos == nil { dragAnchorPos = scrollPosition }
                    guard let start = dragAnchorPos, measuredCellWidth > 1 else { return }
                    let steps = Int((-value.translation.width / measuredCellWidth).rounded())
                    let spacerNum = config.offset
                    let totalItems = totalDateItems() + 2 * spacerNum
                    let newPos = min(max(spacerNum, start + steps), totalItems - 1)
                    if newPos != scrollPosition {
                        withTransaction(Transaction(animation: nil)) {
                            scrollPosition = newPos
                        }
                    }
                }
                .onEnded { _ in
                    dragAnchorPos = nil
                }
        )
    }

    private func dateButton(date: Date, isSelected: Bool, id: Int, onClick: @escaping () -> Void) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        return Button(action: onClick) {
            VStack(spacing: 8) {
                dayText(date: dateToString(for: date), isToday: isToday, isSelected: isSelected)
                dateCircle(date: date, isToday: isToday, isSelected: isSelected)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.effectiveAccentBackground : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .id(id)
        .background(GeometryReader { geo in
            Color.clear.preference(key: CellWidthKey.self, value: geo.size.width)
        })
    }

    private func dayText(date: String, isToday: Bool, isSelected: Bool) -> some View {
        Text(date)
            .font(.caption)
            .foregroundColor(isSelected ? .primary : .secondary)
    }

    private func dateCircle(date: Date, isToday: Bool, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isToday ? Color.effectiveAccent : .clear)
                .frame(width: 20, height: 20)
            Text(date.date)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(isToday ? .white : .primary)
        }
    }

    func handleScrollChange(newValue: Int?, config: Config) {
        guard let newIndex = newValue else { return }
        let spacerNum = config.offset
        let dateCount = totalDateItems()
        guard (spacerNum..<(spacerNum + dateCount)).contains(newIndex) else { return }
        let date = dateForItemIndex(index: newIndex, spacerNum: spacerNum)
        if !Calendar.current.isDate(date, inSameDayAs: selectedDate) {
            selectedDate = date
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }

    private func scrollToToday(config: Config) {
        let today = Date()
        byClick = true
        scrollPosition = indexForDate(today)
        selectedDate = today
    }

    private func indexForDate(_ date: Date) -> Int {
        let spacerNum = config.offset
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startDate = cal.startOfDay(for: cal.date(byAdding: .day, value: -config.past, to: today) ?? today)
        let target = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: startDate, to: target).day ?? 0
        let stepIndex = max(0, min(days / max(config.steps, 1), totalDateItems() - 1))
        return spacerNum + stepIndex
    }

    private func dateForItemIndex(index: Int, spacerNum: Int) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startDate = cal.date(byAdding: .day, value: -config.past, to: today) ?? today
        let stepIndex = index - spacerNum
        return cal.date(byAdding: .day, value: stepIndex * max(config.steps, 1), to: startDate) ?? today
    }

    private func totalDateItems() -> Int {
        let range = config.past + config.future
        let step = max(config.steps, 1)
        return Int(ceil(Double(range) / Double(step))) + 1
    }

    private func dateToString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}

struct CalendarView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()
    @State private var dateExpanded = false
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @Default(.hideCompletedReminders) private var hideCompletedReminders

    var body: some View {
        VStack(spacing: 0) {
            // Compact-by-default date header: when collapsed it shows a single
            // small "weekday, month day" line (~20pt) so the event list below
            // keeps almost the entire 120pt panel. Hovering the header expands
            // the horizontal date-scroll strip (with edge-fade shadows) — the
            // shadows therefore appear exactly when it is scrollable, matching
            // the maintainer's review #1 intent (not permanently drawn).
            HStack(alignment: .center, spacing: 8) {
                // Left label: one compact line when collapsed; month + year when expanded.
                VStack(alignment: .leading, spacing: 1) {
                    if dateExpanded {
                        Text(selectedDate.formatted(.dateTime.month(.abbreviated)))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(Color.primary)
                        Text(selectedDate.formatted(.dateTime.year()))
                            .font(.caption)
                            .fontWeight(.regular)
                            .foregroundColor(Color.secondary)
                    } else {
                        Text(selectedDate.formatted(.dateTime.weekday(.abbreviated))
                             + ", " + selectedDate.formatted(.dateTime.month(.abbreviated))
                             + " " + selectedDate.formatted(.dateTime.day()))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Color.primary)
                    }
                }
                .frame(width: 72, alignment: .leading)

                ZStack {
                    WheelPicker(selectedDate: $selectedDate, config: Config())
                        .frame(maxWidth: .infinity)
                    // Edge fades indicating the date strip is horizontally
                    // scrollable. Subtle (0.45) so they hint without hiding text.
                    LinearGradient(colors: [Color.notchBackground.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 16)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LinearGradient(colors: [.clear, Color.notchBackground.opacity(0.45)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 16)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                // Use the WheelPicker's natural height (50pt) when expanded so its
                // date cells are never clipped top/bottom. Collapsed = 0 height.
                .frame(height: dateExpanded ? 50 : 0)
                .opacity(dateExpanded ? 1 : 0)
                .allowsHitTesting(dateExpanded)
                .clipped()
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .contentShape(Rectangle())
            .onHover { inside in
                withAnimation(.easeInOut(duration: 0.18)) {
                    dateExpanded = inside
                }
            }

            let filteredEvents = EventListView.filteredEvents(
                events: calendarManager.events,
                hideCompletedReminders: hideCompletedReminders,
                hideAllDayEvents: hideAllDayEvents
            )
            if filteredEvents.isEmpty {
                // Centre it in the space left under the header rather than
                // hanging it off the header with all the slack below.
                EmptyEventsView(selectedDate: selectedDate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EventListView(events: calendarManager.events, selectedDate: selectedDate)
            }
        }
        .listRowBackground(Color.clear)
        // Restore the original expanded-notch window height (120pt). Bumping this
        // to 158 grew the whole Dynamic Island window and distorted the music
        // player's internal spacing — both flagged in review #2. The internal
        // wins (all-day floating strip + single-line title) remain, so more timed
        // events are visible at 120 than before, but we no longer enlarge the
        // window or touch the music player's layout.
        .frame(height: 120)
        .onChange(of: selectedDate) {
            Task {
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
        .onChange(of: vm.notchState) { _, _ in
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
        .onAppear {
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
    }
}

/// Half-open day intervals also keep midnight-ending events off the following day.
enum CalendarPageDates {
    static func contains(start: Date, end: Date, on day: Date, calendar: Calendar = .current) -> Bool {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return false }
        return start < interval.end && (end > interval.start || (start >= interval.start && start == end))
    }

    static func upcomingRange(from now: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 7, to: start)!)
    }

    static func upcoming(_ events: [EventModel], now: Date, calendar: Calendar = .current) -> [EventModel] {
        let range = upcomingRange(from: now, calendar: calendar)
        return events.filter { $0.start < range.end && ($0.end > now || $0.start >= now) }
            .sorted { $0.start < $1.start }
    }

    static func spansDays(start: Date, end: Date, allDay: Bool, calendar: Calendar = .current) -> Bool {
        !calendar.isDate(start, inSameDayAs: max(start, allDay ? end.addingTimeInterval(-1) : end))
    }

    static func monthRange(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let month = calendar.dateInterval(of: .month, for: date)!
        let start = calendar.dateInterval(of: .weekOfYear, for: month.start)!.start
        let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end)!
        let end = calendar.dateInterval(of: .weekOfYear, for: lastDay)!.end
        return DateInterval(start: start, end: end)
    }

    static func days(in interval: DateInterval, calendar: Calendar = .current) -> [Date] {
        var days: [Date] = []
        var day = interval.start
        while day < interval.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
}

struct StandaloneCalendarView: View {
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Binding var selectedDate: Date
    @State private var showingMonth = false
    @State private var loadedDate: Date?
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @Default(.hideCompletedReminders) private var hideCompletedReminders

    private let calendar = Calendar.current
    private var visibleEvents: [EventModel] {
        EventListView.filteredEvents(events: calendarManager.monthEvents,
                                     hideCompletedReminders: hideCompletedReminders,
                                     hideAllDayEvents: hideAllDayEvents)
    }
    private func agendaEvents(now: Date) -> [EventModel] {
        if coordinator.calendarShowsWeek {
            return CalendarPageDates.upcoming(visibleEvents, now: now)
        }
        return visibleEvents.filter { CalendarPageDates.contains(start: $0.start, end: $0.end, on: selectedDate) }
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.height >= 280 && geometry.size.width >= 420
            VStack(spacing: 10) {
                toolbar(wide: wide)
                if calendarManager.hasCalendarAccess || calendarManager.hasReminderAccess {
                    if wide {
                        HStack(alignment: .top, spacing: 16) {
                            monthGrid.frame(width: 220)
                            Divider()
                            agenda
                        }
                    } else if showingMonth {
                        monthGrid
                    } else {
                        weekStrip
                        agenda
                    }
                } else {
                    permissionCard
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: max(130, calendarOpenNotchSize().height - max(24, vm.effectiveClosedNotchHeight) - 36))
        .task(id: selectedDate) {
            let date = selectedDate
            loadedDate = nil
            await calendarManager.reloadCalendarAndReminderLists()
            await calendarManager.updateCurrentDate(date)
            if !Task.isCancelled { loadedDate = date }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await calendarManager.reloadCalendarAndReminderLists()
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
        .onHover { vm.isHoveringCalendar = $0 }
        .onDisappear { vm.isHoveringCalendar = false }
        .background {
            if showingMonth {
                Button("Back") { showingMonth = false }
                    .keyboardShortcut(.cancelAction)
                    .hidden()
            }
        }
    }

    private func toolbar(wide: Bool) -> some View {
        HStack {
            Button { if !wide { showingMonth.toggle() } } label: {
                HStack(spacing: 5) {
                    Text(selectedDate, format: .dateTime.year().month(.wide))
                    if !wide { Image(systemName: showingMonth ? "chevron.up" : "chevron.down") }
                }
                .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityHint(wide ? Text("") : Text("Show month"))
            Spacer()
            Button { move(-1, byMonth: wide || showingMonth) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel(wide || showingMonth ? Text("Previous month") : Text("Previous week"))
            Button("Today") {
                selectedDate = Date()
                showingMonth = false
                coordinator.calendarShowsWeek = false
                coordinator.calendarRevealEventID = nil
            }
            Button("Next 7 days") {
                selectedDate = Date()
                coordinator.calendarShowsWeek = true
                coordinator.calendarRevealEventID = nil
                showingMonth = false
            }
            .foregroundStyle(coordinator.calendarShowsWeek ? Color.effectiveAccent : Color.primary)
            Button { move(1, byMonth: wide || showingMonth) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel(wide || showingMonth ? Text("Next month") : Text("Next week"))
            Button { NSWorkspace.shared.open(URL(string: "ical://")!) } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .accessibilityLabel("Open Calendar")
            .help("Open Calendar")
        }
        .buttonStyle(.plain)
        .controlSize(.small)
        .frame(height: 28)
    }

    private var monthGrid: some View {
        GeometryReader { geometry in
            let days = CalendarPageDates.days(in: CalendarPageDates.monthRange(containing: selectedDate))
            let rowHeight = min(36, max(16, (geometry.size.height - 20) / CGFloat(days.count / 7)))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(height: 20)
                }
                ForEach(days, id: \.self) { day in
                    dayButton(day, height: rowHeight, weekday: false)
                }
            }
        }
    }

    private var weekStrip: some View {
        let week = calendar.dateInterval(of: .weekOfYear, for: selectedDate)!
        return HStack(spacing: 2) {
            ForEach(CalendarPageDates.days(in: week), id: \.self) { day in
                dayButton(day, height: 48, weekday: true)
            }
        }
        .frame(height: 48)
    }

    private func dayButton(_ day: Date, height: CGFloat, weekday: Bool) -> some View {
        let selected = !coordinator.calendarShowsWeek && calendar.isDate(day, inSameDayAs: selectedDate)
        let today = calendar.isDateInToday(day)
        let inMonth = calendar.isDate(day, equalTo: selectedDate, toGranularity: .month)
        let calendars = visibleEvents.filter { CalendarPageDates.contains(start: $0.start, end: $0.end, on: day) }
            .reduce(into: [CalendarModel]()) { result, event in
                if result.count < 3 && !result.contains(where: { $0.id == event.calendar.id }) { result.append(event.calendar) }
            }
        return Button {
            selectedDate = day
            coordinator.calendarShowsWeek = false
            coordinator.calendarRevealEventID = nil
            showingMonth = false
        } label: {
            VStack(spacing: 1) {
                if weekday {
                    Text(day, format: .dateTime.weekday(.narrow))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Text(calendar.component(.day, from: day), format: .number)
                    .font(.system(size: 12, weight: selected || today ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : today ? Color.effectiveAccent : Color.primary)
                    .frame(width: min(26, height - 5), height: min(26, height - 5))
                    .background(selected ? Color.effectiveAccent : .clear, in: Circle())
                    .overlay(Circle().inset(by: 2).strokeBorder(today ? (selected ? Color.white : Color.effectiveAccent) : .clear, lineWidth: 1))
                HStack(spacing: 2) {
                    ForEach(calendars, id: \.id) { item in
                        Circle().fill(Color(item.color)).frame(width: 3, height: 3)
                    }
                }.frame(height: 3)
            }
            .opacity(inMonth || weekday ? 1 : 0.4)
            .frame(maxWidth: .infinity).frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day, format: .dateTime.year().month().day().weekday(.wide)))
        .accessibilityValue(today ? Text("Today") : Text(""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var agenda: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let events = agendaEvents(now: context.date)
            Group {
                if loadedDate != selectedDate {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if events.isEmpty {
                    if coordinator.calendarShowsWeek {
                        VStack(spacing: 6) {
                            Image(systemName: "calendar.badge.checkmark").font(.title2)
                            Text("No upcoming events").font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        EmptyEventsView(selectedDate: selectedDate).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    StandaloneEventCardList(events: events, selectedDate: selectedDate,
                                            showFullEventTitles: Defaults[.showFullEventTitles],
                                            showsWeek: coordinator.calendarShowsWeek, now: context.date,
                                            revealEventID: $coordinator.calendarRevealEventID) { id, completed in
                        Task { await calendarManager.setReminderCompleted(reminderID: id, completed: completed) }
                    }
                    .id("\(calendar.startOfDay(for: selectedDate))-\(coordinator.calendarShowsWeek)")
                }
            }
            .onChange(of: calendar.startOfDay(for: context.date)) { _, _ in
                if coordinator.calendarShowsWeek { selectedDate = context.date }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark").font(.title2)
            Text("Allow calendar access to see your events.")
            Button("Allow Calendar Access") {
                Task {
                    if calendarManager.calendarAuthorizationStatus == .notDetermined {
                        await calendarManager.checkCalendarAuthorization()
                    } else {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func move(_ offset: Int, byMonth: Bool) {
        let base = byMonth ? selectedDate.startOfMonth : selectedDate
        if let date = calendar.date(byAdding: byMonth ? .month : .day, value: byMonth ? offset : offset * 7, to: base) {
            selectedDate = date
            coordinator.calendarShowsWeek = false
            coordinator.calendarRevealEventID = nil
        }
    }
}

struct EmptyEventsView: View {
    let selectedDate: Date

    var body: some View {
        // Explicit spacing: the default VStack gap (8pt) applied equally between
        // the icon and both lines, which left the two labels floating apart
        // instead of reading as one caption block under the glyph.
        VStack(spacing: 0) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(Color.secondary)
                .padding(.bottom, 7)
            Text(Calendar.current.isDateInToday(selectedDate) ? "No events today" : "No events")
                .font(.subheadline)
                .foregroundColor(Color.primary)
            Text("Enjoy your free time!")
                .font(.caption)
                .foregroundColor(Color.secondary)
                .padding(.top, 1)
        }
        .multilineTextAlignment(.center)
    }
}

private extension Date {
    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self)) ?? self
    }
}

private struct StandaloneEventCardList: View {
    @Environment(\.openURL) private var openURL
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    let events: [EventModel]
    let selectedDate: Date
    let showFullEventTitles: Bool
    let showsWeek: Bool
    let now: Date
    @Binding var revealEventID: String?
    let onToggleReminder: (String, Bool) -> Void
    @State private var initialAutoScrollDone = false
    @State private var revealedEventID: String?

    private var timedEvents: [EventModel] {
        // Sorted by start time so `scrollTargetForTimedEvents` (which uses
        // `first(where:)` to pick in-progress / next-upcoming) returns the true
        // nearest-to-now event, and the list renders chronologically. (#566)
        partitionEvents(events).timed.sorted { $0.start < $1.start }
    }

    private func scrollToRelevantEvent(proxy: ScrollViewProxy) {
        if let id = revealEventID, events.contains(where: { $0.id == id }) {
            DispatchQueue.main.async {
                guard revealEventID == id else { return }
                proxy.scrollTo(id, anchor: .center)
                revealedEventID = id
                revealEventID = nil
            }
            return
        }
        guard !showsWeek else { return }
        guard autoScrollToNextEvent else { return }
        let refTime = scrollReferenceTime(for: selectedDate)
        guard let target = scrollTargetForTimedEvents(timed: timedEvents, referenceTime: refTime) else { return }

        // Use .center anchor for more reliable positioning with List's internal padding.
        // DispatchQueue.main.async ensures the scroll fires after List completes its initial layout,
        // avoiding the race condition where proxy.scrollTo fires before items are measured.
        let anchor: UnitPoint = .center
        DispatchQueue.main.async {
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(target.id, anchor: anchor)
            }
        }
    }

    var body: some View {
        // One list keeps grouped days and explicit event navigation in the same scroll container.
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ZStack {
                    List {
                        if showsWeek {
                            ForEach(CalendarPageDates.days(in: CalendarPageDates.upcomingRange(from: now)), id: \.self) { day in
                                let group = events.filter { CalendarPageDates.contains(start: $0.start, end: $0.end, on: day) }
                                if !group.isEmpty {
                                    Section {
                                        ForEach(group) { event in
                                            eventRow(event)
                                        }
                                    } header: {
                                        Text(day, format: .dateTime.month().day().weekday(.abbreviated))
                                    }
                                }
                            }
                        } else {
                            ForEach(events.sorted { $0.start < $1.start }) { event in
                                eventRow(event)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollIndicators(.never)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
                .onAppear {
                    scrollToRelevantEvent(proxy: proxy)
                    if !timedEvents.isEmpty {
                        initialAutoScrollDone = true
                    }
                }
                .onChange(of: selectedDate) { _, _ in
                    scrollToRelevantEvent(proxy: proxy)
                }
                .onChange(of: revealEventID) { _, id in
                    if id != nil { scrollToRelevantEvent(proxy: proxy) }
                }
                .onChange(of: timedEvents.isEmpty) { wasEmpty, isEmpty in
                    // Retrigger the initial auto-scroll once, when timed events become
                    // available after the view appeared (e.g. async calendar load).
                    // Guarded so later data refreshes don't re-scroll. (#566 follow-up)
                    guard wasEmpty, !isEmpty, !initialAutoScrollDone else { return }
                    scrollToRelevantEvent(proxy: proxy)
                    initialAutoScrollDone = true
                }
                .onChange(of: events) { _, _ in
                    // Fallback: re-trigger auto-scroll when events are refreshed (e.g., calendar
                    // permission granted, calendars re-selected, or external calendar change).
                    // The initialAutoScrollDone guard prevents unwanted re-scrolling on minor updates.
                    if !initialAutoScrollDone {
                        scrollToRelevantEvent(proxy: proxy)
                    }
                }
            }


        }
        .clipped()
    }

    private func eventRow(_ event: EventModel) -> some View {
        eventCard(event)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
                revealedEventID == event.id ? Color.effectiveAccent : .clear, lineWidth: 1))
            .id(event.id)
            .padding(.bottom, 8)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
    }

    @ViewBuilder
    private func eventCard(_ event: EventModel) -> some View {
        if event.type.isReminder {
            Button {
                if let url = event.calendarAppURL() {
                    openURL(url)
                }
            } label: {
                reminderCard(event)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 2)
        } else {
            calendarEventCard(event)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let url = event.calendarAppURL() {
                        openURL(url)
                    }
                }
                .padding(.horizontal, 2)
        }
    }

    private func reminderCard(_ event: EventModel) -> some View {
        let isCompleted: Bool
        if case .reminder(let completed) = event.type {
            isCompleted = completed
        } else {
            isCompleted = false
        }

        return HStack(spacing: 10) {
            ReminderToggle(
                isOn: Binding(
                    get: { isCompleted },
                    set: { newValue in onToggleReminder(event.id, newValue) }
                ),
                color: Color(event.calendar.color)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(Color.primary)
                    .lineLimit(showFullEventTitles ? nil : 2)

                if event.isAllDay {
                    Text("All-day")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }

            Spacer(minLength: 8)

            if !event.isAllDay {
                Text(event.start, style: .time)
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .opacity(isCompleted ? 0.55 : 1)
    }

    private func calendarEventCard(_ event: EventModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(event.calendar.color))
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                if !event.isAllDay && event.start <= now && event.end > now {
                    Text("Ongoing").font(.caption2).foregroundStyle(Color.effectiveAccent)
                } else if !event.isAllDay && event == events.filter({ !$0.isAllDay && !$0.type.isReminder && $0.start > now }).min(by: { $0.start < $1.start }) {
                    Text("Up next").font(.caption2).foregroundStyle(.secondary)
                }
                Text(event.title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(Color.primary)
                    .lineLimit(showFullEventTitles ? nil : 2)

                Text(event.calendar.title).font(.caption2).foregroundStyle(.secondary)

                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                        .lineLimit(1)
                }

                if let conferenceURL = event.conferenceURL {
                    ConferenceJoinButton(url: conferenceURL, event: event)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                if CalendarPageDates.spansDays(start: event.start, end: event.end, allDay: event.isAllDay) {
                    Text(event.start, format: event.isAllDay ? .dateTime.month().day() : .dateTime.month().day().hour().minute())
                    Text(event.isAllDay ? event.end.addingTimeInterval(-1) : event.end,
                         format: event.isAllDay ? .dateTime.month().day() : .dateTime.month().day().hour().minute())
                        .foregroundStyle(.secondary)
                } else if event.isAllDay {
                    Text("All-day")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Color.primary)
                } else {
                    Text(event.start, style: .time)
                        .font(.caption)
                        .foregroundColor(Color.primary)
                    Text(event.end, style: .time)
                        .font(.caption2)
                        .foregroundColor(Color.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .opacity(event.eventStatus == .ended && Calendar.current.isDateInToday(event.start) ? 0.6 : 1)
    }
}

struct EventListView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var calendarManager = CalendarManager.shared
    let events: [EventModel]
    let selectedDate: Date
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    @Default(.showFullEventTitles) private var showFullEventTitles
    @Default(.hideCompletedReminders) private var hideCompletedReminders
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @State private var initialAutoScrollDone = false

    static func filteredEvents(
        events: [EventModel],
        hideCompletedReminders: Bool,
        hideAllDayEvents: Bool
    ) -> [EventModel] {
        events.filter { event in
            if event.type.isReminder {
                if case .reminder(let completed) = event.type {
                    return !completed || !hideCompletedReminders
                }
            }
            if event.isAllDay && hideAllDayEvents {
                return false
            }
            return true
        }
    }

    private var filteredEvents: [EventModel] {
        Self.filteredEvents(
            events: events,
            hideCompletedReminders: hideCompletedReminders,
            hideAllDayEvents: hideAllDayEvents
        )
    }

    private var allDayEvents: [EventModel] {
        partitionEvents(filteredEvents).allDay.sorted { $0.start < $1.start }
    }

    private var timedEvents: [EventModel] {
        // Sorted by start time so `scrollTargetForTimedEvents` (which uses
        // `first(where:)` to pick in-progress / next-upcoming) returns the true
        // nearest-to-now event, and the list renders chronologically. (#566)
        partitionEvents(filteredEvents).timed.sorted { $0.start < $1.start }
    }

    private func scrollToRelevantEvent(proxy: ScrollViewProxy) {
        guard autoScrollToNextEvent else { return }
        let refTime = scrollReferenceTime(for: selectedDate)
        guard let target = scrollTargetForTimedEvents(timed: timedEvents, referenceTime: refTime) else { return }

        // Use .center anchor for more reliable positioning with List's internal padding.
        // DispatchQueue.main.async ensures the scroll fires after List completes its initial layout,
        // avoiding the race condition where proxy.scrollTo fires before items are measured.
        let anchor: UnitPoint = .center
        DispatchQueue.main.async {
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(target.id, anchor: anchor)
            }
        }
    }

    var body: some View {
        // Timed-events list fills the whole panel; the all-day strip floats as
        // an overlay on top (zero vertical cost) so the scroll area below keeps
        // its full height inside the 120pt Dynamic Island panel.  The List
        // carries a top padding equal to the strip height so that
        // scrollTo(.top) lands the target event fully below the overlay. (#566)
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ZStack {
                    List {
                        ForEach(timedEvents) { event in
                            Button(action: {
                                if let url = event.calendarAppURL() {
                                    openURL(url)
                                }
                            }) {
                                eventRow(event)
                            }
                            .id(event.id)
                            .padding(.leading, -5)
                            .buttonStyle(PlainButtonStyle())
                            .listRowSeparator(.automatic)
                            .listRowSeparatorTint(.gray.opacity(0.2))
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollIndicators(.never)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    // Push list content down so scrollTo(.top) positions the
                    // target event fully below the floating all-day overlay
                    // (28pt strip + 1pt separator + 1pt margin = 30pt).
                    .padding(.top, allDayEvents.isEmpty ? 0 : AllDayStripMetrics.listTopInset)

                    // (Shadows intentionally removed — #566 feedback: the gradient
                    // overlay was permanently drawn on top of the events.)
                }
                .onAppear {
                    scrollToRelevantEvent(proxy: proxy)
                    if !timedEvents.isEmpty {
                        initialAutoScrollDone = true
                    }
                }
                .onChange(of: selectedDate) { _, _ in
                    scrollToRelevantEvent(proxy: proxy)
                }
                .onChange(of: timedEvents.isEmpty) { wasEmpty, isEmpty in
                    // Retrigger the initial auto-scroll once, when timed events become
                    // available after the view appeared (e.g. async calendar load).
                    // Guarded so later data refreshes don't re-scroll. (#566 follow-up)
                    guard wasEmpty, !isEmpty, !initialAutoScrollDone else { return }
                    scrollToRelevantEvent(proxy: proxy)
                    initialAutoScrollDone = true
                }
                .onChange(of: calendarManager.events) { _, _ in
                    // Fallback: re-trigger auto-scroll when events are refreshed (e.g., calendar
                    // permission granted, calendars re-selected, or external calendar change).
                    // The initialAutoScrollDone guard prevents unwanted re-scrolling on minor updates.
                    if !initialAutoScrollDone {
                        scrollToRelevantEvent(proxy: proxy)
                    }
                }
            }

            if !allDayEvents.isEmpty {
                AllDayEventsStrip(
                    events: allDayEvents,
                    onToggleReminder: { reminderID, completed in
                        Task {
                            await calendarManager.setReminderCompleted(
                                reminderID: reminderID, completed: completed
                            )
                        }
                    }
                )
                .background(Color.notchBackground.opacity(0.95))
            }
        }
        Spacer(minLength: 0)
    }

    private func eventRow(_ event: EventModel) -> some View {
        if event.type.isReminder {
            let isCompleted: Bool
            if case .reminder(let completed) = event.type {
                isCompleted = completed
            } else {
                isCompleted = false
            }
            return AnyView(
                HStack(spacing: 8) {
                    ReminderToggle(
                        isOn: Binding(
                            get: { isCompleted },
                            set: { newValue in
                                Task {
                                    await calendarManager.setReminderCompleted(
                                        reminderID: event.id, completed: newValue
                                    )
                                }
                            }
                        ),
                        color: Color(event.calendar.color)
                    )
                    .opacity(1.0)
                    HStack {
                        Text(event.title)
                            .font(.callout)
                            .foregroundColor(Color.primary)
                            .lineLimit(showFullEventTitles ? nil : 1)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 4) {
                            if event.isAllDay {
                                Text("All-day")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color.primary)
                                    .lineLimit(1)
                            } else {
                                Text(event.start, style: .time)
                                    .foregroundColor(Color.primary)
                                    .font(.caption)
                            }
                        }
                    }
                    .opacity(
                        isCompleted
                            ? 0.4
                            : event.start < Date.now && Calendar.current.isDateInToday(event.start)
                                ? 0.6 : 1.0
                    )
                }
                .padding(.vertical, 4)
            )
        } else {
            return AnyView(
                HStack(alignment: .top, spacing: 4) {
                    Rectangle()
                        .fill(Color(event.calendar.color))
                        .frame(width: 3)
                        .cornerRadius(1.5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(Color.primary)
                            .lineLimit(showFullEventTitles ? nil : 2)

                        if let location = event.location, !location.isEmpty {
                            Text(location)
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                                .lineLimit(1)
                        }
                        
                        // Show Join button if conference URL is available
                        if let conferenceURL = event.conferenceURL {
                            ConferenceJoinButton(url: conferenceURL, event: event)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        if event.isAllDay {
                            Text("All-day")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(Color.primary)
                                .lineLimit(1)
                        } else {
                            Text(event.start, style: .time)
                                .foregroundColor(Color.primary)
                            Text(event.end, style: .time)
                                .foregroundColor(Color.secondary)
                        }
                    }
                    .font(.caption)
                    .frame(minWidth: 44, alignment: .trailing)
                }
                .opacity(
                    event.eventStatus == .ended && Calendar.current.isDateInToday(event.start)
                        ? 0.6 : 1.0)
            )
        }
    }
}

struct ReminderToggle: View {
    @Binding var isOn: Bool
    var color: Color

    var body: some View {
        Button(action: {
            isOn.toggle()
        }) {
            ZStack {
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 14, height: 14)
                if isOn {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Circle()
                    .fill(Color.black.opacity(0.001))
                    .frame(width: 14, height: 14)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(0)
        .accessibilityLabel(isOn ? "Mark as incomplete" : "Mark as complete")
    }
}

// MARK: - Conference Provider

enum ConferenceProvider: CaseIterable {
    case zoom, teams, meet, webex, facetime, gotomeeting, bluejeans, whereby, jitsi, discord, generic
    
    var name: String {
        switch self {
        case .zoom: return "Zoom"
        case .teams: return "Teams"
        case .meet: return "Meet"
        case .webex: return "Webex"
        case .facetime: return "FaceTime"
        case .gotomeeting: return "GoToMeeting"
        case .bluejeans: return "BlueJeans"
        case .whereby: return "Whereby"
        case .jitsi: return "Jitsi"
        case .discord: return "Discord"
        case .generic: return ""
        }
    }
    
    var color: Color {
        switch self {
        case .zoom: return Color(red: 0.16, green: 0.52, blue: 0.95)
        case .teams: return Color(red: 0.36, green: 0.42, blue: 0.89)
        case .meet: return Color(red: 0.0, green: 0.65, blue: 0.42)
        case .webex: return Color(red: 0.0, green: 0.71, blue: 0.84)
        case .facetime: return Color(red: 0.2, green: 0.78, blue: 0.35)
        case .gotomeeting: return Color(red: 0.95, green: 0.5, blue: 0.13)
        case .bluejeans: return Color(red: 0.0, green: 0.48, blue: 0.87)
        case .whereby: return Color(red: 0.27, green: 0.51, blue: 0.96)
        case .jitsi: return Color(red: 0.16, green: 0.68, blue: 0.95)
        case .discord: return Color(red: 0.35, green: 0.39, blue: 0.98)
        case .generic: return Color.accentColor
        }
    }
    
    private var hostIdentifiers: [String] {
        switch self {
        case .zoom: return ["zoom.us"]
        case .teams: return ["teams.microsoft.com"]
        case .meet: return ["meet.google.com"]
        case .webex: return ["webex.com"]
        case .facetime: return ["facetime.apple.com"]
        case .gotomeeting: return ["gotomeeting.com"]
        case .bluejeans: return ["bluejeans.com"]
        case .whereby: return ["whereby.com"]
        case .jitsi: return ["meet.jit.si", "jitsi"]
        case .discord: return ["discord.gg", "discord.com"]
        case .generic: return []
        }
    }
    
    var nativeURLScheme: String? {
        switch self {
        case .zoom: return "zoommtg"
        case .teams: return "msteams"
        case .facetime: return "facetime"
        case .discord: return "discord"
        default: return nil
        }
    }

    static func detect(from url: URL) -> ConferenceProvider {
        let host = url.host?.lowercased() ?? ""
        return allCases.first { provider in
            provider.hostIdentifiers.contains { host.contains($0) }
        } ?? .generic
    }
}

// MARK: - Conference Join Button

struct ConferenceJoinButton: View {
    let url: URL
    let event: EventModel
    @Environment(\.openURL) private var openURL
    
    private var provider: ConferenceProvider { .detect(from: url) }
    private var isJoinable: Bool {
        event.start.addingTimeInterval(-15 * 60) <= Date()
    }
    
    private var buttonText: String {
        event.eventStatus == .inProgress ? "Rejoin" : "Join"
    }
    
    var body: some View {
        Button(action: {
            if provider == .zoom {
                openURL(url)
                return
            }
            if let scheme = provider.nativeURLScheme,
               var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.scheme = scheme
                if let nativeURL = components.url {
                    openURL(nativeURL)
                    return
                }
            }
            openURL(url)
        }) {
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                    .font(.system(size: 9))
                Text(provider.name.isEmpty ? buttonText : "\(buttonText) \(provider.name)")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(isJoinable ? .white : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isJoinable ? provider.color.opacity(0.85) : Color.gray.opacity(0.3))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isJoinable)
        .help(isJoinable ? "Join the meeting" : "Meeting starts at \(event.start.formatted(date: .omitted, time: .shortened))")
    }
}

#Preview {
    CalendarView()
        .frame(width: 250)
        .padding(.horizontal)
        .background(Color.notchBackground)
        .environmentObject(DynamicIslandViewModel.init())
}
