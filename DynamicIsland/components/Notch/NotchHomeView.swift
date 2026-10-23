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

import AppKit
import Defaults
import SwiftUI

struct NotchHomeView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var webcamManager = WebcamManager.shared
    @Default(.enableMinimalisticUI) private var minimalistic
    @Default(.showMirror) private var showMirror

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                VStack(spacing: 0) {
                    HStack(spacing: minimalistic ? 12 : 28) {
                        TimelineView(.periodic(from: Calendar.current.startOfDay(for: .now), by: 60)) { context in
                            HomeClockView(date: context.date, compact: minimalistic)
                        }
                        .frame(maxWidth: .infinity)

                        if !minimalistic {
                            HomeGlanceColumn()
                                .fixedSize()
                        }

                        if showMirror && webcamManager.cameraAvailable && vm.notchState == .open {
                            CameraPreviewView(webcamManager: webcamManager)
                                .frame(width: minimalistic ? 80 : 128, height: minimalistic ? 80 : 128)
                        }
                    }
                    .frame(maxWidth: 460, maxHeight: .infinity)
                    .frame(maxWidth: .infinity)

                    if minimalistic {
                        MinimalisticHomeActivitiesView()
                    }
                }
                .padding(.horizontal, minimalistic ? 4 : 16)
                .padding(.vertical, 8)
                .blur(radius: vm.notchState == .closed ? 30 : 0)
            }
        }
        .transition(.opacity)
    }
}

struct HomeClockView: View {
    let date: Date
    let compact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var isBreathing = false

    private var clockText: String {
        date.formatted(.dateTime.hour().minute())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(clockText)
                .font(.system(size: compact ? 36 : 48, weight: .ultraLight, design: .rounded))
                .monospacedDigit()
                .tracking(-1.5)
                .foregroundStyle(clockFill)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: clockText)
            HStack(spacing: 5) {
                Text(date, format: .dateTime.weekday(.wide))
                Text(verbatim: "·")
                    .foregroundStyle(Color.primary.opacity(0.3))
                Text(date, format: .dateTime.month().day())
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .tracking(0.3)
            .foregroundStyle(Color.primary.opacity(0.65))
            .padding(.leading, 2)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .background(alignment: .leading) { ambientGlow }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.45)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Top-lit digits keep the ultraLight weight from looking flat against
    /// the black notch surface.
    private var clockFill: some ShapeStyle {
        LinearGradient(
            colors: [Color.primary.opacity(0.98), Color.primary.opacity(0.66)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var ambientGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.primary.opacity(0.07), .clear],
                    center: .center,
                    startRadius: 12,
                    endRadius: 130
                )
            )
            .frame(width: 260, height: 260)
            .offset(x: -14, y: -6)
            .scaleEffect(isBreathing ? 1.07 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
    }
}

/// The Home tab's right-hand glance column: weather, the next calendar event,
/// and the battery — one quiet row each, hidden when the data is unavailable.
private struct HomeGlanceColumn: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.enableLockScreenWeatherWidget) private var showsWeather

    var body: some View {
        TimelineView(.periodic(from: Calendar.current.startOfDay(for: .now), by: 60)) { context in
            VStack(alignment: .trailing, spacing: 10) {
                if showsWeather {
                    WeatherGlanceRow()
                }
                if let event = nextEvent(at: context.date) {
                    EventGlanceRow(event: event)
                }
                BatteryGlanceRow(referenceDate: context.date)
            }
        }
    }

    private func nextEvent(at date: Date) -> EventModel? {
        calendarManager.lockScreenEvents
            .filter { $0.type.isEvent && !$0.isAllDay && $0.end > date }
            .min { $0.start < $1.start }
    }
}

private struct WeatherGlanceRow: View {
    // Only constructed while the user enabled weather, so reaching the shared
    // manager here cannot trigger its location prompt for anyone else.
    @ObservedObject private var manager = LockScreenWeatherManager.shared

    var body: some View {
        if let snapshot = manager.snapshot {
            HStack(spacing: 5) {
                Image(systemName: snapshot.symbolName)
                    .symbolRenderingMode(.multicolor)
                Text(verbatim: temperatureLabel(for: snapshot))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.6))
            .accessibilityElement(children: .combine)
        }
    }

    private func temperatureLabel(for snapshot: LockScreenWeatherSnapshot) -> String {
        let base = snapshot.temperatureInfo?.displayCurrent ?? snapshot.temperatureText
        return base.hasSuffix("°") ? base : base + "°"
    }
}

private struct EventGlanceRow: View {
    let event: EventModel

    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        Button {
            coordinator.currentView = .calendar
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(eventColor)
                    .frame(width: 3, height: 12)
                Text(verbatim: Self.timeFormatter.string(from: event.start))
                    .monospacedDigit()
                Text(event.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 180, alignment: .trailing)
        .help(event.title)
        .accessibilityElement(children: .combine)
    }

    private var eventColor: Color {
        Color(nsColor: event.calendar.color).ensureMinimumBrightness(factor: 0.7).notchReadableTint()
    }
}

private struct BatteryGlanceRow: View {
    let referenceDate: Date

    @State private var status: MacBatteryManager.BatteryStatus?

    var body: some View {
        if let status, let percentage = status.percentage {
            HStack(spacing: 5) {
                Text("\(percentage)%")
                    .monospacedDigit()
                Image(systemName: status.isCharging ? "bolt.fill" : batterySymbol(for: percentage))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.6))
            .onAppear(perform: refresh)
            .onChange(of: referenceDate) { _, _ in refresh() }
            .accessibilityElement(children: .combine)
        }
    }

    private func refresh() {
        status = MacBatteryManager.shared.currentStatus()
    }

    private func batterySymbol(for percentage: Int) -> String {
        switch percentage {
        case ..<25: return "battery.25percent"
        case ..<50: return "battery.50percent"
        case ..<75: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

private struct MinimalisticHomeActivitiesView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var reminderManager = ReminderLiveActivityManager.shared
    @ObservedObject private var timerManager = TimerManager.shared
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.enableReminderLiveActivity) private var enableReminderLiveActivity
    @Default(.timerPresets) private var timerPresets

    var body: some View {
        VStack(spacing: 0) {
            timerCountdownSection
            if shouldShowReminderList {
                reminderList
            }
        }
    }

    private var reminderEntries: [ReminderLiveActivityManager.ReminderEntry] {
        reminderManager.activeWindowReminders
    }

    private var shouldShowReminderList: Bool {
        enableReminderLiveActivity && !reminderEntries.isEmpty
    }

    private var reminderListHeight: CGFloat {
        ReminderLiveActivityManager.additionalHeight(forRowCount: reminderEntries.count)
    }

    private var shouldShowTimerCountdown: Bool {
        coordinator.timerLiveActivityEnabled && timerManager.isExternalTimerActive
    }

    private var timerCountdownColor: Color {
        let baseColor: Color
        if let presetId = timerManager.activePresetId,
           let preset = timerPresets.first(where: { $0.id == presetId }) {
            baseColor = preset.color
        } else {
            baseColor = timerManager.timerColor
        }
        return baseColor.ensureMinimumBrightness(factor: 0.75).notchReadableTint()
    }

    private var timerCountdownText: String {
        timerManager.formattedRemainingTime()
    }

    private var timerDisplayName: String {
        let trimmed = timerManager.timerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Timer" : trimmed
    }

    private var timerCountdownSection: some View {
        VStack(spacing: 0) {
            if shouldShowTimerCountdown {
                timerCountdownView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, shouldShowTimerCountdown ? minimalisticTimerCountdownTopPadding : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: shouldShowTimerCountdown ? minimalisticTimerCountdownBlockHeight : 0, alignment: .top)
        .animation(.smooth(duration: 0.25), value: shouldShowTimerCountdown)
    }

    private func displayFont(size: CGFloat) -> Font {
        .custom("SF Pro Display", size: size)
    }

    private var timerCountdownView: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let preferredCountdownWidth = max(availableWidth * 0.42, 150)
            let maxCountdownWidth = max(availableWidth - 60, 0)
            let countdownWidth = min(preferredCountdownWidth, maxCountdownWidth)
            let marqueeWidth = max(availableWidth - countdownWidth - 12, 0)

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                MarqueeText(
                    .init(get: { timerDisplayName }, set: { _ in }),
                    font: .system(size: 16, weight: .semibold),
                    nsFont: .title3,
                    textColor: timerCountdownColor.opacity(0.85),
                    frameWidth: max(marqueeWidth, 1)
                )
                .alignmentGuide(.lastTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.bottom]
                }

                Spacer(minLength: 8)

                Text(timerCountdownText)
                    .font(displayFont(size: 56))
                    .monospacedDigit()
                    .foregroundStyle(timerManager.isOvertime ? Color.red : timerCountdownColor)
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.25), value: timerManager.remainingTime)
                    .lineLimit(1)
                    .frame(width: countdownWidth, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .frame(height: minimalisticTimerCountdownContentHeight, alignment: .top)
    }

    private var reminderList: some View {
        MinimalisticReminderEventListView(reminders: reminderEntries)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: reminderListHeight, alignment: .top)
            .opacity(shouldShowReminderList ? 1 : 0)
            .animation(.easeInOut(duration: 0.18), value: shouldShowReminderList)
            .environmentObject(vm)
    }

    private struct MinimalisticReminderEventListView: View {
        let reminders: [ReminderLiveActivityManager.ReminderEntry]

        private let textFont = Font.system(size: 13, weight: .regular)
        private let separatorSpacing: CGFloat = 10

        var body: some View {
            VStack(alignment: .leading, spacing: ReminderLiveActivityManager.listRowSpacing) {
                ForEach(reminders) { entry in
                    MinimalisticReminderEventRow(entry: entry, textFont: textFont, separatorSpacing: separatorSpacing)
                }
            }
            .padding(.top, ReminderLiveActivityManager.listTopPadding)
        }
    }

    private struct MinimalisticReminderEventRow: View {
        let entry: ReminderLiveActivityManager.ReminderEntry
        let textFont: Font
        let separatorSpacing: CGFloat

        @EnvironmentObject private var vm: DynamicIslandViewModel
        @State private var didCopyLink = false
        @State private var copyResetToken: UUID?
        @State private var isDetailsPopoverPresented = false
        @State private var isHoveringDetailsPopover = false

        private let indicatorHeight: CGFloat = 20

        private static let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter
        }()

        var body: some View {
            HStack(spacing: separatorSpacing) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(eventColor)
                    .frame(width: 8, height: indicatorHeight)

                HStack(spacing: 6) {
                    Text(entry.event.title)
                        .font(textFont)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    if let timeText {
                        Text(timeText)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                HStack(spacing: separatorSpacing) {
                    if let url = linkURL {
                        Button {
                            copyToClipboard(url: url)
                            triggerCopyFeedback()
                        } label: {
                            Image(systemName: didCopyLink ? "checkmark.circle.fill" : "link")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(didCopyLink ? Color.green : Color.primary.opacity(0.85))
                                .symbolRenderingMode(.monochrome)
                                .animation(.easeInOut(duration: 0.2), value: didCopyLink)
                        }
                        .buttonStyle(.plain)
                        .help("Copy event link")
                    }

                    if hasDetails {
                        Button {
                            isDetailsPopoverPresented.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isDetailsPopoverPresented, arrowEdge: .top) {
                            MinimalisticReminderDetailsView(
                                entry: entry,
                                linkURL: linkURL,
                                onHoverChanged: { hovering in
                                    isHoveringDetailsPopover = hovering
                                    updatePopoverActivity()
                                }
                            )
                            .onDisappear {
                                isHoveringDetailsPopover = false
                                updatePopoverActivity()
                            }
                        }
                        .onChange(of: isDetailsPopoverPresented) { _, presented in
                            if !presented {
                                isHoveringDetailsPopover = false
                                updatePopoverActivity()
                            }
                        }
                    }
                }
            }
            .frame(height: ReminderLiveActivityManager.listRowHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                openInCalendar()
            }
            .onDisappear {
                copyResetToken = nil
                didCopyLink = false
                vm.isReminderPopoverActive = false
            }
        }

        private var eventColor: Color {
            Color(nsColor: entry.event.calendar.color).ensureMinimumBrightness(factor: 0.7).notchReadableTint()
        }

        private var hasDetails: Bool {
            let location = entry.event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let notes = entry.event.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !location.isEmpty || !notes.isEmpty
        }

        private var linkURL: URL? {
            entry.event.url ?? entry.event.calendarAppURL()
        }

        private var timeText: String? {
            Self.timeFormatter.string(from: entry.event.start)
        }

        private func updatePopoverActivity() {
            vm.isReminderPopoverActive = isDetailsPopoverPresented && isHoveringDetailsPopover
        }

        private func triggerCopyFeedback() {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                didCopyLink = true
            }

            let token = UUID()
            copyResetToken = token

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [token] in
                guard copyResetToken == token else { return }

                withAnimation(.easeInOut(duration: 0.2)) {
                    didCopyLink = false
                }

                if copyResetToken == token {
                    copyResetToken = nil
                }
            }
        }

        private func copyToClipboard(url: URL) {
    #if canImport(AppKit)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.absoluteString, forType: .string)
    #endif
        }

        private func openInCalendar() {
    #if canImport(AppKit)
            guard let url = linkURL else { return }
            NSWorkspace.shared.open(url)
    #endif
        }
    }

    private struct MinimalisticReminderDetailsView: View {
        let entry: ReminderLiveActivityManager.ReminderEntry
        let linkURL: URL?
        var onHoverChanged: (Bool) -> Void = { _ in }

        private let detailFont = Font.system(size: 13, weight: .regular)
        private let smallLabelFont = Font.system(size: 12, weight: .semibold)
        private static let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter
        }()

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.event.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)

                VStack(alignment: .leading, spacing: 6) {
                    if let timeRange = timeRangeText {
                        detailRow(icon: "clock", label: "Time", value: timeRange)
                    }

                    if let location = entry.event.location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailRow(icon: "mappin.and.ellipse", label: "Location", value: location)
                    }

                    if let notes = entry.event.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailRow(icon: "note.text", label: "Notes", value: notes)
                    }
                }

                if let url = linkURL {
                    Button {
                        open(url: url)
                    } label: {
                        Label("Open in Calendar", systemImage: "arrow.up.right.square")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(16)
            .frame(minWidth: 220)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.notchBackground.opacity(0.92))
            )
            .onHover { hovering in
                onHoverChanged(hovering)
            }
            .onDisappear {
                onHoverChanged(false)
            }
        }

        private func detailRow(icon: String, label: String, value: String) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Label(label, systemImage: icon)
                    .font(smallLabelFont)
                    .foregroundStyle(Color.primary.opacity(0.8))
                Text(value)
                    .font(detailFont)
                    .foregroundStyle(Color.primary)
            }
        }

        private var timeRangeText: String? {
            let startText = Self.timeFormatter.string(from: entry.event.start)
            let endText = Self.timeFormatter.string(from: entry.event.end)
            return startText == endText ? startText : "\(startText) – \(endText)"
        }

        private func open(url: URL) {
    #if canImport(AppKit)
            NSWorkspace.shared.open(url)
    #endif
        }
    }
}
