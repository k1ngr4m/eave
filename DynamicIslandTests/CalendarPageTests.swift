import XCTest
import Defaults
@testable import Eave

final class CalendarPageTests: XCTestCase {
    func testMonthRangeCoversSixWeeksAcrossDaylightSaving() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 2
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let range = CalendarPageDates.monthRange(containing: date, calendar: calendar)
        let days = CalendarPageDates.days(in: range, calendar: calendar)
        XCTAssertEqual(days.count, 42)
        XCTAssertEqual(calendar.component(.weekday, from: days[0]), 2)
        XCTAssertEqual(days.filter { calendar.component(.month, from: $0) == 3 }.count, 31)
        XCTAssertTrue(days.allSatisfy { calendar.component(.hour, from: $0) == 0 })
        let midnight = calendar.startOfDay(for: date)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: midnight)!
        XCTAssertTrue(CalendarPageDates.contains(start: midnight, end: tomorrow, on: date, calendar: calendar))
        XCTAssertFalse(CalendarPageDates.contains(start: midnight, end: tomorrow, on: tomorrow, calendar: calendar))
        XCTAssertTrue(CalendarPageDates.contains(start: midnight, end: midnight, on: date, calendar: calendar))
        XCTAssertFalse(CalendarPageDates.contains(start: tomorrow, end: tomorrow, on: date, calendar: calendar))
    }

    func testUpcomingWeekCrossesYearAndExcludesEndedEvents() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 12, day: 29, hour: 12))!
        let range = CalendarPageDates.upcomingRange(from: now, calendar: calendar)
        XCTAssertEqual(CalendarPageDates.days(in: range, calendar: calendar).count, 7)
        XCTAssertEqual(calendar.component(.year, from: range.end), 2027)
        let source = CalendarModel(accountName: "Test", id: "calendar", title: "Test", color: .blue,
                                   isSubscribed: false, isReminder: false)
        func event(_ id: String, _ start: Date, _ end: Date) -> EventModel {
            EventModel(id: id, start: start, end: end, title: id, location: nil, notes: nil, url: nil,
                       isAllDay: false, type: .event(.accepted), calendar: source, participants: [],
                       timeZone: nil, hasRecurrenceRules: false, priority: nil, conferenceURL: nil)
        }
        let events = [event("outside", range.end, range.end.addingTimeInterval(60)),
                      event("last-day", range.end.addingTimeInterval(-60), range.end),
                      event("ended", now.addingTimeInterval(-60), now),
                      event("ongoing", now.addingTimeInterval(-60), now.addingTimeInterval(60)),
                      event("point", now, now)]
        XCTAssertEqual(CalendarPageDates.upcoming(events, now: now, calendar: calendar).map(\.id),
                       ["ongoing", "point", "last-day"])
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        XCTAssertTrue(CalendarPageDates.spansDays(start: now, end: tomorrow, allDay: false, calendar: calendar))
        XCTAssertFalse(CalendarPageDates.spansDays(start: calendar.startOfDay(for: now), end: tomorrow,
                                                   allDay: true, calendar: calendar))
        XCTAssertTrue(CalendarPageDates.spansDays(start: calendar.startOfDay(for: now),
                                                  end: calendar.date(byAdding: .day, value: 1, to: tomorrow)!,
                                                  allDay: true, calendar: calendar))
    }

    @MainActor
    func testCountdownOpensTheExactDayInsteadOfTheWeekOverview() {
        let coordinator = DynamicIslandViewCoordinator.shared
        let state = (coordinator.currentView, coordinator.calendarDate, coordinator.calendarShowsWeek,
                     coordinator.calendarRevealEventID)
        let enabled = Defaults[.showCalendar]
        defer {
            Defaults[.showCalendar] = enabled
            coordinator.currentView = state.0
            coordinator.calendarDate = state.1
            coordinator.calendarShowsWeek = state.2
            coordinator.calendarRevealEventID = state.3
        }
        Defaults[.showCalendar] = true
        let source = CalendarModel(accountName: "Test", id: "calendar", title: "Test", color: .blue,
                                   isSubscribed: false, isReminder: false)
        let date = Date().addingTimeInterval(86400)
        let event = EventModel(id: "countdown-event", start: date, end: date.addingTimeInterval(3600),
                               title: "Meeting", location: nil, notes: nil, url: nil, isAllDay: false,
                               type: .event(.accepted), calendar: source, participants: [], timeZone: nil,
                               hasRecurrenceRules: false, priority: nil, conferenceURL: nil)
        let vm = DynamicIslandViewModel(settingsPreview: true)
        vm.close()
        vm.openCalendar(event: event)
        XCTAssertEqual(vm.notchState, .open)
        XCTAssertEqual(coordinator.currentView, .calendar)
        XCTAssertEqual(coordinator.calendarDate, date)
        XCTAssertFalse(coordinator.calendarShowsWeek)
        XCTAssertEqual(coordinator.calendarRevealEventID, event.id)
    }

    @MainActor
    func testCalendarIsIndependentOfMediaAndAvailableInMinimalMode() {
        let minimal = Defaults[.enableMinimalisticUI]
        let media = Defaults[.showStandardMediaControls]
        let calendar = Defaults[.showCalendar]
        let mirror = Defaults[.showMirror]
        let lyrics = Defaults[.enableLyrics]
        defer {
            Defaults[.enableMinimalisticUI] = minimal
            Defaults[.showStandardMediaControls] = media
            Defaults[.showCalendar] = calendar
            Defaults[.showMirror] = mirror
            Defaults[.enableLyrics] = lyrics
        }
        Defaults[.enableMinimalisticUI] = false
        Defaults[.showStandardMediaControls] = false
        Defaults[.showMirror] = false
        Defaults[.showCalendar] = true
        XCTAssertTrue(TabModel.availableTabs().contains { $0.view == .calendar })
        XCTAssertFalse(TabModel.availableTabs().contains { $0.view == .home })
        let size = calendarOpenNotchSize()
        Defaults[.enableLyrics].toggle()
        XCTAssertEqual(calendarOpenNotchSize(), size)
        Defaults[.enableMinimalisticUI] = true
        XCTAssertEqual(TabModel.availableTabs().map(\.view), [.home, .calendar])
        XCTAssertEqual(enabledStandardTabCount(), 2)
        XCTAssertEqual(ReopenTabSelection.resolve(preference: "system-calendar", lastPage: nil,
                                                  available: TabModel.availableTabs().map(\.id)), "system-calendar")
        Defaults[.showCalendar] = false
        XCTAssertEqual(TabModel.availableTabs().map(\.view), [.home])
        XCTAssertEqual(ReopenTabSelection.resolve(preference: "system-calendar", lastPage: nil,
                                                  available: TabModel.availableTabs().map(\.id)), "system-home")
    }
}
