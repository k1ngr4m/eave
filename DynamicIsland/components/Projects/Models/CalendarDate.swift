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

import Foundation

/// A calendar date (year-month-day) independent of any time zone or wall-clock time.
///
/// Schedules in the projects module are calendar dates, not midnight timestamps:
/// "2026-10-26" keeps meaning October 26 even after a time-zone change, and
/// arithmetic between dates counts calendar days, never fixed 86,400-second
/// steps, so DST transitions cannot shift a date by an hour-day.
struct CalendarDate: Comparable, Hashable, Codable, Identifiable {
    let year: Int
    let month: Int
    let day: Int

    var id: String { stringValue }

    var stringValue: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Validates through `Foundation.Calendar`, so impossible dates
    /// (2026-02-30, 2025-02-29, month 13) are rejected instead of silently
    /// rolling over to the next month.
    init?(year: Int, month: Int, day: Int) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else { return nil }
        // Do not read DateComponents.date here: on recent Foundation builds
        // dateComponents(_:from:) no longer sets .calendar on its result, so
        // .date is always nil. Comparing the components directly validates
        // just as well — date(from:) rolls impossible dates forward, so a
        // mismatch rejects them.
        let validated = calendar.dateComponents([.year, .month, .day], from: date)
        guard validated.year == year, validated.month == month, validated.day == day else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses "YYYY-MM-DD" and verifies it names a real calendar date.
    init?(parsing string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    /// Today in the system's current time zone.
    static var today: CalendarDate {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        guard let year = components.year, let month = components.month, let day = components.day,
              let today = CalendarDate(year: year, month: month, day: day) else {
            // Unreachable with Calendar.current components, but keep a valid fallback.
            return CalendarDate(year: 2000, month: 1, day: 1)!
        }
        return today
    }

    /// Calendar-day arithmetic that survives DST: the offset is expressed in
    /// days, and the result is re-anchored on its own y/m/d components.
    func adding(days: Int) -> CalendarDate {
        guard days != 0 else { return self }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let base = calendar.date(from: components) else { return self }
        let moved = calendar.date(byAdding: .day, value: days, to: base) ?? base
        let parts = calendar.dateComponents([.year, .month, .day], from: moved)
        return CalendarDate(year: parts.year ?? self.year,
                            month: parts.month ?? self.month,
                            day: parts.day ?? self.day) ?? self
    }

    /// Number of calendar days between two dates; positive when self is later.
    func days(since other: CalendarDate) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let start = calendar.date(from: DateComponents(year: other.year, month: other.month, day: other.day))!
        let end = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// 0 = Sunday … 6 = Saturday, in the Gregorian calendar used for schedules.
    var weekdaySundayFirst: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        return calendar.component(.weekday, from: date) - 1
    }

    /// First day of the week containing this date, given the system's first weekday.
    func startOfWeek(firstWeekday: Int) -> CalendarDate {
        let offset = (weekdaySundayFirst - firstWeekday + 7) % 7
        return adding(days: -offset)
    }

    var isWeekend: Bool {
        let weekday = weekdaySundayFirst
        return weekday == 0 || weekday == 6
    }

    /// A Date at local noon on this calendar day — safe for DatePicker round-trips
    /// (noon survives DST shifts in every zone that observes DST).
    var localNoon: Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components) ?? Date()
    }

    static func from(localNoon date: Date) -> CalendarDate {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day,
              let parsed = CalendarDate(year: year, month: month, day: day) else {
            return CalendarDate(year: 2000, month: 1, day: 1)!
        }
        return parsed
    }

    static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    private enum CodingKeys: String, CodingKey {
        case date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = CalendarDate(parsing: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid calendar date: \(raw)")
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}

extension CalendarDate {
    /// Short display form for list cells: "10月26日" (or system-formatted equivalent).
    var shortDisplayText: String {
        let formatter = Self.shortFormatter
        return formatter.string(from: localNoon)
    }

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = false
        return formatter
    }()
}
