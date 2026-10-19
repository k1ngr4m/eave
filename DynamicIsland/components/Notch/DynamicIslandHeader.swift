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

import Defaults
import SwiftUI

struct DynamicIslandHeader: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @EnvironmentObject var webcamManager: WebcamManager
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var timerManager = TimerManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @ObservedObject var caffeinateManager = CaffeinateManager.shared
    @State private var showTimerPopover = false
    @State private var showPerAppVolumePopover = false
    @State private var showCaffeinatePopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.enablePerAppVolume) var enablePerAppVolume
    @Default(.showPerAppVolumeIcon) var showPerAppVolumeIcon
    @Default(.enableCaffeinate) var enableCaffeinate
    @Default(.showCaffeinateIcon) var showCaffeinateIcon
    @Default(.showBatteryIndicator) var showBatteryIndicator
    @Default(.showBatteryPercentInside) var showBatteryPercentInside
    @Default(.showMinimalisticBatteryIndicator) var showMinimalisticBatteryIndicator
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    
    /// Point size per symbol, so the row reads as one size.
    ///
    /// Equal point size is equal *cap height*, which is not equal optical size.
    /// Measured at 15pt medium: `gearshape` covers 289pt² of ink against
    /// `web.camera`'s 208 — 39% more. These sizes were solved so every glyph lands on
    /// 16pt of ink height, which is what actually makes a mixed row look even.
    private static let headerGlyphSizes: [String: CGFloat] = [
        "web.camera": 14.5,
        "timer": 14.4,
        "gearshape": 14.2,
        // Not solved against measured ink the way the others were: the three
        // sliders stand slightly taller than `timer`, so this trims to match.
        "slider.vertical.3": 13.8,
        // Unlike the sizes above, these two were not solved against measured
        // ink height -- they are the row default, nudged down because the cup
        // glyph carries a saucer and so reads a shade wider than `timer`.
        "cup.and.saucer": 14.0,
        "cup.and.saucer.fill": 14.0
    ]

    /// One glyph in the header row, on a common centre.
    ///
    /// The 20pt box leaves room for the symbols' full frames.
    private func headerGlyph(_ name: String, color: Color = Color.primary) -> some View {
        Image(systemName: name)
            .foregroundColor(color)
            .font(.system(size: Self.headerGlyphSizes[name] ?? 14.4, weight: .medium))
            .frame(width: 20, height: 20)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if !enableMinimalisticUI || coordinator.currentView == .calendar {
                    TabSelectionView()
                } else if Defaults[.showCalendar] {
                    Button { coordinator.currentView = .calendar } label: {
                        Image(systemName: "calendar")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Calendar")
                    .help("Calendar")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
            .padding(8)

            if vm.notchState == .open {
                let spacerWidth = min(vm.closedNotchSize.width, 300)
                Rectangle()
                    .fill(enableMinimalisticUI ? .clear : (NSScreen.screens
                        .first(where: { $0.localizedName == coordinator.selectedScreen })?.safeAreaInsets.top ?? 0 > 0 ? Color.notchBackground : .clear))
                    .frame(width: spacerWidth)
                    .mask {
                        NotchShape()
                    }
            }

            // 30pt targets sitting 4pt apart read as one run of buttons rather
            // than as separate ones; 8 is the gap Apple leaves between controls
            // of this size.
            HStack(spacing: 8) {
                if vm.notchState == .open && !enableMinimalisticUI {
                    if Defaults[.showMirror] {
                        Button(action: {
                            vm.toggleCameraPreview()
                        }) {
                            Capsule()
                                .fill(Color.notchBackground)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    headerGlyph("web.camera")
                                }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if Defaults[.enableTimerFeature] && timerDisplayMode == .popover {
                        Button(action: {
                            withAnimation(.smooth) {
                                showTimerPopover.toggle()
                            }
                        }) {
                            Capsule()
                                .fill(Color.notchBackground)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    headerGlyph("timer")
                                }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .popover(isPresented: $showTimerPopover, arrowEdge: .bottom) {
                            TimerPopover()
                        }
                        .onChange(of: showTimerPopover) { isActive in
                            vm.isTimerPopoverActive = isActive
                            if !isActive {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    vm.shouldRecheckHover.toggle()
                                }
                            }
                        }
                    }
                    
                    if enablePerAppVolume && showPerAppVolumeIcon {
                        Button(action: {
                            withAnimation(.smooth) {
                                showPerAppVolumePopover.toggle()
                            }
                        }) {
                            Capsule()
                                .fill(Color.notchBackground)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    headerGlyph("slider.vertical.3")
                                }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .popover(isPresented: $showPerAppVolumePopover, arrowEdge: .bottom) {
                            PerAppVolumePopover()
                        }
                        .onChange(of: showPerAppVolumePopover) { isActive in
                            vm.isPerAppVolumePopoverActive = isActive

                            if !isActive {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    vm.shouldRecheckHover.toggle()
                                }
                            }
                        }
                    }

                    if enableCaffeinate && showCaffeinateIcon {
                        Button(action: {
                            withAnimation(.smooth) {
                                showCaffeinatePopover.toggle()
                            }
                        }) {
                            Capsule()
                                .fill(Color.notchBackground)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    // Tinting the active state is the only
                                    // signal the closed row can give that the
                                    // Mac is being held awake, so it is not
                                    // just a filled-vs-hollow glyph swap.
                                    headerGlyph(
                                        caffeinateManager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                                        color: caffeinateManager.isActive ? .yellow : Color.primary
                                    )
                                }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .popover(isPresented: $showCaffeinatePopover, arrowEdge: .bottom) {
                            CaffeinatePopover()
                        }
                        .onChange(of: showCaffeinatePopover) { isActive in
                            vm.isCaffeinatePopoverActive = isActive

                            if !isActive {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    vm.shouldRecheckHover.toggle()
                                }
                            }
                        }
                    }

                    if Defaults[.settingsIconInNotch] {
                        Button(action: {
                            SettingsWindowController.shared.showWindow()
                        }) {
                            Capsule()
                                .fill(Color.notchBackground)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    headerGlyph("gearshape")
                                }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Screen Recording Indicator
                    if Defaults[.enableScreenRecordingDetection] && Defaults[.showRecordingIndicator] {
                        RecordingIndicator()
                            .frame(width: 30, height: 30) // Same size as other header elements
                    }

                    if Defaults[.enableDoNotDisturbDetection]
                        && Defaults[.showDoNotDisturbIndicator]
                        && doNotDisturbManager.isDoNotDisturbActive {
                        FocusIndicator()
                            .frame(width: 30, height: 30)
                            .transition(.opacity)
                    }
                }

                if vm.notchState == .open && showBatteryIndicator {
                    if enableMinimalisticUI {
                        // In minimalistic notch mode, show the battery pill only when
                        // showMinimalisticBatteryIndicator is enabled (and not DI mode).
                        if !shouldUseDynamicIslandMode(for: vm.screen) && showMinimalisticBatteryIndicator {
                            MinimalisticBatteryView(
                                levelBattery: batteryModel.levelBattery,
                                isPluggedIn: batteryModel.isPluggedIn,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                bodyWidth: 28,
                                bodyHeight: 14,
                                isForNotification: false,
                                showPercentInside: showBatteryPercentInside
                            )
                            .padding(.trailing, 4)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        }
                    } else {
                        DynamicIslandBatteryView(
                            batteryWidth: 30,
                            isCharging: batteryModel.isCharging,
                            isInLowPowerMode: batteryModel.isInLowPowerMode,
                            isPluggedIn: batteryModel.isPluggedIn,
                            levelBattery: batteryModel.levelBattery,
                            maxCapacity: batteryModel.maxCapacity,
                            timeToFullCharge: batteryModel.timeToFullCharge,
                            isForNotification: false
                        )
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(.smooth.delay(0.1), value: vm.notchState)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
        .onChange(of: enablePerAppVolume) { _, newValue in
            if !newValue {
                showPerAppVolumePopover = false
                vm.isPerAppVolumePopoverActive = false
            }
        }
        .onChange(of: enableCaffeinate) { _, newValue in
            if !newValue {
                showCaffeinatePopover = false
                vm.isCaffeinatePopoverActive = false
            }
        }
        .onChange(of: enableTimerFeature) { _, newValue in
            if !newValue {
                showTimerPopover = false
                vm.isTimerPopoverActive = false
            }
        }
        .onChange(of: timerDisplayMode) { _, mode in
            if mode == .tab {
                showTimerPopover = false
                vm.isTimerPopoverActive = false
            }
        }
    }
}

#Preview {
    DynamicIslandHeader()
        .environmentObject(DynamicIslandViewModel())
        .environmentObject(WebcamManager.shared)
}
