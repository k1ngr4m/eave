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
import Defaults
import AppKit

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews

    init(label: String, icon: String, view: NotchViews) {
        self.id = "system-\(view.rawValue)"
        self.label = label
        self.icon = icon
        self.view = view
    }

    static func availableTabs() -> [TabModel] {
        var tabsArray = [TabModel(label: "Home", icon: "house.fill", view: .home)]

        if Defaults[.showStandardMediaControls] || Defaults[.enableMinimalisticUI] {
            tabsArray.append(TabModel(label: "Media", icon: "play.rectangle.fill", view: .media))
        }

        if Defaults[.showCalendar] {
            tabsArray.append(TabModel(label: "Calendar", icon: "calendar", view: .calendar))
        }

        if Defaults[.enableMinimalisticUI] { return tabsArray }

        if Defaults[.dynamicShelf] {
            tabsArray.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        
        if Defaults[.enableTimerFeature] && Defaults[.timerDisplayMode] == .tab {
            tabsArray.append(TabModel(label: "Timer", icon: "timer", view: .timer))
        }

        // Stats tab only shown when stats feature is enabled
        if Defaults[.enableStatsFeature] {
            tabsArray.append(TabModel(label: "Stats", icon: "gauge.with.dots.needle.33percent", view: .stats))
        }

        if Defaults[.enableStocksFeature] {
            tabsArray.append(TabModel(label: "Stocks", icon: "chart.line.uptrend.xyaxis", view: .stocks))
        }

        // Usage tab only shown when LLM usage feature is enabled
        if Defaults[.enableLLMUsageFeature] {
            tabsArray.append(TabModel(label: "Usage", icon: "chart.bar.doc.horizontal", view: .llmUsage))
        }

        if Defaults[.enableNotes] {
            tabsArray.append(TabModel(label: "Notes", icon: "note.text", view: .notes))
        }
        if Defaults[.enableTerminalFeature] {
            tabsArray.append(TabModel(label: "Terminal", icon: "apple.terminal", view: .terminal))
        }
        if Defaults[.enableDeveloperTools] {
            tabsArray.append(TabModel(label: "开发工具", icon: "curlybraces", view: .developerTools))
        }
        if Defaults[.enableProjectTasks] {
            tabsArray.append(TabModel(label: String(localized: "任务"), icon: "checklist", view: .tasks))
        }
        return tabsArray
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.headerTabSpacing) private var headerTabSpacing
    @Namespace var animation

    private var tabs: [TabModel] {
        coordinator.availableTabs
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabRow(spacing: CGFloat(headerTabSpacing))
            tabRow(spacing: CGFloat(max(4, headerTabSpacing / 2)))
            tabRow(spacing: 4)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    tabRow(spacing: 4)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    proxy.scrollTo(coordinator.currentView, anchor: .center)
                }
                .onChange(of: coordinator.currentView) { _, selection in
                    proxy.scrollTo(selection, anchor: .center)
                }
            }
        }
        .frame(height: 26)
        .onAppear {
            ensureValidSelection(with: coordinator.availableTabs)
        }
    }

    private func tabRow(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(tabs) { tab in
                let selected = isSelected(tab)
                TabButton(label: tab.label, icon: tab.icon, selected: selected) {
                    coordinator.currentView = tab.view
                }
                .frame(width: 20, height: 26)
                .foregroundStyle(selected ? Color.primary : .gray)
                .background {
                    if selected {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill).opacity(0.25))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    }
                }
                .id(tab.view)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        return coordinator.currentView == tab.view
    }

    private func ensureValidSelection(with tabs: [TabModel]) {
        guard !tabs.isEmpty else { return }
        if tabs.contains(where: { isSelected($0) }) {
            return
        }
        guard let first = tabs.first else { return }
        coordinator.currentView = first.view
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
