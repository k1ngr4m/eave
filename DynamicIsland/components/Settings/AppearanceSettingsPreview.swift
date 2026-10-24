import AppKit
import Defaults
import SwiftUI

/// A passive example: preview navigation never opens the real notch or starts media/camera work.
struct AppearanceSettingsPreview: View {
    @Binding var expanded: Bool
    @Binding var screenName: String
    @State private var screens = NSScreen.screens
    @State private var systemScheme: ColorScheme = .dark
    @State private var replayTask: Task<Void, Never>?
    @State private var stageWidth: CGFloat = 688
    @Default(.notchAppearance) private var appearance
    @Default(.enableMinimalisticUI) private var minimalistic
    @Default(.closedNotchWidth) private var closedWidth
    @Default(.openNotchWidth) private var openWidth
    @Default(.customizeNonNotchWidth) private var customizeNonNotchWidth
    @Default(.customizeOpenNotchWidth) private var customizeOpenNotchWidth
    @Default(.customizePhysicalNotchWidth) private var customizeWidth
    @Default(.notchHeight) private var notchHeight
    @Default(.notchHeightMode) private var notchHeightMode
    @Default(.nonNotchHeight) private var nonNotchHeight
    @Default(.nonNotchHeightMode) private var nonNotchHeightMode
    @Default(.externalDisplayStyle) private var displayStyle
    @Default(.cornerRadiusScaling) private var scalesCorners
    @Default(.enableShadow) private var shadow
    @Default(.headerTabSpacing) private var tabSpacing
    @Default(.settingsIconInNotch) private var settingsIcon
    @Default(.useModernCloseAnimation) private var modernClose
    @Default(.showCalendar) private var calendar
    @Default(.dynamicShelf) private var shelf
    @Default(.enableTimerFeature) private var timer
    @Default(.timerDisplayMode) private var timerMode
    @Default(.enableStatsFeature) private var stats
    @Default(.enableStocksFeature) private var stocks
    @Default(.enableLLMUsageFeature) private var usage
    @Default(.enableNotes) private var notes
    @Default(.enableTerminalFeature) private var terminal
    @Default(.enableDeveloperTools) private var developerTools
    @Default(.showStandardMediaControls) private var media
    @Default(.showMirror) private var mirror
    @Default(.enablePerAppVolume) private var perAppVolume
    @Default(.showPerAppVolumeIcon) private var volumeIcon
    @Default(.enableCaffeinate) private var caffeinate
    @Default(.showCaffeinateIcon) private var caffeinateIcon

    private var screen: NSScreen? { screens.first { $0.localizedName == screenName } ?? screens.first }
    private var resolvedName: String? { screen?.localizedName }
    private var pill: Bool { shouldUseDynamicIslandMode(for: resolvedName) }
    private var closedSize: CGSize { getClosedNotchSize(screen: resolvedName) }
    private var scheme: ColorScheme { appearance.colorScheme(for: systemScheme) }
    private var expandedSize: CGSize {
        if minimalistic {
            return minimalisticBaseOpenNotchSize(for: .home, isDynamicIslandMode: pill, includesLyrics: false)
        }
        return getOpenNotchSize(screen: resolvedName)
    }
    private var size: CGSize { expanded ? expandedSize : closedSize }
    private var referenceWidth: CGFloat {
        minimalistic ? max(420, closedSize.width) : 900
    }
    private var surfaceHeight: CGFloat {
        let scale = AppearancePreviewGeometry.scale(stageWidth: stageWidth, referenceWidth: referenceWidth)
        return (max(expandedSize.height, closedSize.height, hardwareSize.height) + (pill ? dynamicIslandTopOffset : 0)) * scale + 16
    }
    private var hardwareSize: CGSize {
        guard let screen, screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return .zero }
        return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
    }
    private var shape: AnyShape {
        if pill {
            return AnyShape(DynamicIslandPillShape(cornerRadius: expanded
                ? (minimalistic ? minimalisticCornerRadiusInsets.opened.top : dynamicIslandPillCornerRadiusInsets.opened)
                : max(closedSize.height / 2, dynamicIslandPillCornerRadiusInsets.closed.standard)))
        }
        let radii = expanded && scalesCorners
            ? (minimalistic ? minimalisticCornerRadiusInsets.opened : cornerRadiusInsets.opened)
            : cornerRadiusInsets.closed
        return AnyShape(NotchShape(topCornerRadius: radii.top, bottomCornerRadius: radii.bottom))
    }
    private var sizeNote: String {
        if !expanded && hardwareSize.width > 0 && !customizeWidth { return String(localized: "Width follows the physical notch") }
        if expanded && minimalistic { return String(localized: "Minimalistic layout uses its own size") }
        if expanded && expandedSize.width < max(customizeOpenNotchWidth ? openWidth : 0, currentRecommendedMinimumNotchWidth()) {
            return String(localized: "Width limited by the preview display")
        }
        return expanded ? String(localized: "Minimum width accommodates enabled tabs") : String(localized: "Closed size without live activities")
    }

    var body: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack { screenPicker; Spacer(); previewControls }
                VStack(alignment: .leading, spacing: 8) { screenPicker; previewControls }
            }
            GeometryReader { geometry in
                let scale = AppearancePreviewGeometry.scale(stageWidth: geometry.size.width, referenceWidth: referenceWidth)
                VStack(spacing: 6) {
                    ZStack(alignment: .top) {
                        Rectangle().fill(.secondary.opacity(0.16)).frame(height: 1)
                        surface
                            .padding(.top, pill ? dynamicIslandTopOffset : 0)
                            .overlay(alignment: .top) {
                                if hardwareSize.width > 0 {
                                    NotchShape().fill(.black)
                                        .frame(width: hardwareSize.width, height: hardwareSize.height)
                                }
                            }
                            .environment(\.colorScheme, scheme)
                            .scaleEffect(scale, anchor: .top)
                            .frame(width: size.width * scale, height: surfaceHeight, alignment: .top)
                            .frame(maxWidth: .infinity, alignment: .top)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    HStack(spacing: 8) {
                        Text(verbatim: "\(Int(size.width)) × \(Int(size.height)) pt · \(Int(scale * 100))%")
                            .monospacedDigit()
                        Text("Sample content").foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                .padding(.top, 10)
                .onAppear { stageWidth = geometry.size.width }
                .onChange(of: geometry.size.width) { _, width in stageWidth = width }
            }
            .frame(height: surfaceHeight + 36)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            .clipped()
            Text(sizeNote).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onReceive(NSApp.publisher(for: \.effectiveAppearance)) { appearance in
            systemScheme = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
            if !screens.contains(where: { $0.localizedName == screenName }) {
                screenName = screens.first?.localizedName ?? ""
            }
        }
        .onAppear {
            if !screens.contains(where: { $0.localizedName == screenName }) {
                screenName = screens.first?.localizedName ?? ""
            }
        }
        .onDisappear { replayTask?.cancel() }
    }

    private var screenPicker: some View {
        Picker("Preview display", selection: $screenName) {
            ForEach(screens, id: \.localizedName) { screen in
                Text(screen.localizedName).tag(screen.localizedName)
            }
        }
        .fixedSize()
        .help("Only changes the preview display")
    }

    private var previewControls: some View {
        HStack(spacing: 8) {
            Picker("Preview state", selection: $expanded) {
                Text("Collapsed").tag(false)
                Text("Expanded").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 148)
            Button {
                replayTask?.cancel()
                expanded = true
                replayTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(650))
                    guard !Task.isCancelled else { return }
                    expanded = false
                }
            } label: { Image(systemName: "play.circle") }
            .buttonStyle(.plain)
            .accessibilityLabel("Replay close animation")
            .help("Replay close animation")
        }
    }

    private var surface: some View {
        VStack(spacing: 10) {
            if expanded {
                demoHeader.frame(height: max(24, closedSize.height))
                idleContent.padding(.horizontal, 24).padding(.bottom, 12)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.notchBackground)
        .clipShape(shape)
        .shadow(color: expanded && shadow ? .black.opacity(scheme == .light ? 0.18 : 0.6) : .clear,
                radius: scalesCorners ? 10 : 5)
        .animation(.spring(response: expanded || !modernClose ? 0.42 : 0.45, dampingFraction: 1), value: expanded)
    }

    private var demoHeader: some View {
        let exclusion = hardwareSize.width > 0
            ? max(closedSize.width, hardwareSize.width + 4)
            : (minimalistic ? 0 : min(closedSize.width, 300))
        let side = max(0, (size.width - exclusion - 52) / 2)
        return HStack(spacing: 0) {
            Group {
                if minimalistic {
                    HStack(spacing: 4) {
                        Image(systemName: "house.fill")
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        tabRow(spacing: tabSpacing)
                        tabRow(spacing: max(4, tabSpacing / 2))
                        tabRow(spacing: 4)
                        ScrollView(.horizontal) { tabRow(spacing: 4) }.scrollIndicators(.hidden)
                    }
                }
            }
            .frame(width: side, alignment: .leading)
            Color.clear.frame(width: exclusion)
            HStack(spacing: 8) {
                if !minimalistic {
                    if mirror { headerIcon("web.camera") }
                    if timer && timerMode == .popover { headerIcon("timer") }
                    if perAppVolume && volumeIcon { headerIcon("slider.vertical.3") }
                    if caffeinate && caffeinateIcon { headerIcon("cup.and.saucer") }
                    if settingsIcon { headerIcon("gearshape") }
                }
            }
            .frame(width: side, alignment: .trailing)
        }
        .padding(.horizontal, 26)
    }

    private func headerIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 30, height: 30)
    }

    private func tabRow(spacing: Double) -> some View {
        HStack(spacing: spacing) {
            ForEach(TabModel.availableTabs()) { tab in
                Image(systemName: tab.icon)
                    .font(.system(size: 12))
                    .frame(width: 20, height: 26)
                    .foregroundStyle(tab.id == TabModel.availableTabs().first?.id ? Color.primary : .gray)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var idleContent: some View {
        TimelineView(.periodic(from: Calendar.current.startOfDay(for: .now), by: 60)) { context in
            HomeClockView(date: context.date, compact: minimalistic)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
