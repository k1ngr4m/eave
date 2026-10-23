//
//  SettingsView.swift
//  DynamicIsland
//
//  Created by Richard Kunkli on 07/08/2024.
//
import AppKit
import AVFoundation
import Combine
import Defaults
import EaveStatus
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import LottieUI
import SwiftUI
import SwiftUIIntrospect
import UniformTypeIdentifiers

/// Groups for organizing settings tabs in the sidebar.
private enum SettingsTabGroup: String, CaseIterable, Identifiable {
    case core, interface, efficiency, daily, system, development, other, info

    var id: String { rawValue }
    var title: String? {
        switch self {
        case .core: return nil
        case .interface: return String(localized: "Interface")
        case .efficiency: return String(localized: "Efficiency")
        case .daily: return String(localized: "Daily")
        case .system: return String(localized: "System")
        case .development: return String(localized: "Development")
        case .other: return String(localized: "Other")
        case .info: return nil
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case features
    case interaction
    case keepAwake
    case liveActivities
    case menuBar
    case appearance
    case lockScreen
    case media
    case devices
    case timer
    case calendar
    case hudAndOSD
    case stats
    case llmAgents
    case stocks
    case desktopPing
    case screenText
    case clipboard
    case shelf
    case shortcuts
    case notes
    case terminal
    case developerTools
    case about

    var id: String { rawValue }

    /// Which sidebar group this tab belongs to.
    var group: SettingsTabGroup {
        switch self {
        case .general, .features, .appearance, .interaction: return .core
        case .liveActivities, .menuBar, .lockScreen: return .interface
        case .clipboard, .screenText, .shelf, .notes: return .efficiency
        case .media, .timer, .calendar, .keepAwake: return .daily
        case .devices, .hudAndOSD, .stats: return .system
        case .llmAgents, .terminal, .developerTools: return .development
        case .stocks, .desktopPing: return .other
        case .shortcuts, .about: return .info
        }
    }

    var title: String {
        switch self {
        case .features: return String(localized: "Features")
        case .general: return String(localized: "General")
        case .menuBar: return String(localized: "Menu Bar & Dock")
        case .interaction: return String(localized: "Interaction & Displays")
        case .keepAwake: return String(localized: "Keep Awake")
        case .liveActivities: return String(localized: "Live Activities")
        case .appearance: return String(localized: "Appearance")
        case .lockScreen: return String(localized: "Lock Screen")
        case .media: return String(localized: "Media")
        case .devices: return String(localized: "Devices")
        case .timer: return String(localized: "Timer")
        case .calendar: return String(localized: "Calendar")
        case .hudAndOSD: return String(localized: "Volume & Brightness")
        case .clipboard: return String(localized: "Clipboard")
        case .screenText: return String(localized: "Copy text from screen")
        case .desktopPing: return String(localized: "Desktop Pings")
        case .stocks: return String(localized: "Stocks")
        case .stats: return String(localized: "Monitoring")
        case .llmAgents: return String(localized: "LLM Agents")
        case .shelf: return String(localized: "Shelf")
        case .shortcuts: return String(localized: "Shortcuts")
        case .notes: return String(localized: "Notes")
        case .developerTools: return "开发工具"
        case .terminal: return String(localized: "Terminal")
        case .about: return String(localized: "About")
        }
    }

    var systemImage: String {
        switch self {
        case .features: return "square.grid.2x2"
        case .general: return "gear"
        case .interaction: return "hand.draw"
        case .keepAwake: return "cup.and.saucer"
        case .menuBar: return "menubar.rectangle"
        case .liveActivities: return "waveform.path.ecg"
        case .appearance: return "paintpalette"
        case .lockScreen: return "lock.laptopcomputer"
        case .media: return "play.laptopcomputer"
        case .devices: return "headphones"
        case .timer: return "timer"
        case .calendar: return "calendar"
        case .hudAndOSD: return "dial.medium.fill"
        case .clipboard: return "doc.on.clipboard"
        case .screenText: return "text.viewfinder"
        case .desktopPing: return "scope"
        case .stocks: return "chart.line.uptrend.xyaxis"
        case .stats: return "gauge.with.dots.needle.33percent"
        case .llmAgents: return "sparkles"
        case .shelf: return "books.vertical"
        case .shortcuts: return "keyboard"
        case .notes: return "note.text"
        case .developerTools: return "curlybraces"
        case .terminal: return "apple.terminal"
        case .about: return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .features: return .blue
        case .general: return .blue
        case .interaction: return .blue
        case .keepAwake: return .brown
        case .menuBar: return .teal
        case .liveActivities: return .pink
        case .appearance: return .purple
        case .lockScreen: return .orange
        case .media: return .green
        case .devices: return Color(red: 0.1, green: 0.11, blue: 0.12)
        case .timer: return .red
        case .calendar: return .cyan
        case .hudAndOSD: return .indigo
        case .clipboard: return .blue
        case .screenText: return .blue
        case .desktopPing: return .cyan
        case .stocks: return .red
        case .stats: return .teal
        case .llmAgents: return .purple
        case .shelf: return .brown
        case .shortcuts: return .orange
        case .notes: return Color(red: 0.979, green: 0.716, blue: 0.153, opacity: 1.000)
        case .developerTools: return .blue
        case .terminal: return Color(red: 0.2, green: 0.8, blue: 0.4)
        case .about: return .secondary
        }
    }

    var sidebarTab: SettingsTab {
        switch self {
        case .appearance, .interaction: return .appearance
        default: return self
        }
    }

    func highlightID(for title: String) -> String {
        "\(rawValue)-\(title)"
    }
}

private struct SettingsSearchEntry: Identifiable {
    let tab: SettingsTab
    let title: String
    let keywords: [String]
    let highlightID: String?
    var id: String { "\(tab.rawValue)-\(title)" }
}

private enum SettingsSearchIndex {
    static let entries: [SettingsSearchEntry] = [
        SettingsSearchEntry(tab: .developerTools, title: "开发工具 / JSON 美化", keywords: ["json", "developer", "格式化", "开发工具", "校验"], highlightID: nil),
        SettingsSearchEntry(tab: .desktopPing, title: "Desktop Pings", keywords: ["lolping", "ping", "wheel", "signal", "pause", "轮盘", "信号", "暫停", "訊號"], highlightID: nil),
        SettingsSearchEntry(tab: .media, title: "Show music perimeter progress", keywords: ["music", "progress", "perimeter", "歌曲", "外围", "进度条", "外圍", "進度條"], highlightID: SettingsTab.media.highlightID(for: "Show music perimeter progress")),
        SettingsSearchEntry(tab: .menuBar, title: "Use three-in-one status icon", keywords: ["菜单栏", "三合一"], highlightID: SettingsTab.menuBar.highlightID(for: "Use three-in-one status icon")),
        SettingsSearchEntry(tab: .menuBar, title: "Show dynamic status icon in Dock", keywords: ["dock", "程序坞"], highlightID: SettingsTab.menuBar.highlightID(for: "Show dynamic status icon in Dock")),
        SettingsSearchEntry(tab: .interaction, title: "Horizontal media gestures", keywords: ["手势", "media"], highlightID: SettingsTab.interaction.highlightID(for: "Horizontal media gestures")),
        SettingsSearchEntry(tab: .interaction, title: "Gesture skip behavior", keywords: ["手势", "skip"], highlightID: SettingsTab.interaction.highlightID(for: "Gesture skip behavior")),
        // General
        SettingsSearchEntry(tab: .features, title: "Enable minimalistic UI", keywords: ["minimalistic", "ui mode", "general"], highlightID: SettingsTab.features.highlightID(for: "Enable minimalistic UI")),
        SettingsSearchEntry(tab: .menuBar, title: "Show menu bar icon", keywords: ["menu bar", "status bar", "icon"], highlightID: SettingsTab.menuBar.highlightID(for: "Show menu bar icon")),
        SettingsSearchEntry(tab: .general, title: "Launch at login", keywords: ["autostart", "startup"], highlightID: SettingsTab.general.highlightID(for: "Launch at login")),
        SettingsSearchEntry(tab: .general, title: "Language", keywords: ["locale", "translation", "system", "语言", "語言"], highlightID: SettingsTab.general.highlightID(for: "Language")),
        SettingsSearchEntry(tab: .interaction, title: "Show on all displays", keywords: ["multi-display", "external monitor"], highlightID: SettingsTab.interaction.highlightID(for: "Show on all displays")),
        SettingsSearchEntry(tab: .interaction, title: "Show on a specific display", keywords: ["preferred screen", "display picker"], highlightID: SettingsTab.interaction.highlightID(for: "Show on a specific display")),
        SettingsSearchEntry(tab: .interaction, title: "Automatically switch displays", keywords: ["auto switch", "displays"], highlightID: SettingsTab.interaction.highlightID(for: "Automatically switch displays")),
        SettingsSearchEntry(tab: .interaction, title: "Hide Dynamic Island during screenshots & recordings", keywords: ["privacy", "screenshot", "recording"], highlightID: SettingsTab.interaction.highlightID(for: "Hide Dynamic Island during screenshots & recordings")),
        SettingsSearchEntry(tab: .keepAwake, title: "Enable Keep Awake", keywords: ["caffeinate", "keep awake", "prevent sleep", "insomnia", "no sleep"], highlightID: SettingsTab.keepAwake.highlightID(for: "Enable Keep Awake")),
        SettingsSearchEntry(tab: .keepAwake, title: "Show Keep Awake icon in the notch", keywords: ["caffeinate", "keep awake", "icon", "notch"], highlightID: SettingsTab.keepAwake.highlightID(for: "Show Keep Awake icon in the notch")),
        SettingsSearchEntry(tab: .keepAwake, title: "Default duration", keywords: ["caffeinate", "keep awake", "duration", "timeout"], highlightID: SettingsTab.keepAwake.highlightID(for: "Default duration")),
        SettingsSearchEntry(tab: .keepAwake, title: "Also keep the display awake", keywords: ["caffeinate", "keep awake", "display sleep", "screen"], highlightID: SettingsTab.keepAwake.highlightID(for: "Also keep the display awake")),
        SettingsSearchEntry(tab: .interaction, title: "Enable gestures", keywords: ["gestures", "trackpad"], highlightID: SettingsTab.interaction.highlightID(for: "Enable gestures")),
        SettingsSearchEntry(tab: .interaction, title: "Enable close gesture", keywords: ["pinch", "swipe"], highlightID: SettingsTab.interaction.highlightID(for: "Enable close gesture")),
        SettingsSearchEntry(tab: .interaction, title: "Reverse swipe gestures", keywords: ["reverse", "swipe", "media"], highlightID: SettingsTab.interaction.highlightID(for: "Reverse swipe gestures")),
        SettingsSearchEntry(tab: .interaction, title: "Reverse scroll gestures", keywords: ["reverse", "scroll", "open", "close"], highlightID: SettingsTab.interaction.highlightID(for: "Reverse scroll gestures")),
        SettingsSearchEntry(tab: .appearance, title: "Extend hover area", keywords: ["hover", "cursor"], highlightID: SettingsTab.appearance.highlightID(for: "Extend hover area")),
        SettingsSearchEntry(tab: .appearance, title: "Enable haptics", keywords: ["haptic", "feedback"], highlightID: SettingsTab.appearance.highlightID(for: "Enable haptics")),
        SettingsSearchEntry(tab: .appearance, title: "When reopening", keywords: ["reopen", "last tab", "default tab", "重新打开", "上次的页面"], highlightID: SettingsTab.appearance.highlightID(for: "When reopening")),
        SettingsSearchEntry(tab: .appearance, title: "Keep expanded", keywords: ["keep open", "pin", "保持展开", "常驻"], highlightID: SettingsTab.appearance.highlightID(for: "Keep expanded")),
        SettingsSearchEntry(tab: .appearance, title: "Open notch on hover", keywords: ["hover to open", "auto open"], highlightID: SettingsTab.appearance.highlightID(for: "Open notch on hover")),
        SettingsSearchEntry(tab: .appearance, title: "External display style", keywords: ["dynamic island", "pill", "external display", "non-notch", "floating", "capsule"], highlightID: SettingsTab.appearance.highlightID(for: "External display style")),
        SettingsSearchEntry(tab: .appearance, title: "Hide until hovered", keywords: ["hide", "hover", "external", "non-notch", "auto hide", "slide"], highlightID: SettingsTab.appearance.highlightID(for: "Hide until hovered")),
        SettingsSearchEntry(tab: .appearance, title: "Notch display height", keywords: ["display height", "menu bar size"], highlightID: SettingsTab.appearance.highlightID(for: "Notch display height")),

        // Live Activities
        SettingsSearchEntry(tab: .liveActivities, title: "Enable download detection", keywords: ["downloads", "下载", "detection"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable download detection")),
        SettingsSearchEntry(tab: .liveActivities, title: "Download indicator style", keywords: ["downloads", "下载", "progress ring"], highlightID: SettingsTab.liveActivities.highlightID(for: "Download indicator style")),
        SettingsSearchEntry(tab: .liveActivities, title: "Show download speed", keywords: ["downloads", "下载", "speed"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show download speed")),
        SettingsSearchEntry(tab: .liveActivities, title: "Enable screen recording detection", keywords: ["screen recording", "indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable screen recording detection")),
        SettingsSearchEntry(tab: .liveActivities, title: "Show recording indicator", keywords: ["recording indicator", "red dot"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show recording indicator")),
        SettingsSearchEntry(tab: .liveActivities, title: "Recording Controls", keywords: ["screen recording", "stop button", "indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Recording Controls")),
        SettingsSearchEntry(tab: .liveActivities, title: "Recording Hover Style", keywords: ["screen recording", "hover", "inline", "stop"], highlightID: SettingsTab.liveActivities.highlightID(for: "Recording Hover Style")),
        SettingsSearchEntry(tab: .liveActivities, title: "Enable Focus detection", keywords: ["focus", "do not disturb", "dnd"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Focus detection")),
        SettingsSearchEntry(tab: .liveActivities, title: "Show Focus indicator", keywords: ["focus icon", "moon"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Focus indicator")),
        SettingsSearchEntry(tab: .liveActivities, title: "Show Focus label", keywords: ["focus label", "text"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Focus label")),
        SettingsSearchEntry(tab: .liveActivities, title: "Enable camera detection", keywords: ["camera", "privacy indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable camera detection")),
        SettingsSearchEntry(tab: .liveActivities, title: "Enable microphone detection", keywords: ["microphone", "privacy"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable microphone detection")),
        SettingsSearchEntry(tab: .liveActivities, title: "Enable music live activity", keywords: ["music", "now playing"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable music live activity")),
        SettingsSearchEntry(tab: .liveActivities, title: "Enable reminder live activity", keywords: ["reminder", "live activity"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable reminder live activity")),

        SettingsSearchEntry(tab: .menuBar, title: "Menu Bar", keywords: ["status", "trio", "wifi", "network", "bluetooth", "volume", "battery", "菜单栏", "状态面板", "三合一", "蓝牙"], highlightID: nil),
        SettingsSearchEntry(tab: .general, title: "Use three-in-one status icon", keywords: ["trio", "status icon", "menu bar", "三合一"], highlightID: SettingsTab.general.highlightID(for: "Use three-in-one status icon")),
        // Battery alerts
        SettingsSearchEntry(tab: .liveActivities, title: "Show battery alerts", keywords: ["notifications", "power"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show battery alerts")),
        SettingsSearchEntry(tab: .liveActivities, title: "Play low battery alert sound", keywords: ["low battery", "alert", "sound"], highlightID: SettingsTab.liveActivities.highlightID(for: "Play low battery alert sound")),
        SettingsSearchEntry(tab: .liveActivities, title: "Show charging HUD", keywords: ["battery", "charging", "temporary activity"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show charging HUD")),
        SettingsSearchEntry(tab: .liveActivities, title: "Show low battery HUD", keywords: ["battery", "low", "temporary activity"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show low battery HUD")),
        SettingsSearchEntry(tab: .liveActivities, title: "Show fully charged HUD", keywords: ["battery", "full", "temporary activity"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show fully charged HUD")),
        SettingsSearchEntry(tab: .liveActivities, title: "Charging duration", keywords: ["charging", "duration", "seconds"], highlightID: SettingsTab.liveActivities.highlightID(for: "Charging duration")),
        SettingsSearchEntry(tab: .liveActivities, title: "Low battery duration", keywords: ["low battery", "duration", "seconds"], highlightID: SettingsTab.liveActivities.highlightID(for: "Low battery duration")),
        SettingsSearchEntry(tab: .liveActivities, title: "Full battery duration", keywords: ["full battery", "duration", "seconds"], highlightID: SettingsTab.liveActivities.highlightID(for: "Full battery duration")),
        SettingsSearchEntry(tab: .liveActivities, title: "Test charging HUD", keywords: ["battery", "test", "charging", "preview"], highlightID: SettingsTab.liveActivities.highlightID(for: "Test charging HUD")),
        SettingsSearchEntry(tab: .liveActivities, title: "Test low battery HUD", keywords: ["battery", "test", "low", "preview"], highlightID: SettingsTab.liveActivities.highlightID(for: "Test low battery HUD")),
        SettingsSearchEntry(tab: .liveActivities, title: "Test full battery HUD", keywords: ["battery", "test", "full", "preview"], highlightID: SettingsTab.liveActivities.highlightID(for: "Test full battery HUD")),
        SettingsSearchEntry(tab: .liveActivities, title: "Low battery style", keywords: ["battery", "style", "compact", "standard"], highlightID: SettingsTab.liveActivities.highlightID(for: "Low battery style")),
        SettingsSearchEntry(tab: .liveActivities, title: "Low battery threshold", keywords: ["battery", "threshold", "percent"], highlightID: SettingsTab.liveActivities.highlightID(for: "Low battery threshold")),
        SettingsSearchEntry(tab: .liveActivities, title: "Full battery style", keywords: ["battery", "style", "compact", "standard"], highlightID: SettingsTab.liveActivities.highlightID(for: "Full battery style")),
        SettingsSearchEntry(tab: .liveActivities, title: "Full charge threshold", keywords: ["battery", "threshold", "full"], highlightID: SettingsTab.liveActivities.highlightID(for: "Full charge threshold")),
        SettingsSearchEntry(tab: .devices, title: "Enable per-app volume", keywords: ["per app volume", "app volume", "mixer", "audio", "mute app"], highlightID: SettingsTab.devices.highlightID(for: "Enable per-app volume")),
        SettingsSearchEntry(tab: .devices, title: "Show app volume icon in the notch", keywords: ["per app volume", "icon", "notch", "mixer"], highlightID: SettingsTab.devices.highlightID(for: "Show app volume icon in the notch")),
        SettingsSearchEntry(tab: .devices, title: "Reset all app volumes", keywords: ["per app volume", "reset", "mixer"], highlightID: SettingsTab.devices.highlightID(for: "Reset all app volumes")),

        // HUDs
        SettingsSearchEntry(tab: .devices, title: "Show Bluetooth device connections", keywords: ["bluetooth", "hud"], highlightID: SettingsTab.devices.highlightID(for: "Show Bluetooth device connections")),
        SettingsSearchEntry(tab: .devices, title: "Use circular battery indicator", keywords: ["battery", "circular"], highlightID: SettingsTab.devices.highlightID(for: "Use circular battery indicator")),
        SettingsSearchEntry(tab: .devices, title: "Show battery percentage text in HUD", keywords: ["battery text"], highlightID: SettingsTab.devices.highlightID(for: "Show battery percentage text in HUD")),
        SettingsSearchEntry(tab: .devices, title: "Scroll device name in HUD", keywords: ["marquee", "device name"], highlightID: SettingsTab.devices.highlightID(for: "Scroll device name in HUD")),
        SettingsSearchEntry(tab: .devices, title: "Use 3D Bluetooth HUD icon", keywords: ["bluetooth", "3d", "animation", "mov"], highlightID: SettingsTab.devices.highlightID(for: "Use 3D Bluetooth HUD icon")),
        SettingsSearchEntry(tab: .devices, title: "Use color-coded battery display", keywords: ["color", "battery"], highlightID: SettingsTab.devices.highlightID(for: "Use color-coded battery display")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Enable system control overlays", keywords: ["hud", "osd", "enable", "系统控制提示"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable system control overlays")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Use color-coded volume display", keywords: ["volume", "color"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Use color-coded volume display")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Use smooth color transitions", keywords: ["gradient", "smooth"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Use smooth color transitions")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Show percentages beside progress bars", keywords: ["percentages", "progress"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Show percentages beside progress bars")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "HUD style", keywords: ["inline", "compact"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "HUD style")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Progressbar style", keywords: ["progress", "style"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Progressbar style")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Enable glowing effect", keywords: ["glow", "indicator"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable glowing effect")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Use accent color", keywords: ["accent", "color"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Use accent color")),

        // Custom OSD
        SettingsSearchEntry(tab: .hudAndOSD, title: "Enable Custom OSD", keywords: ["osd", "on-screen display", "custom osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable Custom OSD")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Show volume OSD", keywords: ["volume", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Show volume OSD")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Show brightness OSD", keywords: ["brightness", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Show brightness OSD")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Show keyboard backlight OSD", keywords: ["keyboard", "backlight", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Show keyboard backlight OSD")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Material", keywords: ["material", "frosted", "liquid", "glass", "solid", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Material")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Icon & Progress Color", keywords: ["color", "icon", "white", "black", "gray", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Icon & Progress Color")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Volume step", keywords: ["volume", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume step")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Volume fine step", keywords: ["volume", "fine", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume fine step")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Brightness step", keywords: ["brightness", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness step")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Brightness fine step", keywords: ["brightness", "fine", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness fine step")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Third-party DDC app integration", keywords: ["ddc", "third party", "external", "display", "betterdisplay", "lunar"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Third-party DDC app integration")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Third-party DDC provider", keywords: ["provider", "betterdisplay", "lunar", "integration", "refresh detection"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Third-party DDC provider")),
        SettingsSearchEntry(tab: .hudAndOSD, title: "Enable external volume control listener", keywords: ["external volume", "ddc volume", "betterdisplay volume", "lunar volume", "disable native volume"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable external volume control listener")),

        // Media
        SettingsSearchEntry(tab: .media, title: "Music Source", keywords: ["media source", "controller"], highlightID: SettingsTab.media.highlightID(for: "Music Source")),
        SettingsSearchEntry(tab: .media, title: "Skip buttons", keywords: ["skip", "controls", "±10"], highlightID: SettingsTab.media.highlightID(for: "Skip buttons")),
        SettingsSearchEntry(tab: .media, title: "Sneak Peek Style", keywords: ["sneak peek", "preview"], highlightID: SettingsTab.media.highlightID(for: "Sneak Peek Style")),
        SettingsSearchEntry(tab: .media, title: "Pinned lyric font size", keywords: ["lyrics", "font", "size", "歌词", "字体", "字号"], highlightID: SettingsTab.media.highlightID(for: "Pinned lyric font size")),
        SettingsSearchEntry(tab: .media, title: "Pinned lyric context", keywords: ["pinned lyrics", "lyric context", "lyrics lines", "closed notch", "lyrics height"], highlightID: SettingsTab.media.highlightID(for: "Pinned lyric context")),
        SettingsSearchEntry(tab: .media, title: "Keep lyrics under the closed notch", keywords: ["lyrics", "pin", "pinned", "closed notch", "always show"], highlightID: SettingsTab.media.highlightID(for: "Keep lyrics under the closed notch")),
        SettingsSearchEntry(tab: .media, title: "Show lyrics", keywords: ["lyrics", "song text", "side panel", "calendar", "inline"], highlightID: SettingsTab.media.highlightID(for: "Show lyrics")),
        // Targets the lyrics toggle rather than the Highlight picker: the picker
        // only exists while lyrics are on, so a search result pointing at it
        // scrolls to nothing for anyone who has not turned them on yet -- which
        // is everyone, by default.
        SettingsSearchEntry(tab: .media, title: "Lyrics script", keywords: ["lyrics", "simplified", "traditional", "original", "简体", "繁体", "原文"], highlightID: SettingsTab.media.highlightID(for: "Show lyrics")),
        SettingsSearchEntry(tab: .media, title: "Lyrics timing adjustment", keywords: ["lyrics", "sync", "delay", "advance", "歌词", "快慢"], highlightID: SettingsTab.media.highlightID(for: "Show lyrics")),
        SettingsSearchEntry(tab: .media, title: "Lyric highlight", keywords: ["lyrics", "highlight", "sweep", "gradient", "solid", "karaoke", "animation"], highlightID: SettingsTab.media.highlightID(for: "Show lyrics")),
        SettingsSearchEntry(tab: .media, title: "Side lyrics width", keywords: ["lyrics", "width", "panel"], highlightID: SettingsTab.media.highlightID(for: "Side lyrics width")),
        SettingsSearchEntry(tab: .media, title: "Side lyrics horizontal offset", keywords: ["lyrics", "offset", "panel"], highlightID: SettingsTab.media.highlightID(for: "Side lyrics horizontal offset")),
        SettingsSearchEntry(tab: .media, title: "Show live canvas in Dynamic Island", keywords: ["canvas", "live canvas", "album art", "dynamic island", "spotify canvas"], highlightID: SettingsTab.media.highlightID(for: "Show live canvas in Dynamic Island")),
        SettingsSearchEntry(tab: .media, title: "Auto-hide inactive notch media player", keywords: ["auto hide", "inactive", "placeholder", "notch media"], highlightID: SettingsTab.media.highlightID(for: "Auto-hide inactive notch media player")),
        SettingsSearchEntry(tab: .media, title: "Show Change Media Output control", keywords: ["airplay", "route picker", "media output"], highlightID: SettingsTab.media.highlightID(for: "Show Change Media Output control")),
        SettingsSearchEntry(tab: .lockScreen, title: "Enable album art parallax", keywords: ["parallax", "lock screen", "album art"], highlightID: SettingsTab.lockScreen.highlightID(for: "Enable album art parallax")),
        SettingsSearchEntry(tab: .media, title: "Enable album art parallax effect", keywords: ["parallax", "parallax effect", "album art"], highlightID: SettingsTab.media.highlightID(for: "Enable album art parallax effect")),

        // Calendar
        SettingsSearchEntry(tab: .calendar, title: "Enable calendar", keywords: ["calendar", "events"], highlightID: SettingsTab.calendar.highlightID(for: "Enable calendar")),
        SettingsSearchEntry(tab: .calendar, title: "Enable reminder live activity", keywords: ["reminder", "live activity"], highlightID: SettingsTab.calendar.highlightID(for: "Enable reminder live activity")),
        SettingsSearchEntry(tab: .calendar, title: "Countdown style", keywords: ["reminder countdown"], highlightID: SettingsTab.calendar.highlightID(for: "Countdown style")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen reminder", keywords: ["lock screen", "reminder widget"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen reminder")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show next calendar event", keywords: ["calendar widget", "lock screen", "next event"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show next calendar event")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show events within the next", keywords: ["calendar widget", "lookahead"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show events within the next")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show events from all calendars", keywords: ["calendar widget", "selection"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show events from all calendars")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show countdown", keywords: ["calendar widget", "countdown"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show countdown")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show event for entire duration", keywords: ["calendar widget", "duration"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show event for entire duration")),
        SettingsSearchEntry(tab: .lockScreen, title: "Hide active event and show next upcoming event", keywords: ["calendar widget", "after start"], highlightID: SettingsTab.lockScreen.highlightID(for: "Hide active event and show next upcoming event")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show time remaining", keywords: ["calendar widget", "remaining"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show time remaining")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show start time after event begins", keywords: ["calendar widget", "start time"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show start time after event begins")),
        SettingsSearchEntry(tab: .lockScreen, title: "Chip color", keywords: ["reminder chip", "color"], highlightID: SettingsTab.lockScreen.highlightID(for: "Chip color")),
        SettingsSearchEntry(tab: .calendar, title: "Hide all-day events", keywords: ["calendar", "all-day"], highlightID: SettingsTab.calendar.highlightID(for: "Hide all-day events")),
        SettingsSearchEntry(tab: .calendar, title: "Hide completed reminders", keywords: ["reminder", "completed"], highlightID: SettingsTab.calendar.highlightID(for: "Hide completed reminders")),
        SettingsSearchEntry(tab: .calendar, title: "Show full event titles", keywords: ["calendar", "titles"], highlightID: SettingsTab.calendar.highlightID(for: "Show full event titles")),
        SettingsSearchEntry(tab: .calendar, title: "Auto-scroll to next event", keywords: ["calendar", "scroll"], highlightID: SettingsTab.calendar.highlightID(for: "Auto-scroll to next event")),

        // Shelf
        SettingsSearchEntry(tab: .shelf, title: "Enable shelf", keywords: ["shelf", "dock"], highlightID: SettingsTab.shelf.highlightID(for: "Enable shelf")),
        SettingsSearchEntry(tab: .shelf, title: "Expand drag detection area", keywords: ["shelf", "drag"], highlightID: SettingsTab.shelf.highlightID(for: "Expand drag detection area")),
        SettingsSearchEntry(tab: .shelf, title: "Copy items on drag", keywords: ["shelf", "drag", "copy"], highlightID: SettingsTab.shelf.highlightID(for: "Copy items on drag")),
        SettingsSearchEntry(tab: .shelf, title: "Remove from shelf after dragging", keywords: ["shelf", "drag", "remove"], highlightID: SettingsTab.shelf.highlightID(for: "Remove from shelf after dragging")),
        SettingsSearchEntry(tab: .shelf, title: "Quick Share Service", keywords: ["shelf", "share", "airdrop", "localsend"], highlightID: SettingsTab.shelf.highlightID(for: "Quick Share Service")),
        SettingsSearchEntry(tab: .shelf, title: "LocalSend Device Picker Style", keywords: ["localsend", "glass", "picker", "material"], highlightID: SettingsTab.shelf.highlightID(for: "Device Picker Style")),

        // Appearance
        SettingsSearchEntry(tab: .appearance, title: "Notch appearance", keywords: ["light", "dark", "system", "theme", "浅色", "深色", "跟随系统", "淺色", "跟隨系統", "刘海", "瀏海"], highlightID: SettingsTab.appearance.highlightID(for: "Notch appearance")),
        SettingsSearchEntry(tab: .appearance, title: "Main screen style", keywords: ["dynamic island", "pill", "non-notch", "display style", "notch style"], highlightID: SettingsTab.appearance.highlightID(for: "Main screen style")),
        SettingsSearchEntry(tab: .appearance, title: "Show settings icon in the notch", keywords: ["settings button", "toolbar"], highlightID: SettingsTab.appearance.highlightID(for: "Show settings icon in the notch")),
        SettingsSearchEntry(tab: .appearance, title: "Top tab spacing", keywords: ["tabs", "icons", "spacing", "刘海", "间距", "图标"], highlightID: SettingsTab.appearance.highlightID(for: "Top tab spacing")),
        SettingsSearchEntry(tab: .appearance, title: "Enable window shadow", keywords: ["shadow", "appearance"], highlightID: SettingsTab.appearance.highlightID(for: "Enable window shadow")),
        SettingsSearchEntry(tab: .appearance, title: "Scale corner radius with notch size", keywords: ["corner radius", "shape"], highlightID: SettingsTab.appearance.highlightID(for: "Scale corner radius with notch size")),
        SettingsSearchEntry(tab: .appearance, title: "Use simpler close animation", keywords: ["close animation", "notch"], highlightID: SettingsTab.appearance.highlightID(for: "Use simpler close animation")),
        SettingsSearchEntry(tab: .appearance, title: "Notch Width", keywords: ["expanded notch", "width", "resize"], highlightID: SettingsTab.appearance.highlightID(for: "Expanded notch width")),
        SettingsSearchEntry(tab: .media, title: "Use colored spectrograms", keywords: ["spectrogram", "audio"], highlightID: SettingsTab.media.highlightID(for: "Use colored spectrograms")),
        SettingsSearchEntry(tab: .media, title: "Enable blur effect behind album art", keywords: ["blur", "album art"], highlightID: SettingsTab.media.highlightID(for: "Enable blur effect behind album art")),
        SettingsSearchEntry(tab: .media, title: "Slider color", keywords: ["slider", "accent"], highlightID: SettingsTab.media.highlightID(for: "Slider color")),
        SettingsSearchEntry(tab: .appearance, title: "Enable dynamic mirror", keywords: ["mirror", "reflection"], highlightID: SettingsTab.appearance.highlightID(for: "Enable dynamic mirror")),
        SettingsSearchEntry(tab: .appearance, title: "Mirror shape", keywords: ["mirror shape", "circle", "rectangle"], highlightID: SettingsTab.appearance.highlightID(for: "Mirror shape")),
        SettingsSearchEntry(tab: .appearance, title: "Enable idle animation", keywords: ["face animation", "idle", "cool face"], highlightID: SettingsTab.appearance.highlightID(for: "Enable idle animation")),
        SettingsSearchEntry(tab: .appearance, title: "App icon", keywords: ["app icon", "custom icon"], highlightID: SettingsTab.appearance.highlightID(for: "App icon")),

        // Lock Screen
        SettingsSearchEntry(tab: .lockScreen, title: "After an event starts", keywords: ["calendar", "日历", "事件开始"], highlightID: SettingsTab.lockScreen.highlightID(for: "After an event starts")),
        SettingsSearchEntry(tab: .lockScreen, title: "Lock Screen Positioning", keywords: ["layout", "position", "width", "布局", "位置", "宽度"], highlightID: SettingsTab.lockScreen.highlightID(for: "Lock Screen Positioning")),
        SettingsSearchEntry(tab: .lockScreen, title: "Siri detection speed", keywords: ["Siri", "检测", "速度"], highlightID: SettingsTab.lockScreen.highlightID(for: "Siri detection speed")),
        SettingsSearchEntry(tab: .lockScreen, title: "Preview lock screen widgets", keywords: ["preview", "lock screen", "widgets"], highlightID: SettingsTab.lockScreen.highlightID(for: "Preview lock screen widgets")),
        SettingsSearchEntry(tab: .lockScreen, title: "Widget appearance", keywords: ["appearance", "theme", "dark", "light", "contrast", "wallpaper"], highlightID: SettingsTab.lockScreen.highlightID(for: "Widget appearance")),
        SettingsSearchEntry(tab: .lockScreen, title: "Enable lock screen live activity", keywords: ["lock screen", "live activity"], highlightID: SettingsTab.lockScreen.highlightID(for: "Enable lock screen live activity")),
        SettingsSearchEntry(tab: .lockScreen, title: "Live activity icon", keywords: ["lock", "fingerprint", "touch id", "unlock", "biometric", "icon style"], highlightID: SettingsTab.lockScreen.highlightID(for: "Live activity icon")),
        SettingsSearchEntry(tab: .lockScreen, title: "Play lock/unlock sounds", keywords: ["chime", "sound"], highlightID: SettingsTab.lockScreen.highlightID(for: "Play lock/unlock sounds")),
        SettingsSearchEntry(tab: .lockScreen, title: "Material", keywords: ["glass", "frosted", "liquid"], highlightID: SettingsTab.lockScreen.highlightID(for: "Material")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen media panel", keywords: ["media panel", "lock screen media"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen media panel")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show media app icon", keywords: ["app icon", "media"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show media app icon")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show panel border", keywords: ["panel border"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show panel border")),
        SettingsSearchEntry(tab: .lockScreen, title: "Always show volume control", keywords: ["volume", "slider", "lock screen", "media output", "accessibility"], highlightID: SettingsTab.lockScreen.highlightID(for: "Always show volume control")),
        SettingsSearchEntry(tab: .lockScreen, title: "Enable media panel blur", keywords: ["blur", "media panel"], highlightID: SettingsTab.lockScreen.highlightID(for: "Enable media panel blur")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen timer", keywords: ["timer widget", "lock screen timer"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen timer")),
        SettingsSearchEntry(tab: .lockScreen, title: "Timer surface", keywords: ["timer glass", "classic", "blur"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer surface")),
        SettingsSearchEntry(tab: .lockScreen, title: "Timer glass material", keywords: ["frosted", "liquid", "timer material"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer glass material")),
        SettingsSearchEntry(tab: .lockScreen, title: "Timer liquid mode", keywords: ["timer", "standard", "custom"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer liquid mode")),
        SettingsSearchEntry(tab: .lockScreen, title: "Timer widget variant", keywords: ["timer variant", "liquid"], highlightID: SettingsTab.lockScreen.highlightID(for: "Timer widget variant")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show lock screen weather", keywords: ["weather widget"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show lock screen weather")),
        SettingsSearchEntry(tab: .lockScreen, title: "Widget layout", keywords: ["inline", "circular", "widget layout", "weather layout", "status widget"], highlightID: SettingsTab.lockScreen.highlightID(for: "Widget layout")),
        SettingsSearchEntry(tab: .lockScreen, title: "Weather data provider", keywords: ["wttr", "open meteo"], highlightID: SettingsTab.lockScreen.highlightID(for: "Weather data provider")),
        SettingsSearchEntry(tab: .lockScreen, title: "Temperature unit", keywords: ["celsius", "fahrenheit"], highlightID: SettingsTab.lockScreen.highlightID(for: "Temperature unit")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show location label", keywords: ["location", "weather"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show location label")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show charging status", keywords: ["charging", "weather"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show charging status")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show charging percentage", keywords: ["charging percentage"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show charging percentage")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show battery indicator", keywords: ["battery gauge", "weather"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show battery indicator")),
        SettingsSearchEntry(tab: .lockScreen, title: "Use MacBook icon when on battery", keywords: ["laptop icon", "battery"], highlightID: SettingsTab.lockScreen.highlightID(for: "Use MacBook icon when on battery")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show Bluetooth battery", keywords: ["bluetooth", "gauge"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show Bluetooth battery")),
        SettingsSearchEntry(tab: .lockScreen, title: "Show AQI widget", keywords: ["air quality", "aqi"], highlightID: SettingsTab.lockScreen.highlightID(for: "Show AQI widget")),
        SettingsSearchEntry(tab: .lockScreen, title: "Air quality scale", keywords: ["aqi", "scale"], highlightID: SettingsTab.lockScreen.highlightID(for: "Air quality scale")),
        SettingsSearchEntry(tab: .lockScreen, title: "Use colored gauges", keywords: ["gauge tint", "monochrome"], highlightID: SettingsTab.lockScreen.highlightID(for: "Use colored gauges")),
        SettingsSearchEntry(tab: .lockScreen, title: "Reminder alignment", keywords: ["reminder", "alignment", "position"], highlightID: SettingsTab.lockScreen.highlightID(for: "Reminder alignment")),
        SettingsSearchEntry(tab: .lockScreen, title: "Reminder vertical offset", keywords: ["reminder", "offset", "position"], highlightID: SettingsTab.lockScreen.highlightID(for: "Reminder vertical offset")),

        SettingsSearchEntry(tab: .clipboard, title: "Clipboard", keywords: ["clipboard", "paste", "启用剪贴板", "音效", "纯文本", "粘贴", "保留历史", "删除历史"], highlightID: nil),
        // Shortcuts
        SettingsSearchEntry(tab: .screenText, title: "Enable copy text from screen", keywords: ["OCR", "enable", "启用", "开启", "拷贝屏幕文字"], highlightID: SettingsTab.screenText.highlightID(for: "Enable copy text from screen")),
        SettingsSearchEntry(tab: .screenText, title: "Copy text from screen", keywords: ["OCR", "copy", "screen", "text", "QR", "文字", "识别", "复制", "拷贝", "二维码", "换行"], highlightID: SettingsTab.screenText.highlightID(for: "Copy text from screen")),
        SettingsSearchEntry(tab: .shortcuts, title: "Enable global keyboard shortcuts", keywords: ["keyboard", "shortcut"], highlightID: SettingsTab.shortcuts.highlightID(for: "Enable global keyboard shortcuts")),

        // Timer
        SettingsSearchEntry(tab: .timer, title: "Enable timer", keywords: ["timer", "enable"], highlightID: SettingsTab.timer.highlightID(for: "Enable timer")),
        SettingsSearchEntry(tab: .timer, title: "Mirror macOS Clock timers", keywords: ["system timer", "clock app"], highlightID: SettingsTab.timer.highlightID(for: "Mirror macOS Clock timers")),
        SettingsSearchEntry(tab: .timer, title: "Timer tint", keywords: ["timer colour", "preset"], highlightID: SettingsTab.timer.highlightID(for: "Timer tint")),
        SettingsSearchEntry(tab: .timer, title: "Solid colour", keywords: ["timer colour", "custom"], highlightID: SettingsTab.timer.highlightID(for: "Solid colour")),
        SettingsSearchEntry(tab: .timer, title: "Progress style", keywords: ["progress", "bar", "ring"], highlightID: SettingsTab.timer.highlightID(for: "Progress style")),
        SettingsSearchEntry(tab: .timer, title: "Accent colour", keywords: ["accent", "timer"], highlightID: SettingsTab.timer.highlightID(for: "Accent colour")),

        // Stocks
        SettingsSearchEntry(tab: .stocks, title: "Enable A-share stocks", keywords: ["stocks", "quotes", "watchlist", "股票", "行情", "自选"], highlightID: nil),

        // Stats
        SettingsSearchEntry(tab: .stats, title: "Show sensor widget when collapsed", keywords: ["sensor", "temperature", "传感器", "收起"], highlightID: SettingsTab.stats.highlightID(for: "Show sensor widget when collapsed")),
        SettingsSearchEntry(tab: .stats, title: "Sensors", keywords: ["temperature", "power", "fans", "传感器"], highlightID: SettingsTab.stats.highlightID(for: "Sensors")),
        SettingsSearchEntry(tab: .stats, title: "Enable system stats monitoring", keywords: ["stats", "monitoring"], highlightID: SettingsTab.stats.highlightID(for: "Enable system stats monitoring")),
        SettingsSearchEntry(tab: .llmAgents, title: "Enable LLM Usage Monitor", keywords: ["llm", "usage", "ai", "monitor"], highlightID: SettingsTab.llmAgents.highlightID(for: "Enable LLM Usage Monitor")),
        SettingsSearchEntry(tab: .llmAgents, title: "Agent cards", keywords: ["codex", "cards", "reorder", "卡片", "排序"], highlightID: SettingsTab.llmAgents.highlightID(for: "Agent cards")),
        SettingsSearchEntry(tab: .llmAgents, title: "While agents work", keywords: ["codex", "live", "elapsed", "智能体", "工作"], highlightID: SettingsTab.llmAgents.highlightID(for: "While agents work")),
        SettingsSearchEntry(tab: .llmAgents, title: "Claude Provider", keywords: ["llm", "claude", "provider", "toggle"], highlightID: SettingsTab.llmAgents.highlightID(for: "Claude Provider")),
        SettingsSearchEntry(tab: .llmAgents, title: "Codex Provider", keywords: ["llm", "codex", "provider", "toggle"], highlightID: SettingsTab.llmAgents.highlightID(for: "Codex Provider")),
        SettingsSearchEntry(tab: .llmAgents, title: "Cursor Provider", keywords: ["llm", "cursor", "provider", "toggle"], highlightID: SettingsTab.llmAgents.highlightID(for: "Cursor Provider")),
        SettingsSearchEntry(tab: .llmAgents, title: "Antigravity Provider", keywords: ["llm", "antigravity", "provider", "toggle"], highlightID: SettingsTab.llmAgents.highlightID(for: "Antigravity Provider")),
        SettingsSearchEntry(tab: .llmAgents, title: "New API Provider", keywords: ["llm", "new api", "newapi", "provider", "toggle"], highlightID: SettingsTab.llmAgents.highlightID(for: "New API Provider")),
        SettingsSearchEntry(tab: .llmAgents, title: "New API Accounts", keywords: ["llm", "new api", "newapi", "accounts", "key", "token"], highlightID: SettingsTab.llmAgents.highlightID(for: "New API Accounts")),
        SettingsSearchEntry(tab: .stats, title: "Stop monitoring after closing the notch", keywords: ["stats", "auto stop"], highlightID: SettingsTab.stats.highlightID(for: "Stop monitoring after closing the notch")),
        SettingsSearchEntry(tab: .stats, title: "CPU Usage", keywords: ["cpu", "graph"], highlightID: SettingsTab.stats.highlightID(for: "CPU Usage")),
        SettingsSearchEntry(tab: .stats, title: "Temperature unit", keywords: ["cpu", "temperature", "celsius", "fahrenheit"], highlightID: SettingsTab.stats.highlightID(for: "Temperature unit")),
        SettingsSearchEntry(tab: .stats, title: "Memory Usage", keywords: ["memory", "ram"], highlightID: SettingsTab.stats.highlightID(for: "Memory Usage")),
        SettingsSearchEntry(tab: .stats, title: "GPU Usage", keywords: ["gpu", "graphics"], highlightID: SettingsTab.stats.highlightID(for: "GPU Usage")),
        SettingsSearchEntry(tab: .stats, title: "Show CPU widget when collapsed", keywords: ["cpu", "processor", "widget", "处理器", "小组件", "收起"], highlightID: SettingsTab.stats.highlightID(for: "Show CPU widget when collapsed")),
        SettingsSearchEntry(tab: .stats, title: "Show GPU widget when collapsed", keywords: ["gpu", "graphics", "widget", "显卡", "小组件", "收起"], highlightID: SettingsTab.stats.highlightID(for: "Show GPU widget when collapsed")),
        SettingsSearchEntry(tab: .stats, title: "Show memory widget when collapsed", keywords: ["memory", "ram", "内存", "小组件", "收起"], highlightID: SettingsTab.stats.highlightID(for: "Show memory widget when collapsed")),
        SettingsSearchEntry(tab: .stats, title: "Show disk widget when collapsed", keywords: ["disk", "磁盘", "小组件", "收起"], highlightID: SettingsTab.stats.highlightID(for: "Show disk widget when collapsed")),
        SettingsSearchEntry(tab: .stats, title: "Show network widget when collapsed", keywords: ["network", "speed", "widget", "collapsed", "网络", "网速", "小组件", "收起"], highlightID: SettingsTab.stats.highlightID(for: "Show network widget when collapsed")),
        SettingsSearchEntry(tab: .stats, title: "Network Activity", keywords: ["network", "graph"], highlightID: SettingsTab.stats.highlightID(for: "Network Activity")),
        SettingsSearchEntry(tab: .stats, title: "Disk I/O", keywords: ["disk", "io"], highlightID: SettingsTab.stats.highlightID(for: "Disk I/O")),

        // Terminal
        SettingsSearchEntry(tab: .terminal, title: "Enable terminal", keywords: ["terminal", "guake", "shell"], highlightID: SettingsTab.terminal.highlightID(for: "Enable terminal")),
        SettingsSearchEntry(tab: .terminal, title: "Shell path", keywords: ["shell", "zsh", "bash", "terminal"], highlightID: SettingsTab.terminal.highlightID(for: "Shell path")),
        SettingsSearchEntry(tab: .terminal, title: "Font size", keywords: ["terminal", "font", "text size"], highlightID: SettingsTab.terminal.highlightID(for: "Font size")),
        SettingsSearchEntry(tab: .terminal, title: "Terminal opacity", keywords: ["terminal", "opacity", "transparency", "blur", "background"], highlightID: SettingsTab.terminal.highlightID(for: "Terminal opacity")),
        SettingsSearchEntry(tab: .terminal, title: "Maximum height", keywords: ["terminal", "height", "size"], highlightID: SettingsTab.terminal.highlightID(for: "Maximum height")),
        SettingsSearchEntry(tab: .terminal, title: "Background color", keywords: ["terminal", "background", "color", "theme"], highlightID: SettingsTab.terminal.highlightID(for: "Background color")),
        SettingsSearchEntry(tab: .terminal, title: "Foreground color", keywords: ["terminal", "foreground", "text color", "theme"], highlightID: SettingsTab.terminal.highlightID(for: "Foreground color")),
        SettingsSearchEntry(tab: .terminal, title: "Cursor color", keywords: ["terminal", "cursor", "caret", "color"], highlightID: SettingsTab.terminal.highlightID(for: "Cursor color")),
        SettingsSearchEntry(tab: .terminal, title: "Bold as bright", keywords: ["terminal", "bold", "bright", "colors"], highlightID: SettingsTab.terminal.highlightID(for: "Bold as bright")),
        SettingsSearchEntry(tab: .terminal, title: "Cursor style", keywords: ["terminal", "cursor", "block", "underline", "bar", "blink"], highlightID: SettingsTab.terminal.highlightID(for: "Cursor style")),
        SettingsSearchEntry(tab: .terminal, title: "Scrollback lines", keywords: ["terminal", "scrollback", "buffer", "history"], highlightID: SettingsTab.terminal.highlightID(for: "Scrollback lines")),
        SettingsSearchEntry(tab: .terminal, title: "Option as Meta", keywords: ["terminal", "option", "meta", "alt", "key"], highlightID: SettingsTab.terminal.highlightID(for: "Option as Meta")),
        SettingsSearchEntry(tab: .terminal, title: "Mouse reporting", keywords: ["terminal", "mouse", "reporting", "vim", "tmux"], highlightID: SettingsTab.terminal.highlightID(for: "Mouse reporting")),
    ]


}

final class SettingsHighlightCoordinator: ObservableObject {
    struct ScrollRequest: Identifiable, Equatable {
        let id: String
        fileprivate let tab: SettingsTab
    }

    @Published fileprivate var pendingScrollRequest: ScrollRequest?
    @Published private(set) var activeHighlightID: String?

    private var clearWorkItem: DispatchWorkItem?

    fileprivate func focus(on entry: SettingsSearchEntry) {
        guard let highlightID = entry.highlightID else { return }
        pendingScrollRequest = ScrollRequest(id: highlightID, tab: entry.tab)
        activateHighlight(id: highlightID)
    }

    func consumeScrollRequest(_ request: ScrollRequest) {
        guard pendingScrollRequest?.id == request.id else { return }
        pendingScrollRequest = nil
    }

    private func activateHighlight(id: String) {
        activeHighlightID = id
        clearWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard self?.activeHighlightID == id else { return }
            self?.activeHighlightID = nil
        }

        clearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }
}

private struct LockScreenSettingsLink: View {
    let title: String
    @EnvironmentObject private var coordinator: SettingsHighlightCoordinator

    var body: some View {
        Button {
            coordinator.focus(on: SettingsSearchEntry(
                tab: .lockScreen, title: title, keywords: [],
                highlightID: SettingsTab.lockScreen.highlightID(for: title)
            ))
        } label: {
            Label("Open Lock Screen Settings", systemImage: "arrow.up.forward.square")
        }
    }
}

private struct SettingsHighlightModifier: ViewModifier {
    let id: String
    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator
    @State private var animatePulse = false

    private var isActive: Bool {
        highlightCoordinator.activeHighlightID == id
    }

    func body(content: Content) -> some View {
        content
            .id(id)
            .background {
                if isActive {
                    highlightBackground
                }
            }
            .onChange(of: isActive) { _, active in
                animatePulse = active
            }
            .onAppear {
                if isActive {
                    animatePulse = true
                }
            }
    }

    private var highlightBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                Color.accentColor.opacity(isActive ? (animatePulse ? 0.95 : 0.4) : 0),
                lineWidth: 2
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(isActive ? 0.08 : 0))
            )
            .padding(-4)
            .shadow(color: Color.accentColor.opacity(isActive ? 0.25 : 0), radius: animatePulse ? 8 : 2)
            .animation(
                isActive ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: animatePulse
            )
    }
}

extension View {
    func settingsHighlight(id: String) -> some View {
        modifier(SettingsHighlightModifier(id: id))
    }

    @ViewBuilder
    func settingsHighlightIfPresent(_ id: String?) -> some View {
        if let id {
            settingsHighlight(id: id)
        } else {
            self
        }
    }
}

private struct SettingsForm<Content: View>: View {
    let tab: SettingsTab
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator

    var body: some View {
        ScrollViewReader { proxy in
            content()
                .onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { request -> SettingsHighlightCoordinator.ScrollRequest? in
                    guard let request, request.tab == tab else { return nil }
                    return request
                }) { request in
                    // Give a newly selected page/segment a layout pass before scrolling.
                    DispatchQueue.main.async {
                        guard highlightCoordinator.pendingScrollRequest == request else { return }
                        withAnimation(.easeInOut(duration: 0.45)) {
                            proxy.scrollTo(request.id, anchor: .center)
                        }
                        highlightCoordinator.consumeScrollRequest(request)
                    }
                }
        }
    }
}

struct SettingsView: View {
    @Default(.notchAppearance) private var notchAppearance
    @State private var selectedTab: SettingsTab = .general
    @State private var searchText: String = ""
    @State private var expandedGroups = Set(SettingsTabGroup.allCases)
    @StateObject private var registry = SettingsModuleRegistry(modules: SettingsModuleRegistry.appModules())
    @State private var galleryTarget: SettingsTab?
    @State private var galleryRequest = UUID()
    @StateObject private var highlightCoordinator = SettingsHighlightCoordinator()
    @Default(.enableMinimalisticUI) var enableMinimalisticUI

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                SettingsSidebarSearchBar(
                    text: $searchText,
                    suggestions: searchSuggestions,
                    status: searchStatus,
                    onSuggestionSelected: handleSearchSuggestionSelection
                )
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

                List(selection: selectionBinding) {
                    ForEach(groupedFilteredTabs, id: \.group) { section in
                        if let title = section.group.title {
                            DisclosureGroup(isExpanded: Binding(
                                get: { !searchText.isEmpty || expandedGroups.contains(section.group) },
                                set: { expanded in
                                    if expanded { expandedGroups.insert(section.group) }
                                    else { expandedGroups.remove(section.group) }
                                }
                            )) {
                                ForEach(section.tabs) { tab in
                                    NavigationLink(value: tab) { sidebarRow(for: tab) }
                                }
                            } label: {
                                Text(title).foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(section.tabs) { tab in
                                NavigationLink(value: tab) { sidebarRow(for: tab) }
                            }
                        }
                    }
                }
                .listStyle(SidebarListStyle())
                .tint(.blue)
                .frame(minWidth: 200)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 240)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } detail: {
            VStack(spacing: 0) {
                if resolvedSelection.sidebarTab == .appearance {
                    SettingsPageTabBar(
                        items: registry.appearancePages.map(\.id),
                        selection: $selectedTab,
                        title: { registry.module($0)?.title ?? "" },
                        icon: { registry.module($0)?.icon ?? "" },
                        accessibilityTitle: String(localized: "Appearance & Interaction")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                    .padding(.bottom, 2)
                }
                detailView(for: resolvedSelection)
            }
            // Same opaque background the form uses below, so the window's
            // translucent material does not show through the tab-bar row as a
            // lighter band.
            .background(Color(nsColor: .windowBackgroundColor))
                .modifier(SettingsPageStyle())
                .navigationTitle(resolvedSelection.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(notchAppearance.preferredColorScheme)
        .toolbar(removing: .sidebarToggle)
        .toolbar { toolbarSpacingShim }
        .environmentObject(highlightCoordinator)
        .onChange(of: highlightCoordinator.pendingScrollRequest) { _, request in
            guard let request else { return }
            searchText = ""
            expandedGroups.insert(request.tab.group)
            if registry.requiresGallery(request.tab, minimal: enableMinimalisticUI) {
                highlightCoordinator.consumeScrollRequest(request)
                openGallery(request.tab)
            } else {
                selectedTab = request.tab
            }
        }
        .toggleStyle(.switch)
        .formStyle(.grouped)
        .frame(minWidth: 700, maxWidth: .infinity)
        .onChange(of: registry.enabledIDs) { _, _ in reconcileSelection() }
        .onChange(of: enableMinimalisticUI) { _, _ in reconcileSelection() }
        .background {
            Group {
                if #available(macOS 26.0, *) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .glassEffect(
                            .clear
                                .tint(Color.white.opacity(0.1))
                                .interactive(),
                            in: .rect(cornerRadius: 18)
                        )
                } else {
                    ZStack {
                        Color(NSColor.windowBackgroundColor)
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    private var resolvedSelection: SettingsTab {
        selectedTab
    }

    @ToolbarContentBuilder
    private var toolbarSpacingShim: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                toolbarSpacerView
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                toolbarSpacerView
            }
        }
    }

    @ViewBuilder
    private var toolbarSpacerView: some View {
        Color.clear
            .frame(width: 96, height: 32)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var filteredTabs: [SettingsTab] {
        registry.sidebarTabs(minimal: enableMinimalisticUI)
    }

    private var selectionBinding: Binding<SettingsTab> {
        Binding(
            get: { resolvedSelection.sidebarTab },
            set: { newValue in
                selectedTab = newValue
            }
        )
    }

    private func sidebarIcon(for tab: SettingsTab) -> some View {
        Image(systemName: tab.systemImage)
            .foregroundStyle(resolvedSelection.sidebarTab == tab ? Color.white : Color.blue)
            .frame(width: 18)
            .accessibilityHidden(true)
    }

    private func sidebarRow(for tab: SettingsTab) -> some View {
        HStack(spacing: 9) {
            sidebarIcon(for: tab)
            Text(tab == .appearance ? String(localized: "Appearance & Interaction") : tab.title)
                .foregroundStyle(resolvedSelection.sidebarTab == tab ? Color.white : Color.primary)
        }
    }

    private var groupedFilteredTabs: [(group: SettingsTabGroup, tabs: [SettingsTab])] {
        let visible = filteredTabs
        var result: [(group: SettingsTabGroup, tabs: [SettingsTab])] = []

        for group in SettingsTabGroup.allCases {
            let tabs = visible.filter { $0.group == group }
            if !tabs.isEmpty {
                result.append((group: group, tabs: tabs))
            }
        }

        return result
    }

    private var searchSuggestions: [SettingsSearchEntry] {
        Array(registry.search(searchText).prefix(8))
    }

    private func searchStatus(_ entry: SettingsSearchEntry) -> String {
        guard let module = registry.module(entry.tab), module.enabled != nil else { return entry.tab.title }
        if !module.isEnabled { return String(localized: "Feature disabled → Enable in Features") }
        if enableMinimalisticUI && !module.supportsMinimalMode {
            return String(localized: "Limited by Minimalistic UI → View preset")
        }
        return module.title
    }

    private func openGallery(_ target: SettingsTab?) {
        searchText = ""
        galleryTarget = target
        galleryRequest = UUID()
        selectedTab = .features
    }

    private func reconcileSelection() {
        if registry.requiresGallery(selectedTab, minimal: enableMinimalisticUI) {
            openGallery(selectedTab)
        }
    }

    private func handleSearchSuggestionSelection(_ suggestion: SettingsSearchEntry) {
        if registry.requiresGallery(suggestion.tab, minimal: enableMinimalisticUI) {
            openGallery(suggestion.tab)
        } else if suggestion.tab == .features {
            openGallery(nil)
        } else {
            searchText = ""
            expandedGroups.insert(suggestion.tab.group)
            selectedTab = suggestion.tab
            highlightCoordinator.focus(on: suggestion)
        }
    }

    private struct SettingsSidebarSearchBar: View {
        @Binding var text: String
        let suggestions: [SettingsSearchEntry]
        let status: (SettingsSearchEntry) -> String
        let onSuggestionSelected: (SettingsSearchEntry) -> Void

        @FocusState private var isFocused: Bool
        @State private var hoveredSuggestionID: SettingsSearchEntry.ID?

        var body: some View {
            VStack(spacing: 6) {
                searchField
                if showSuggestions {
                    suggestionList
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showSuggestions)
        }

        private var showSuggestions: Bool {
            isFocused && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !suggestions.isEmpty
        }

        private var searchField: some View {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.secondary)

                TextField("Search Settings", text: $text)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(triggerFirstSuggestion)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.12))
            )
        }

        private var suggestionList: some View {
            VStack(spacing: 0) {
                ForEach(suggestions) { suggestion in
                    Button {
                        selectSuggestion(suggestion)
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(suggestion.tab.tint)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Image(systemName: suggestion.tab.systemImage)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(suggestion.title))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                Text(status(suggestion))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .background(rowBackground(for: suggestion))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredSuggestionID = hovering ? suggestion.id : (hoveredSuggestionID == suggestion.id ? nil : hoveredSuggestionID)
                    }

                    if suggestion.id != suggestions.last?.id {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08))
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        private func rowBackground(for suggestion: SettingsSearchEntry) -> some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hoveredSuggestionID == suggestion.id ? Color.white.opacity(0.08) : Color.clear)
        }

        private func selectSuggestion(_ suggestion: SettingsSearchEntry) {
            onSuggestionSelected(suggestion)
            isFocused = false
        }

        private func triggerFirstSuggestion() {
            guard let first = suggestions.first else { return }
            selectSuggestion(first)
        }
    }

    @ViewBuilder
    private func detailView(for tab: SettingsTab) -> some View {
        if tab == .features {
            FeatureGallery(registry: registry, target: galleryTarget) { destination in
                expandedGroups.insert(destination.group)
                selectedTab = destination
            }
            .id(galleryRequest)
        } else if let module = registry.module(tab) {
            SettingsForm(tab: tab) { module.makeSettings() }
        }
    }
}

/// Navigation role is explicit; having a switch does not determine page ownership.
private struct SettingsModule: Identifiable {
    enum Kind { case core, toggleable, configuration }

    let id: SettingsTab
    let kind: Kind
    let summary: String
    let enabled: Binding<Bool>?
    let supportsMinimalMode: Bool
    let changes: AnyPublisher<Void, Never>?
    let makeSettings: () -> AnyView
    let searchEntries: [SettingsSearchEntry]

    var title: String { id.title }
    var icon: String { id.systemImage }
    var color: Color { id.tint }
    var group: SettingsTabGroup { id.group }
    var isEnabled: Bool { enabled?.wrappedValue ?? true }
    var isFeature: Bool { kind == .toggleable }

    init<Content: View>(_ id: SettingsTab, kind: Kind, summary: String = "",
                        enabled: Binding<Bool>? = nil, supportsMinimalMode: Bool = true,
                        changes: AnyPublisher<Void, Never>? = nil,
                        @ViewBuilder settings: @escaping () -> Content) {
        precondition((kind == .toggleable) == (enabled != nil))
        self.id = id
        self.kind = kind
        self.summary = summary
        self.enabled = enabled
        self.supportsMinimalMode = supportsMinimalMode
        self.changes = changes
        self.makeSettings = { AnyView(settings()) }
        // Keep existing option anchors while also making every module discoverable by name.
        self.searchEntries = SettingsSearchIndex.entries.filter { $0.tab == id }
            + [SettingsSearchEntry(tab: id, title: id.title, keywords: [summary], highlightID: nil)]
    }
}

@MainActor
private final class SettingsModuleRegistry: ObservableObject {
    let modules: [SettingsModule]
    private var observation: AnyCancellable?

    init(modules: [SettingsModule]) {
        self.modules = modules
        observation = Publishers.MergeMany(modules.compactMap(\.changes))
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
    }

    var features: [SettingsModule] { modules.filter(\.isFeature) }
    var galleryModules: [SettingsModule] { modules.filter { $0.kind != .core } }
    var appearancePages: [SettingsModule] { modules.filter { $0.id.sidebarTab == .appearance } }
    var enabledIDs: [SettingsTab] { features.filter(\.isEnabled).map(\.id) }
    func module(_ id: SettingsTab) -> SettingsModule? { modules.first { $0.id == id } }

    func requiresGallery(_ id: SettingsTab, minimal: Bool) -> Bool {
        guard let module = module(id), module.isFeature else { return false }
        return !module.isEnabled || (minimal && !module.supportsMinimalMode)
    }

    func sidebarTabs(minimal: Bool) -> [SettingsTab] {
        [.general, .appearance, .features]
            + galleryModules.filter { !requiresGallery($0.id, minimal: minimal) }.map(\.id)
            + [.shortcuts, .about]
    }

    func search(_ query: String) -> [SettingsSearchEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let gallery = SettingsSearchEntry(tab: .features, title: SettingsTab.features.title,
                                          keywords: [], highlightID: nil)
        let entries = [gallery] + SettingsSearchIndex.entries.filter { $0.tab == .features }
            + modules.flatMap(\.searchEntries)
        var seen = Set<String>()
        return entries.filter { entry in
            (entry.title.localizedCaseInsensitiveContains(query)
             || NSLocalizedString(entry.title, comment: "").localizedCaseInsensitiveContains(query)
             || entry.keywords.contains { $0.localizedCaseInsensitiveContains(query) })
                && seen.insert(entry.id).inserted
        }
    }
}

private struct MenuBarSettings: View {
    @EnvironmentObject private var coordinator: SettingsHighlightCoordinator
    @State private var statusIcons = false

    private let pages: [(id: Bool, title: String, icon: String)] = [
        (false, String(localized: "Visibility"), "eye"),
        (true, String(localized: "Status Icons"), "menubar.rectangle")
    ]

    var body: some View {
        VStack(spacing: 0) {
            SettingsPageTabBar(
                items: pages.map(\.id),
                selection: $statusIcons,
                title: { id in pages.first { $0.id == id }?.title ?? "" },
                icon: { id in pages.first { $0.id == id }?.icon ?? "" },
                accessibilityTitle: String(localized: "Menu Bar & Dock")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 2)
            if statusIcons {
                MenuBarStatusSettingsView(controller: MenuBarStatusManager.shared.controller)
            } else {
                GeneralSettings(page: .menuBar)
            }
        }
        .onReceive(coordinator.$pendingScrollRequest) { request in
            if request?.tab == .menuBar { statusIcons = false }
        }
    }
}

private struct FeatureGallery: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var registry: SettingsModuleRegistry
    let target: SettingsTab?
    let open: (SettingsTab) -> Void
    @Default(.enableMinimalisticUI) private var minimal
    @State private var query = ""
    @State private var filter = 0

    private var visibleModules: [SettingsModule] {
        registry.galleryModules.filter { module in
            (filter == 0 || (module.isFeature && (filter == 1 ? module.isEnabled : !module.isEnabled)))
                && (query.isEmpty || module.title.localizedCaseInsensitiveContains(query)
                    || module.summary.localizedCaseInsensitiveContains(query)
                    || module.searchEntries.contains { entry in
                        NSLocalizedString(entry.title, comment: "").localizedCaseInsensitiveContains(query)
                            || entry.keywords.contains { $0.localizedCaseInsensitiveContains(query) }
                    })
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Enabled features appear in the sidebar. Turning a feature off keeps its saved settings.")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable minimalistic UI", isOn: Binding(
                            get: { minimal },
                            set: { value in
                                minimal = value
                                if value { Defaults[.useModernCloseAnimation] = true }
                            }
                        )).toggleStyle(.switch)
                        Text("This preset keeps the original compact layout and temporarily limits some features without changing their switches.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(colorScheme == .dark ? Color(white: 0.16) : Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .id(SettingsTab.features)
                    TextField("Search features", text: $query).textFieldStyle(.roundedBorder)
                    SettingsPageTabBar(
                        items: [0, 1, 2],
                        selection: $filter,
                        title: { value in
                            switch value {
                            case 1: return String(localized: "Enabled Features")
                            case 2: return String(localized: "Disabled Features")
                            default: return String(localized: "All Features")
                            }
                        },
                        icon: { value in
                            switch value {
                            case 1: return "checkmark.circle"
                            case 2: return "xmark.circle"
                            default: return "square.grid.2x2"
                            }
                        },
                        accessibilityTitle: String(localized: "Feature filter")
                    )
                    if visibleModules.isEmpty {
                        Text("No matching features.").foregroundStyle(.secondary)
                    }
                    ForEach(SettingsTabGroup.allCases) { group in
                        let items = visibleModules.filter { $0.group == group }
                        if !items.isEmpty {
                            Text(group.title ?? "").font(.headline).accessibilityAddTraits(.isHeader)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                                ForEach(items) { module in
                                    card(module) { proxy.scrollTo(SettingsTab.features, anchor: .top) }.id(module.id)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                guard let target else { return }
                // A new gallery instance starts with All Features and an empty query.
                DispatchQueue.main.async { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }

    private func card(_ module: SettingsModule, reviewPreset: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: module.icon).font(.title2).foregroundStyle(module.color)
                    .accessibilityHidden(true)
                Spacer()
                if let binding = module.enabled {
                    Toggle(module.title, isOn: binding).labelsHidden().toggleStyle(.switch)
                        .disabled(minimal && !module.supportsMinimalMode)
                }
            }
            Text(module.title).font(.headline)
            Text(module.summary).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(module.kind == .configuration ? String(localized: "Managed in feature settings")
                 : minimal && !module.supportsMinimalMode ? String(localized: "Limited by Minimalistic UI")
                 : module.isEnabled ? String(localized: "Enabled") : String(localized: "Disabled"))
                .font(.caption).foregroundStyle(.secondary)
            if minimal && !module.supportsMinimalMode {
                Button("Review preset", action: reviewPreset)
            }
            Button("Configure") { open(module.id) }
                .disabled(registry.requiresGallery(module.id, minimal: minimal))
                .help(module.isEnabled ? module.title : String(localized: "Enable this feature first."))
                .accessibilityLabel(String(localized: "Configure") + " " + module.title)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
        .background(colorScheme == .dark ? Color(white: 0.16) : Color.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(target == module.id ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1))
    }
}

@MainActor
private extension SettingsModuleRegistry {
    static func appModules() -> [SettingsModule] {
        [
            SettingsModule(.general, kind: .core) { GeneralSettings() },
            SettingsModule(.appearance, kind: .core) { Appearance() },
            SettingsModule(.interaction, kind: .core) { GeneralSettings(page: .interaction) },
            SettingsModule(.liveActivities, kind: .configuration, summary: String(localized: "Configure live activity indicators and system alerts.")) { LiveActivitiesSettings() },
            SettingsModule(.menuBar, kind: .configuration, summary: String(localized: "Choose menu bar and Dock icons and their status displays.")) { MenuBarSettings() },
            SettingsModule(.lockScreen, kind: .configuration, summary: String(localized: "Arrange media, timers and other lock screen widgets.")) { LockScreenSettings() },
            SettingsModule(.media, kind: .configuration, summary: String(localized: "Configure playback controls, lyrics and music sources.")) { Media() },
            SettingsModule(.calendar, kind: .configuration, summary: String(localized: "Choose calendars, reminders and upcoming events.")) { CalendarSettings() },
            SettingsModule(.devices, kind: .configuration, summary: String(localized: "Configure connected devices and battery displays.")) { DevicesSettingsView() },
            SettingsModule(.hudAndOSD, kind: .configuration, summary: String(localized: "Customize volume and brightness controls and overlays.")) { HUDAndOSDSettingsView() },
            SettingsModule(.shortcuts, kind: .core) { Shortcuts() },
            SettingsModule(.about, kind: .core) { About() },
            SettingsModule(.clipboard, kind: .toggleable, summary: String(localized: "Keep clipboard history and paste copied items."),
                enabled: Binding(get: { ClipboardHistoryStore.shared.enabled }, set: { ClipboardHistoryStore.shared.enabled = $0 }),
                changes: ClipboardHistoryStore.shared.$enabled.map { _ in () }.eraseToAnyPublisher()) { ClipboardSettingsView() },
            feature(.screenText, key: .enableScreenText, summary: String(localized: "Recognize and copy text from the screen."), supportsMinimalMode: true) { ScreenTextSettings() },
            feature(.shelf, key: .dynamicShelf, summary: String(localized: "Temporarily collect files and share them by dragging."), supportsMinimalMode: false) { Shelf() },
            feature(.notes, key: .enableNotes, summary: String(localized: "Write quick notes in the island."), supportsMinimalMode: false) { NotesSettingsView() },
            feature(.timer, key: .enableTimerFeature, summary: String(localized: "Set timers, presets and countdown displays."), supportsMinimalMode: false) { TimerSettings() },
            feature(.keepAwake, key: .enableCaffeinate, summary: String(localized: "Keep your Mac awake for a chosen duration."), supportsMinimalMode: true) { GeneralSettings(page: .keepAwake) },
            feature(.stats, key: .enableStatsFeature, summary: String(localized: "Monitor CPU, memory, network and other system activity."), supportsMinimalMode: false) { StatsSettings() },
            feature(.llmAgents, key: .enableLLMUsageFeature, summary: String(localized: "View AI provider usage and agent activity."), supportsMinimalMode: false) { LLMAgentsSettings() },
            feature(.terminal, key: .enableTerminalFeature, summary: String(localized: "Use a terminal inside the island."), supportsMinimalMode: false) { TerminalSettings() },
            feature(.developerTools, key: .enableDeveloperTools, summary: String(localized: "Format and validate JSON with developer tools."), supportsMinimalMode: false) { DeveloperToolsSettings() },
            feature(.stocks, key: .enableStocksFeature, summary: String(localized: "Follow stock quotes and a personal watchlist."), supportsMinimalMode: false) { Form { StocksSettingsSection() } },
            SettingsModule(.desktopPing, kind: .toggleable, summary: String(localized: "Send visual pings and emotes on the desktop."),
                enabled: Binding(get: { DesktopPingManager.shared.configuration.enabled }, set: { DesktopPingManager.shared.configuration.enabled = $0 }),
                changes: DesktopPingManager.shared.$configuration.map { _ in () }.eraseToAnyPublisher()) { DesktopPingSettings() },
        ]
    }

    static func feature<Content: View>(_ id: SettingsTab, key: Defaults.Key<Bool>, summary: String,
                                      supportsMinimalMode: Bool, @ViewBuilder settings: @escaping () -> Content) -> SettingsModule {
        SettingsModule(id, kind: .toggleable, summary: summary,
                       enabled: Binding(get: { Defaults[key] }, set: { Defaults[key] = $0 }),
                       supportsMinimalMode: supportsMinimalMode,
                       changes: Defaults.publisher(key).map { _ in () }.eraseToAnyPublisher(), settings: settings)
    }
}

private struct SettingsPageStyle: ViewModifier {
    var compact = false
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.formStyle(SettingsCardStyle(compact: compact))
        } else {
            content.formStyle(.grouped)
                .labelStyle(.titleOnly)
        }
    }
}

@available(macOS 15.0, *)
private struct SettingsCardStyle: FormStyle {
    var compact = false
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(sections: configuration.content) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        section.header
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            ForEach(subviews: section.content) { row in
                                if row.id != section.content.first?.id {
                                    Divider().opacity(0.5).padding(.horizontal, 20)
                                }
                                row
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, compact ? 12 : 16)
                            }
                        }
                        .background(colorScheme == .dark ? Color(white: 0.16) : Color.white,
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                        section.footer
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .frame(maxWidth: compact ? 712 : .infinity, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .font(.body)
        .controlSize(.regular)
        .toggleStyle(SettingsCardToggleStyle())
        .pickerStyle(.menu)
        .labelStyle(SettingsCardLabelStyle())
    }
}

private struct SettingsCardToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label
                .accessibilityHidden(true)
            Spacer(minLength: 12)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct SettingsCardLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.title
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    var page: SettingsTab = .general
    @State private var screens: [String] = NSScreen.screens.compactMap { $0.localizedName }
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.closedNotchWidth) var closedNotchWidth
    @Default(.customizePhysicalNotchWidth) var customizePhysicalNotchWidth
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.enableHorizontalMusicGestures) var enableHorizontalMusicGestures
    @Default(.musicGestureBehavior) var musicGestureBehavior
    @Default(.reverseSwipeGestures) var reverseSwipeGestures
    @Default(.reverseScrollGestures) var reverseScrollGestures
    @Default(.enableCaffeinate) var enableCaffeinate
    @Default(.caffeinateDefaultDuration) var caffeinateDefaultDuration

    private func highlightID(_ title: String) -> String {
        page.highlightID(for: title)
    }

    var body: some View {
        settingsForm
            .navigationTitle(page.title)
    }

    private var settingsForm: some View {
        Form {
            switch page {
            case .general:
                AppLanguageSettingsSection(expandsLabel: true)
                .settingsHighlight(id: highlightID("Language"))

                Section {
                    LaunchAtLogin.Toggle {
                        Label("Launch at login", systemImage: "play.circle.fill")
                    }
                    .settingsHighlight(id: highlightID("Launch at login"))
                }
            case .menuBar:
                Section {
                    Defaults.Toggle(key: .menubarIcon) {
                        Label("Show menu bar icon", systemImage: "menubar.rectangle")
                    }
                    .settingsHighlight(id: highlightID("Show menu bar icon"))
                    Defaults.Toggle(key: .menuBarUsesTrioIcon) {
                        Label("Use three-in-one status icon", systemImage: "square.grid.3x1.below.line.grid.1x2")
                    }
                    .settingsHighlight(id: highlightID("Use three-in-one status icon"))
                    Defaults.Toggle(key: .dynamicDockIcon) {
                        Label("Show dynamic status icon in Dock", systemImage: "dock.rectangle")
                    }
                    .settingsHighlight(id: highlightID("Show dynamic status icon in Dock"))
                } header: { Text("Menu Bar & Dock") }
            case .interaction:
                Section {
                    Defaults.Toggle(key: .showOnAllDisplays) {
                        Label("Show on all displays", systemImage: "display.2")
                    }
                    .onChange(of: showOnAllDisplays) {
                        NotificationCenter.default.post(name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                    }
                    .settingsHighlight(id: highlightID("Show on all displays"))
                    HStack(spacing: 16) {
                        Label("Show on a specific display", systemImage: "display")
                        Spacer(minLength: 12)
                        Picker("Show on a specific display", selection: $coordinator.preferredScreen) {
                            ForEach(screens, id: \.self) { screen in
                                Text(screen)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .onChange(of: NSScreen.screens) {
                        screens =  NSScreen.screens.compactMap({$0.localizedName})
                    }
                    .disabled(showOnAllDisplays)
                    .settingsHighlight(id: highlightID("Show on a specific display"))
                    Defaults.Toggle(key: .automaticallySwitchDisplay) {
                        Label("Automatically switch displays", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .onChange(of: automaticallySwitchDisplay) {
                        NotificationCenter.default.post(name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                    }
                    .disabled(showOnAllDisplays)
                    .settingsHighlight(id: highlightID("Automatically switch displays"))
                    Defaults.Toggle(key: .hideDynamicIslandFromScreenCapture) {
                        Label("Hide Dynamic Island during screenshots & recordings", systemImage: "eye.slash")
                    }
                    .settingsHighlight(id: highlightID("Hide Dynamic Island during screenshots & recordings"))
                } header: {
                    Text("System features")
                }

                gestureControls()
            case .keepAwake:
                Section {
                    Defaults.Toggle(key: .enableCaffeinate) {
                        Label("Enable Keep Awake", systemImage: "cup.and.saucer.fill")
                    }
                    .settingsHighlight(id: highlightID("Enable Keep Awake"))

                    Defaults.Toggle(key: .showCaffeinateIcon) {
                        Label("Show Keep Awake icon in the notch", systemImage: "cup.and.saucer")
                    }
                    .disabled(!enableCaffeinate)
                    .settingsHighlight(id: highlightID("Show Keep Awake icon in the notch"))

                    HStack(spacing: 16) {
                        Label("Default duration", systemImage: "clock")
                        Spacer(minLength: 12)
                        Picker("Default duration", selection: $caffeinateDefaultDuration) {
                            ForEach(CaffeinateDuration.allCases) { duration in
                                Text(duration.displayName).tag(duration)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .disabled(!enableCaffeinate)
                    .settingsHighlight(id: highlightID("Default duration"))

                    Defaults.Toggle(key: .caffeinateKeepsDisplayAwake) {
                        Label("Also keep the display awake", systemImage: "sun.max")
                    }
                    .disabled(!enableCaffeinate)
                    .settingsHighlight(id: highlightID("Also keep the display awake"))
                } header: {
                    Text("Keep Awake")
                } footer: {
                    Text("Holds a power assertion so the Mac will not sleep, the way the caffeinate command does. Turning this off also ends a session that is already running. With the display option off, the screen can still sleep while the system stays up.")
                }

            default: EmptyView()
            }
        }
    }

    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Label("Enable gestures", systemImage: "hand.draw")
            }
            .disabled(!openNotchOnHover)
            .settingsHighlight(id: highlightID("Enable gestures"))
            Group {
                Defaults.Toggle(key: .enableHorizontalMusicGestures) {
                    Label("Enable horizontal media gestures", systemImage: "arrow.left.arrow.right")
                }
                .settingsHighlight(id: highlightID("Horizontal media gestures"))

                Group {
                    HStack(spacing: 12) {
                        Label("Gesture skip behavior", systemImage: "forward.end")
                        Spacer(minLength: 8)
                        SettingsSegmentedControl(
                            items: Array(MusicSkipBehavior.allCases),
                            selection: $musicGestureBehavior,
                            label: { $0.displayName }
                        )
                    }
                    .settingsHighlight(id: highlightID("Gesture skip behavior"))

                    Text(musicGestureBehavior.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Defaults.Toggle(key: .reverseSwipeGestures) {
                        Label("Reverse swipe gestures", systemImage: "arrow.uturn.backward")
                    }
                    .settingsHighlight(id: highlightID("Reverse swipe gestures"))
                }
                .disabled(!enableHorizontalMusicGestures)

                Defaults.Toggle(key: .closeGestureEnabled) {
                    Label("Enable close gesture", systemImage: "arrow.up")
                }
                .settingsHighlight(id: highlightID("Enable close gesture"))
                HStack(spacing: 16) {
                    Label("Gesture sensitivity", systemImage: "slider.horizontal.3")
                    Spacer(minLength: 12)
                    DottedSettingsSlider(
                        value: Binding(
                            // A smaller gesture threshold means higher sensitivity.
                            get: { 400 - Double(gestureSensitivity) },
                            set: { gestureSensitivity = CGFloat(400 - $0) }
                        ),
                        range: 100...300,
                        step: 100,
                        label: "Gesture sensitivity",
                        valueText: String(localized: gestureSensitivity == 100 ? "High" : gestureSensitivity == 200 ? "Medium" : "Low")
                    )
                }

                Defaults.Toggle(key: .reverseScrollGestures) {
                    Label("Reverse open/close scroll gestures", systemImage: "arrow.up.arrow.down")
                }
                .settingsHighlight(id: highlightID("Reverse scroll gestures"))
            }
            .disabled(!enableGestures)
        } header: {
            HStack {
                Text("Gesture control")
                customBadge(text: "Beta")
            }
        } footer: {
            Text("Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled")
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

}

struct BatteryHUDSettingsSections: View {
    @ObservedObject private var batteryStatusViewModel = BatteryStatusViewModel.shared
    @Default(.showPowerStatusNotifications) private var showPowerStatusNotifications
    @Default(.showChargingBatteryHUD) private var showChargingBatteryHUD
    @Default(.showLowBatteryHUD) private var showLowBatteryHUD
    @Default(.showFullBatteryHUD) private var showFullBatteryHUD
    @Default(.chargingBatteryHUDDuration) private var chargingBatteryHUDDuration
    @Default(.lowBatteryHUDDuration) private var lowBatteryHUDDuration
    @Default(.fullBatteryHUDDuration) private var fullBatteryHUDDuration
    @Default(.lowBatteryHUDThreshold) private var lowBatteryHUDThreshold
    @Default(.fullBatteryHUDThreshold) private var fullBatteryHUDThreshold
    @Default(.lowBatteryHUDStyle) private var lowBatteryHUDStyle
    @Default(.fullBatteryHUDStyle) private var fullBatteryHUDStyle

    private func highlightID(_ title: String) -> String {
        SettingsTab.liveActivities.highlightID(for: title)
    }

    private var chargingDurationBinding: Binding<Double> {
        Binding(
            get: { Double(chargingBatteryHUDDuration) },
            set: { chargingBatteryHUDDuration = Int($0.rounded()) }
        )
    }

    private var lowBatteryDurationBinding: Binding<Double> {
        Binding(
            get: { Double(lowBatteryHUDDuration) },
            set: { lowBatteryHUDDuration = Int($0.rounded()) }
        )
    }

    private var fullBatteryDurationBinding: Binding<Double> {
        Binding(
            get: { Double(fullBatteryHUDDuration) },
            set: { fullBatteryHUDDuration = Int($0.rounded()) }
        )
    }

    private var lowBatteryThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(lowBatteryHUDThreshold) },
            set: { lowBatteryHUDThreshold = Int($0.rounded()) }
        )
    }

    private var fullBatteryThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(fullBatteryHUDThreshold) },
            set: { fullBatteryHUDThreshold = Int($0.rounded()) }
        )
    }

    private func sectionOpacity(_ isEnabled: Bool) -> Double {
        isEnabled ? 1 : 0.5
    }

    var body: some View {
        if BatteryActivityManager.shared.hasBattery() {
            Section {
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Label("Show battery alerts", systemImage: "battery.100")
                }
                .settingsHighlight(id: highlightID("Show battery alerts"))
            } header: {
                Text("Battery Alerts")
            }
            Section {
                Defaults.Toggle(key: .showChargingBatteryHUD) {
                    Label("Show charging HUD", systemImage: "battery.100")
                }
                .settingsHighlight(id: highlightID("Show charging HUD"))
                Group {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Charging duration", systemImage: "battery.100")
                            Spacer()
                        }
                        SettingsSlider(value: chargingDurationBinding, in: 1...10, step: 1, valueLabel: Text("\(chargingBatteryHUDDuration)s"))
                    }
                    .settingsHighlight(id: highlightID("Charging duration"))

                    Button {
                        batteryStatusViewModel.triggerTestHUD(kind: .charging)
                    } label: {
                        Label("Test charging HUD", systemImage: "bolt.fill")
                    }
                    .settingsHighlight(id: highlightID("Test charging HUD"))
                }
                .disabled(!showChargingBatteryHUD)
                .opacity(sectionOpacity(showChargingBatteryHUD))
            } header: {
                Text("Charging Alert")
            }
            .disabled(!showPowerStatusNotifications)
            .opacity(sectionOpacity(showPowerStatusNotifications))
            Section {
                Defaults.Toggle(key: .showLowBatteryHUD) {
                    Label("Show low battery HUD", systemImage: "battery.100")
                }
                .settingsHighlight(id: highlightID("Show low battery HUD"))
                Group {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsSegmentedPicker(
                            "Low battery style",
                            selection: $lowBatteryHUDStyle,
                            items: Array(BatteryNotificationStyle.allCases)
                        ) { $0.title }
                        Text("Compact matches the charging HUD. Standard uses the expanded DynamicNotch-style card.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .settingsHighlight(id: highlightID("Low battery style"))


                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Low battery threshold", systemImage: "battery.100")
                            Spacer()
                        }
                        SettingsSlider(value: lowBatteryThresholdBinding, in: 5...30, step: 1, valueLabel: Text("\(lowBatteryHUDThreshold)%"))
                    }
                    .settingsHighlight(id: highlightID("Low battery threshold"))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Low battery duration", systemImage: "battery.100")
                            Spacer()
                        }
                        SettingsSlider(value: lowBatteryDurationBinding, in: 1...10, step: 1, valueLabel: Text("\(lowBatteryHUDDuration)s"))
                    }
                    .settingsHighlight(id: highlightID("Low battery duration"))

                    Defaults.Toggle(key: .playLowBatteryAlertSound) {
                        Label("Play low battery alert sound", systemImage: "battery.100")
                    }
                    .settingsHighlight(id: highlightID("Play low battery alert sound"))

                    Button {
                        batteryStatusViewModel.triggerTestHUD(kind: .lowBattery)
                    } label: {
                        Label("Test low battery HUD", systemImage: "battery.25")
                    }
                    .settingsHighlight(id: highlightID("Test low battery HUD"))
                }
                .disabled(!showLowBatteryHUD)
                .opacity(sectionOpacity(showLowBatteryHUD))
            } header: {
                Text("Low Battery Alert")
            }
            .disabled(!showPowerStatusNotifications)
            .opacity(sectionOpacity(showPowerStatusNotifications))
            Section {
                Defaults.Toggle(key: .showFullBatteryHUD) {
                    Label("Show fully charged HUD", systemImage: "battery.100")
                }
                .settingsHighlight(id: highlightID("Show fully charged HUD"))
                Group {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsSegmentedPicker(
                            "Full battery style",
                            selection: $fullBatteryHUDStyle,
                            items: Array(BatteryNotificationStyle.allCases)
                        ) { $0.title }
                        Text("Compact keeps the alert inline. Standard uses the taller full-charge HUD with the charging animation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .settingsHighlight(id: highlightID("Full battery style"))


                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Full charge threshold", systemImage: "battery.100")
                            Spacer()
                        }
                        SettingsSlider(value: fullBatteryThresholdBinding, in: 80...100, step: 1, valueLabel: Text("\(fullBatteryHUDThreshold)%"))
                    }
                    .settingsHighlight(id: highlightID("Full charge threshold"))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Full battery duration", systemImage: "battery.100")
                            Spacer()
                        }
                        SettingsSlider(value: fullBatteryDurationBinding, in: 1...10, step: 1, valueLabel: Text("\(fullBatteryHUDDuration)s"))
                    }
                    .settingsHighlight(id: highlightID("Full battery duration"))

                    Button {
                        batteryStatusViewModel.triggerTestHUD(kind: .fullBattery)
                    } label: {
                        Label("Test full battery HUD", systemImage: "battery.100")
                    }
                    .settingsHighlight(id: highlightID("Test full battery HUD"))
                }
                .disabled(!showFullBatteryHUD)
                .opacity(sectionOpacity(showFullBatteryHUD))
            } header: {
                Text("Full Battery Alert")
            }
            .disabled(!showPowerStatusNotifications)
            .opacity(sectionOpacity(showPowerStatusNotifications))
        }
    }
}

struct DownloadSettingsSection: View {
    @Default(.selectedDownloadIndicatorStyle) var selectedDownloadIndicatorStyle
    @Default(.selectedDownloadIconStyle) var selectedDownloadIconStyle
    @Default(.enableDownloadListener) var enableDownloadListener

    private func highlightID(_ title: String) -> String {
        SettingsTab.liveActivities.highlightID(for: title)
    }

    var body: some View {
        Section {
            Defaults.Toggle(key: .enableDownloadListener) {
                Label("Enable download detection", systemImage: "arrow.down.circle")
            }
            .settingsHighlight(id: highlightID("Enable download detection"))
            VStack(alignment: .leading, spacing: 12) {
                Label("Download indicator style", systemImage: "arrow.down.circle")
                    .font(.system(size: 13, weight: .semibold))
                    // .white is invisible against a light Settings window;
                    // the label follows the appearance like every other one.
                    .foregroundStyle(enableDownloadListener ? Color.primary : Color.secondary)

                HStack(spacing: 16) {
                    DownloadStyleButton(
                        style: .progress,
                        isSelected: selectedDownloadIndicatorStyle == .progress,
                        disabled: !enableDownloadListener
                    ) {
                        selectedDownloadIndicatorStyle = .progress
                    }

                    DownloadStyleButton(
                        style: .circle,
                        isSelected: selectedDownloadIndicatorStyle == .circle,
                        disabled: !enableDownloadListener
                    ) {
                        selectedDownloadIndicatorStyle = .circle
                    }
                }

                Text("A bar that fills as the download runs, or a ring around the notch's corner.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .settingsHighlight(id: highlightID("Download indicator style"))

            VStack(alignment: .leading, spacing: 6) {
                Defaults.Toggle(key: .showDownloadSpeed) {
                    Label("Show download speed", systemImage: "clock")
                }
                .disabled(!enableDownloadListener)

                Text("Adds the current rate beside the indicator, measured from how fast the files in your Downloads folder are growing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .settingsHighlight(id: highlightID("Show download speed"))
        } header: {
            Text("Download Detection")
        } footer: {
            Text("Shows a live activity in the Dynamic Island while a file is downloading. Works with Safari, Firefox, and Chrome and the browsers built on it — Edge, Brave, Arc, Vivaldi and Opera. Only your Downloads folder is watched, so a file saved anywhere else will not appear.")
        }
    }

    struct DownloadStyleButton: View {
        let style: DownloadIndicatorStyle
        let isSelected: Bool
        let disabled: Bool
        let action: () -> Void

        @State private var isHovering = false

        var body: some View {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
                        )

                    if style == .progress {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                            .frame(width: 40)
                    } else {
                        SpinningCircleDownloadView()
                    }
                }
                .frame(width: 80, height: 60)
                .onHover { hovering in
                    if !disabled {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isHovering = hovering
                        }
                    }
                }

                Text(LocalizedStringKey(style.rawValue))
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 100)
                    .foregroundStyle(disabled ? .secondary : .primary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !disabled {
                    action()
                }
            }
            .opacity(disabled ? 0.5 : 1.0)
        }

        private var backgroundColor: Color {
            if disabled { return Color(nsColor: .controlBackgroundColor) }
            if isSelected { return Color.accentColor.opacity(0.1) }
            if isHovering { return Color.primary.opacity(0.05) }
            return Color(nsColor: .controlBackgroundColor)
        }

        private var borderColor: Color {
            if isSelected { return Color.accentColor }
            if isHovering { return Color.primary.opacity(0.1) }
            return Color.clear
        }
    }
}

final class HUDPreviewViewModel: ObservableObject {
    @Published var level: Float = 0
    @Published var iconName: String = "speaker.wave.3.fill"

    private var cancellables = Set<AnyCancellable>()

    init() {
        setup()
    }

    private func setup() {
        // Ensure controllers are active
        SystemVolumeController.shared.start()
        SystemBrightnessController.shared.start()
        SystemKeyboardBacklightController.shared.start()

        // Initial state from volume
        let vol = SystemVolumeController.shared.currentVolume
        self.level = vol
        if vol <= 0.01 { self.iconName = "speaker.slash.fill" }
        else if vol < 0.33 { self.iconName = "speaker.wave.1.fill" }
        else if vol < 0.66 { self.iconName = "speaker.wave.2.fill" }
        else { self.iconName = "speaker.wave.3.fill" }

        // Listeners
        NotificationCenter.default.publisher(for: .systemVolumeDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let vol = info["value"] as? Float {
                    self.level = vol
                    if vol <= 0.01 { self.iconName = "speaker.slash.fill" }
                    else if vol < 0.33 { self.iconName = "speaker.wave.1.fill" }
                    else if vol < 0.66 { self.iconName = "speaker.wave.2.fill" }
                    else { self.iconName = "speaker.wave.3.fill" }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .systemBrightnessDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let val = info["value"] as? Float {
                    self.level = val
                    self.iconName = "sun.max.fill"
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .keyboardBacklightDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let val = info["value"] as? Float {
                    self.level = val
                    self.iconName = val > 0.5 ? "light.max" : "light.min"
                }
            }
            .store(in: &cancellables)
    }
}

/// Disables a control while the selected external display app is the one actually
/// handling those keys.
///
/// Ownership is not the integration toggle on its own. `resolvedControlFlags()`
/// hands the keys over only while integration is enabled *and* the provider is
/// running, so quitting the provider gives them back to Eave -- and a control
/// gated on the toggle alone stays greyed out over a setting that has started
/// working again.
///
/// A modifier rather than a computed property per view: it carries the
/// observation of both providers with it, so a control re-enables the moment the
/// provider quits without every settings view having to observe them itself.
private struct ExternalKeyOwnershipModifier: ViewModifier {
    @Default(.enableThirdPartyDDCIntegration) private var integrationEnabled
    @Default(.thirdPartyDDCProvider) private var provider
    @ObservedObject private var betterDisplayManager = BetterDisplayManager.shared
    @ObservedObject private var lunarManager = LunarManager.shared

    let message: String

    private var providerRunning: Bool {
        switch provider {
        case .betterDisplay: return betterDisplayManager.isRunning
        case .lunar: return lunarManager.isRunning
        }
    }

    private var externalOwnsKeys: Bool {
        integrationEnabled && providerRunning
    }

    func body(content: Content) -> some View {
        content
            .disabled(externalOwnsKeys)
            .help(externalOwnsKeys ? message : "")
    }
}

extension View {
    /// Greys this control out while the running external display app owns the
    /// keys it configures.
    func disabledWhileExternalAppOwnsKeys(_ message: String) -> some View {
        modifier(ExternalKeyOwnershipModifier(message: message))
    }
}

private struct HUDAndOSDSettingsView: View {
    @State private var selectedTab: Tab = {
        if Defaults[.enableSystemHUD] { return .hud }
        if Defaults[.enableCustomOSD] { return .osd }
        if Defaults[.enableVerticalHUD] { return .vertical }
        if Defaults[.enableCircularHUD] { return .circular }
        return .hud
    }()
    @Default(.enableSystemHUD) var enableSystemHUD
    @Default(.enableCustomOSD) var enableCustomOSD
    @Default(.enableVerticalHUD) var enableVerticalHUD
    @Default(.enableCircularHUD) var enableCircularHUD
    @Default(.verticalHUDPosition) var verticalHUDPosition
    @Default(.enableVolumeHUD) var enableVolumeHUD
    @Default(.enableBrightnessHUD) var enableBrightnessHUD
    @Default(.enableKeyboardBacklightHUD) var enableKeyboardBacklightHUD
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.verticalHUDShowValue) var verticalHUDShowValue
    @Default(.verticalHUDInteractive) var verticalHUDInteractive
    @Default(.verticalHUDHeight) var verticalHUDHeight
    @Default(.verticalHUDWidth) var verticalHUDWidth
    @Default(.verticalHUDPadding) var verticalHUDPadding
    @Default(.verticalHUDUseAccentColor) var verticalHUDUseAccentColor
    @Default(.verticalHUDMaterial) var verticalHUDMaterial
    @Default(.verticalHUDLiquidGlassCustomizationMode) var verticalHUDLiquidGlassCustomizationMode
    @Default(.verticalHUDLiquidGlassVariant) var verticalHUDLiquidGlassVariant

    // Circular HUD Props
    @Default(.circularHUDShowValue) var circularHUDShowValue
    @Default(.circularHUDSize) var circularHUDSize
    @Default(.circularHUDStrokeWidth) var circularHUDStrokeWidth
    @Default(.circularHUDUseAccentColor) var circularHUDUseAccentColor
    @StateObject private var previewModel = HUDPreviewViewModel()
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    private enum Tab: String, CaseIterable, Identifiable {
        case hud = "Dynamic Island HUD"
        case osd = "Custom OSD"
        case vertical = "Vertical Bar"
        case circular = "Circular"

        var id: String { rawValue }
    }

    private var hudEnabled: Binding<Bool> {
        Binding(
            get: { self.enableSystemHUD || self.enableCustomOSD || self.enableVerticalHUD || self.enableCircularHUD },
            set: { enabled in
                self.enableSystemHUD = enabled && self.selectedTab == .hud
                self.enableCustomOSD = enabled && self.selectedTab == .osd
                self.enableVerticalHUD = enabled && self.selectedTab == .vertical
                self.enableCircularHUD = enabled && self.selectedTab == .circular
            }
        )
    }

    private var paneBackgroundColor: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var availableVerticalMaterials: [OSDMaterial] {
        if #available(macOS 26.0, *) {
            return OSDMaterial.allCases
        }
        return OSDMaterial.allCases.filter { $0 != .liquid }
    }

    private var verticalLiquidVariantBinding: Binding<Double> {
        Binding(
            get: { Double(verticalHUDLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                verticalHUDLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    private var hudVariantCards: some View {
            HStack(spacing: 16) {
                HUDSelectionCard(
                    title: String(localized: "Dynamic Island"),
                    isSelected: selectedTab == .hud,
                    action: {
                        let wasEnabled = hudEnabled.wrappedValue
                        selectedTab = .hud
                        hudEnabled.wrappedValue = wasEnabled
                    }
                ) {
                    VStack {
                        Capsule()
                            .fill(Color.black)
                            .frame(width: 64, height: 20)
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                            .overlay {
                                HStack(spacing: 6) {
                                    Image(systemName: previewModel.iconName)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 12)

                                    GeometryReader { geo in
                                        Capsule()
                                            .fill(Color.white.opacity(0.2))
                                            .overlay(alignment: .leading) {
                                                Capsule()
                                                    .fill(Color.white)
                                                    .frame(width: geo.size.width * CGFloat(previewModel.level))
                                                    .animation(.spring(response: 0.3), value: previewModel.level)
                                            }
                                    }
                                    .frame(height: 4)
                                }
                                .padding(.horizontal, 8)
                            }
                    }
                }

                HUDSelectionCard(
                    title: String(localized: "Custom OSD"),
                    isSelected: selectedTab == .osd,
                    action: {
                        let wasEnabled = hudEnabled.wrappedValue
                        selectedTab = .osd
                        hudEnabled.wrappedValue = wasEnabled
                    }
                ) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: previewModel.iconName)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                    .symbolRenderingMode(.hierarchical)
                                    .contentTransition(.symbolEffect(.replace))

                                GeometryReader { geo in
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.2))
                                        .overlay(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.primary)
                                                .frame(width: geo.size.width * CGFloat(previewModel.level))
                                                .animation(.spring(response: 0.3), value: previewModel.level)
                                        }
                                }
                                .frame(width: 36, height: 4)
                            }
                        }
                        .frame(width: 44, height: 44)
                }

                HUDSelectionCard(
                    title: String(localized: "Vertical Bar"),
                    isSelected: selectedTab == .vertical,
                    action: {
                        let wasEnabled = hudEnabled.wrappedValue
                        selectedTab = .vertical
                        hudEnabled.wrappedValue = wasEnabled
                    }
                ) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                        .overlay {
                            VStack {
                                GeometryReader { geo in
                                    VStack {
                                        Spacer()
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.white)
                                            .frame(height: max(0, geo.size.height * CGFloat(previewModel.level)))
                                            .animation(.spring(response: 0.3), value: previewModel.level)
                                    }
                                }
                                .mask(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .padding(.bottom, 2)

                                Image(systemName: previewModel.iconName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(previewModel.level > 0.15 ? .black : .secondary)
                                    .symbolRenderingMode(.hierarchical)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .padding(4)
                        }
                        .frame(width: 22, height: 54)
                }

                HUDSelectionCard(
                    title: String(localized: "Circular"),
                    isSelected: selectedTab == .circular,
                    action: {
                        let wasEnabled = hudEnabled.wrappedValue
                        selectedTab = .circular
                        hudEnabled.wrappedValue = wasEnabled
                    }
                ) {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: CGFloat(previewModel.level))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.3), value: previewModel.level)
                        Image(systemName: previewModel.iconName)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .frame(width: 44, height: 44)
                }
            }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable system control overlays", systemImage: "power", isOn: hudEnabled)
                    .settingsHighlight(id: SettingsTab.hudAndOSD.highlightID(for: "Enable system control overlays"))
            }
            Group {
                Section {
                    // Four fixed-width cards ask for about 490pt. In a grouped
                    // Form that is a hard minimum, so on a narrower window the
                    // whole settings pane was pushed wider to satisfy it and the
                    // content overflowed sideways. It scrolls instead when it
                    // does not fit, and lays out as a row whenever it does.
                    ViewThatFits(in: .horizontal) {
                        hudVariantCards
                        ScrollView(.horizontal, showsIndicators: false) {
                            hudVariantCards
                        }
                    }
                    .padding(.top, 8)
                }

                switch selectedTab {
                case .hud:
                    HUD()
                case .osd:
                    if #available(macOS 15.0, *) {
                        CustomOSDSettings()
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.orange)

                            Text("macOS 15 or later required")
                                .font(.headline)

                            Text("Custom OSD feature requires macOS 15 or later.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    }
                case .vertical:
                    Group {
                        if !enableThirdPartyDDCIntegration {
                            Section {
                                AccessibilitySettingsPermissionRow(message: "Accessibility permission is needed to intercept system controls for the Vertical HUD.")
                            } header: {
                                Text("Accessibility")
                            }
                        }

                        if accessibilityPermission.isAuthorized || enableThirdPartyDDCIntegration {
                            Section {
                                Toggle("Show volume HUD", systemImage: "speaker.wave.2", isOn: $enableVolumeHUD)
                                Toggle("Show brightness HUD", systemImage: "sun.max", isOn: $enableBrightnessHUD)
                                Toggle("Show keyboard backlight HUD", systemImage: "keyboard", isOn: $enableKeyboardBacklightHUD)
                                    .disabledWhileExternalAppOwnsKeys("Disabled while the external display app is running \u{2014} that app owns the keyboard backlight keys.")
                            } header: {
                                Text("Controls")
                            } footer: {
                                Text("Choose which system controls should display HUD notifications.")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }

                        Section {
                            Toggle("Show percentage", systemImage: "power", isOn: $verticalHUDShowValue)
                            Toggle("Use accent color", systemImage: "paintpalette", isOn: $verticalHUDUseAccentColor)
                            Toggle("Enable drag to adjust", systemImage: "power", isOn: $verticalHUDInteractive)
                            HStack(spacing: 12) {
                                Label("Material", systemImage: "circle.lefthalf.filled").accessibilityHidden(true)
                                Spacer(minLength: 12)
                                Picker(selection: $verticalHUDMaterial) {
                                    ForEach(availableVerticalMaterials, id: \.self) { material in
                                        Text(LocalizedStringKey(material.rawValue)).tag(material)
                                    }
                                } label: {
                                    Label("Material", systemImage: "circle.lefthalf.filled")
                                }
                                    .labelsHidden()
                            }

                            if verticalHUDMaterial == .liquid {
                                if #available(macOS 26.0, *) {
                                    SettingsSegmentedPicker(
                                        "Glass mode",
                                        selection: $verticalHUDLiquidGlassCustomizationMode,
                                        items: Array(LockScreenGlassCustomizationMode.allCases)
                                    ) { $0.rawValue }

                                    if verticalHUDLiquidGlassCustomizationMode == .customLiquid {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Label("Custom liquid variant", systemImage: "drop")
                                                Spacer()
                                            }
                                            SettingsSlider(value: verticalLiquidVariantBinding, in: liquidVariantRange, step: 1, valueLabel: Text("v\(verticalHUDLiquidGlassVariant.rawValue)"))
                                        }
                                    }
                                } else {
                                    Text("Custom Liquid is available on macOS 26 or later.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Defaults.Toggle(key: .useColorCodedVolumeDisplay) {
                                Label("Use color-coded volume display", systemImage: "speaker.wave.2")
                            }
                            Group {
                                Defaults.Toggle(key: .useSmoothColorGradient) {
                                    Label("Use smooth color transitions", systemImage: "paintpalette")
                                }
                            }
                            .disabled(!(Defaults[.useColorCodedVolumeDisplay]))
                        } header: {
                            Text("Behavior & Style")
                        }

                        Section {
                            HStack(spacing: 12) {
                                Label("HUD Position", systemImage: "rectangle.3.group").accessibilityHidden(true)
                                Spacer(minLength: 12)
                                Picker(selection: $verticalHUDPosition) {
                                    Text("Left").tag("left")
                                    Text("Right").tag("right")
                                } label: {
                                    Label("HUD Position", systemImage: "rectangle.3.group")
                                }
                                    .labelsHidden()
                            }
                            .pickerStyle(.menu)

                            VStack(alignment: .leading) {
                                Label("Screen Padding", systemImage: "arrow.left.and.right")
                                SettingsSlider(value: $verticalHUDPadding, in: 0...100, step: 4, valueLabel: Text("\(Int(verticalHUDPadding))px"))
                            }
                        } header: {
                            Text("Position")
                        } footer: {
                            Text("Choose directly on which side of the screen the vertical bar appears.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }

                        Section {
                            VStack(alignment: .leading) {
                                Label("Width", systemImage: "arrow.left.and.right")
                                SettingsSlider(value: $verticalHUDWidth, in: 24...80, step: 2, valueLabel: Text("\(Int(verticalHUDWidth))px"))
                            }
                            VStack(alignment: .leading) {
                                Label("Height", systemImage: "arrow.left.and.right")
                                SettingsSlider(value: $verticalHUDHeight, in: 100...500, step: 10, valueLabel: Text("\(Int(verticalHUDHeight))px"))
                            }
                            Button("Reset to Default") {
                                verticalHUDWidth = 36
                                verticalHUDHeight = 160
                                verticalHUDPadding = 24
                            }
                        } header: {
                            Text("Dimensions")
                        }
                    }

                case .circular:
                    Group {
                        if !enableThirdPartyDDCIntegration {
                            Section {
                                AccessibilitySettingsPermissionRow(message: "Accessibility permission is needed to intercept system controls for the Circular HUD.")
                            } header: {
                                Text("Accessibility")
                            }
                        }

                        if accessibilityPermission.isAuthorized || enableThirdPartyDDCIntegration {
                            Section {
                                Toggle("Show volume HUD", systemImage: "speaker.wave.2", isOn: $enableVolumeHUD)
                                Toggle("Show brightness HUD", systemImage: "sun.max", isOn: $enableBrightnessHUD)
                                Toggle("Show keyboard backlight HUD", systemImage: "keyboard", isOn: $enableKeyboardBacklightHUD)
                                    .disabledWhileExternalAppOwnsKeys("Disabled while the external display app is running \u{2014} that app owns the keyboard backlight keys.")
                            } header: {
                                Text("Controls")
                            } footer: {
                                Text("Choose which system controls should display HUD notifications.")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }

                        Section {
                            Toggle("Show percentage", systemImage: "power", isOn: $circularHUDShowValue)
                            Toggle("Use accent color", systemImage: "paintpalette", isOn: $circularHUDUseAccentColor)
                            Defaults.Toggle(key: .useColorCodedVolumeDisplay) {
                                Label("Use color-coded volume display", systemImage: "speaker.wave.2")
                            }
                            Group {
                                Defaults.Toggle(key: .useSmoothColorGradient) {
                                    Label("Use smooth color transitions", systemImage: "paintpalette")
                                }
                            }
                            .disabled(!(Defaults[.useColorCodedVolumeDisplay]))
                        } header: {
                            Text("Style")
                        }

                        Section {
                            VStack(alignment: .leading) {
                                Label("Size", systemImage: "arrow.left.and.right")
                                SettingsSlider(value: $circularHUDSize, in: 40...200, step: 5, valueLabel: Text("\(Int(circularHUDSize))px"))
                            }
                            VStack(alignment: .leading) {
                                Label("Line Width", systemImage: "arrow.left.and.right")
                                SettingsSlider(value: $circularHUDStrokeWidth, in: 2...16, step: 1, valueLabel: Text("\(Int(circularHUDStrokeWidth))px"))
                            }
                            Button("Reset to Default") {
                                circularHUDSize = 65
                                circularHUDStrokeWidth = 4
                            }
                        } header: {
                            Text("Dimensions")
                        }
                    }
                }

            }
            .disabled(!hudEnabled.wrappedValue)

            // Third-party display integrations also work independently of the overlay.
            ExternalDisplayIntegrationsSection()
        }
        .navigationTitle("Controls")
        .onAppear {
            if #unavailable(macOS 26.0), verticalHUDMaterial == .liquid {
                verticalHUDMaterial = .frosted
                verticalHUDLiquidGlassCustomizationMode = .standard
            }
        }
    }
}

// MARK: - External Display Integrations Settings Section

private struct ExternalDisplayIntegrationsSection: View {
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.thirdPartyDDCProvider) var thirdPartyDDCProvider
    @Default(.enableExternalVolumeControlListener) var enableExternalVolumeControlListener
    @Default(.volumeStepPercent) var volumeStepPercent
    @Default(.volumeFineStepPercent) var volumeFineStepPercent
    @Default(.brightnessStepPercent) var brightnessStepPercent
    @Default(.brightnessFineStepPercent) var brightnessFineStepPercent
    @ObservedObject private var betterDisplayManager = BetterDisplayManager.shared
    @ObservedObject private var lunarManager = LunarManager.shared

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    /// Whether the selected DDC provider is actually running.
    ///
    /// The one place that answers this. Ownership of the keys and everything the
    /// section says about the provider's state are read from here, so the
    /// controls and the status beside them cannot disagree about whether the
    /// provider is up.
    private var ddcProviderRunning: Bool {
        switch thirdPartyDDCProvider {
        case .betterDisplay: return betterDisplayManager.isRunning
        case .lunar: return lunarManager.isRunning
        }
    }

    /// Mirrors `SystemHUDManager.resolvedControlFlags()`: ownership only transfers
    /// while integration is enabled *and* the provider is running. When the
    /// provider is quit, Eave handles the keys again and the saved step sizes
    /// apply, so the controls have to come back with it.
    private var externalOwnsBrightness: Bool {
        enableThirdPartyDDCIntegration && ddcProviderRunning
    }

    private var externalOwnsVolume: Bool {
        externalOwnsBrightness && enableExternalVolumeControlListener
    }

    private var providerStatusText: String {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if ddcProviderRunning { return String(localized: "Running") }
            if betterDisplayManager.isDetected { return String(localized: "Not running") }
            return String(localized: "Not detected")
        case .lunar:
            if lunarManager.isConnected { return String(localized: "Connected") }
            if ddcProviderRunning { return String(localized: "Running") }
            if lunarManager.isDetected { return String(localized: "Not running") }
            return String(localized: "Not detected")
        }
    }

    private var providerStatusColor: Color {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if ddcProviderRunning { return .green }
            if betterDisplayManager.isDetected { return .orange }
            return .secondary
        case .lunar:
            if lunarManager.isConnected { return .green }
            if ddcProviderRunning { return .orange }
            if lunarManager.isDetected { return .orange }
            return .secondary
        }
    }

    private var providerStatusDescription: String {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if !betterDisplayManager.isDetected {
                return String(localized: "Install [BetterDisplay](https://betterdisplay.pro) to control external display brightness (and optional volume) through Eave's HUD.")
            }
            if !ddcProviderRunning {
                return String(localized: "BetterDisplay is installed but not currently running. Launch BetterDisplay to enable integration.")
            }
            return String(localized: "BetterDisplay OSD events will be routed through Eave's active HUD style. Brightness is always routed; volume is routed when external volume control listener is enabled below. Make sure BetterDisplay's OSD integration is enabled in Settings › Application › Integration.")
        case .lunar:
            if !lunarManager.isDetected {
                return String(localized: "Install [Lunar](https://lunar.fyi) to control external display brightness, contrast, and optional volume through Eave's HUD via DDC.")
            }
            if !ddcProviderRunning {
                return String(localized: "Lunar is installed but not currently running. Launch Lunar to enable integration.")
            }
            if lunarManager.isConnected {
                return String(localized: "Connected to Lunar's DDC socket. Brightness and contrast adjustments are shown through Eave's HUD; volume follows when external volume control listener is enabled below.")
            }
            return String(localized: "Lunar is running but the socket connection is not yet established. It will connect automatically.")
        }
    }

    private func refreshDetectionStatus() {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            betterDisplayManager.refreshDetectionStatus()
        case .lunar:
            lunarManager.refreshDetectionStatus()
        }
    }

    var body: some View {
        Group {
            Section {
                Stepper(value: $volumeStepPercent, in: 1...25) {
                    HStack {
                        Label("Volume step", systemImage: "speaker.wave.2")
                        Spacer()
                        Text("\(volumeStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Volume step"))
                .disabled(externalOwnsVolume)
                .help(externalOwnsVolume ? "Disabled while \"Enable external volume control listener\" is on in External Display Integrations \u{2014} that app owns the volume keys." : "")

                Stepper(value: $volumeFineStepPercent, in: 1...25) {
                    HStack {
                        Label("Volume fine step", systemImage: "speaker.wave.2")
                        Spacer()
                        Text("\(volumeFineStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Volume fine step"))
                .disabled(externalOwnsVolume)
                .help(externalOwnsVolume ? "Disabled while \"Enable external volume control listener\" is on in External Display Integrations \u{2014} that app owns the volume keys." : "")

                if externalOwnsVolume {
                    Text("Disabled while external display volume integration is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Stepper(value: $brightnessStepPercent, in: 1...25) {
                    HStack {
                        Label("Brightness step", systemImage: "slider.horizontal.3")
                        Spacer()
                        Text("\(brightnessStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Brightness step"))
                .disabled(externalOwnsBrightness)
                .help(externalOwnsBrightness ? "Disabled while external display integration is on \u{2014} that app owns the brightness keys." : "")

                Stepper(value: $brightnessFineStepPercent, in: 1...25) {
                    HStack {
                        Label("Brightness fine step", systemImage: "slider.horizontal.3")
                        Spacer()
                        Text("\(brightnessFineStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Brightness fine step"))
                .disabled(externalOwnsBrightness)
                .help(externalOwnsBrightness ? "Disabled while external display integration is on \u{2014} that app owns the brightness keys." : "")

                if externalOwnsBrightness {
                    Text("Disabled while external display brightness integration is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Step size")
            } footer: {
                Text("Percent change per key press. Fine step applies when holding Shift+Option.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .enableDirectDisplayVolumeControl) {
                    Label("Enable direct display volume control (DDC)", systemImage: "speaker.wave.2")
                }
                Text("Requires Apple silicon and one identifiable external display. Controls HDMI or DisplayPort volume when macOS cannot, and yields to the selected external volume provider while it is active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Enable third-party DDC app integration", systemImage: "power", isOn: $enableThirdPartyDDCIntegration)
                    .settingsHighlight(id: highlightID("Third-party DDC app integration"))

                if enableThirdPartyDDCIntegration {
                    HStack(spacing: 12) {
                        Label("Provider", systemImage: "slider.horizontal.3").accessibilityHidden(true)
                        Spacer(minLength: 12)
                        Picker(selection: $thirdPartyDDCProvider) {
                            ForEach(ThirdPartyDDCProvider.allCases) { provider in
                                HStack {
                                    AppIconImage(
                                        bundleIdentifiers: provider.bundleIdentifiers,
                                        symbolFallback: "display",
                                        symbolColor: .secondary
                                    )
                                    Text(provider.displayName)
                                }
                                .tag(provider)
                            }
                        } label: {
                            Label("Provider", systemImage: "slider.horizontal.3")
                        }
                            .labelsHidden()
                    }
                    .settingsHighlight(id: highlightID("Third-party DDC provider"))

                    Toggle("Enable external volume control listener", systemImage: "speaker.wave.2", isOn: $enableExternalVolumeControlListener)
                        .settingsHighlight(id: highlightID("Enable external volume control listener"))

                    Text(
                        enableExternalVolumeControlListener
                        ? "Eave's built-in volume key interception is disabled while external volume listening is on. Volume HUD/OSD will follow \(thirdPartyDDCProvider.displayName) payloads."
                        : "Eave keeps native volume key interception. External provider volume payloads are ignored while this is off."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack {
                        Label("Status", systemImage: "info.circle")
                        Spacer()
                        Text(providerStatusText)
                            .font(.caption)
                            .foregroundStyle(providerStatusColor)
                    }

                    Text(providerStatusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        refreshDetectionStatus()
                    } label: {
                        Label("Refresh detection", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                } else {
                    Text("Enable to route BetterDisplay or Lunar display adjustments through Eave's active HUD style.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if enableThirdPartyDDCIntegration {
                    Text("Eave always listens to selected-provider brightness events, and listens to provider volume events only when external volume listener is enabled.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }
}

private struct HUDSelectionCard<Preview: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let preview: Preview

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.clear,
                                    lineWidth: 2.5
                                )
                        )
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)

                    preview
                }
                .frame(width: 110, height: 80)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 4, height: 4)
                    } else {
                        Color.clear
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

private struct DevicesSettingsView: View {
    @Default(.progressBarStyle) var progressBarStyle
    @Default(.useBluetoothHUD3DIcon) private var useBluetoothHUD3DIcon
    @Default(.enablePerAppVolume) private var enablePerAppVolume

    private func highlightID(_ title: String) -> String {
        SettingsTab.devices.highlightID(for: title)
    }

    private var colorCodingDisabled: Bool {
        progressBarStyle == .segmented
    }

    var body: some View {
        Form {
            Section {
                AudioSettingsPermissionRow()
                Defaults.Toggle(key: .enablePerAppVolume) {
                    Label("Enable per-app volume", systemImage: "speaker.wave.2")
                }
                .settingsHighlight(id: highlightID("Enable per-app volume"))

                Defaults.Toggle(key: .showPerAppVolumeIcon) {
                    Label("Show app volume icon in the notch", systemImage: "speaker.wave.2")
                }
                .disabled(!enablePerAppVolume)
                .settingsHighlight(id: highlightID("Show app volume icon in the notch"))

                Button("Reset all app volumes") {
                    PerAppVolumeManager.shared.resetAll()
                }
                .disabled(!enablePerAppVolume)
                .settingsHighlight(id: highlightID("Reset all app volumes"))
            } header: {
                Text("App Volume")
            } footer: {
                Text("Gives each app its own volume and mute, independent of the system volume. macOS will ask for audio recording permission the first time an app's level is changed: routing an app's audio through Eave is the only way it can be adjusted, and nothing is ever recorded or written to disk. Apps left at 100% and unmuted keep their normal, untouched path to the speakers.")
            }

            Section {
                Defaults.Toggle(key: .showBluetoothDeviceConnections) {
                    Label("Show Bluetooth device connections", systemImage: "headphones")
                }
                .settingsHighlight(id: highlightID("Show Bluetooth device connections"))
                Defaults.Toggle(key: .useCircularBluetoothBatteryIndicator) {
                    Label("Use circular battery indicator", systemImage: "battery.100")
                }
                .settingsHighlight(id: highlightID("Use circular battery indicator"))
                Defaults.Toggle(key: .showBluetoothBatteryPercentageText) {
                    Label("Show battery percentage text in HUD", systemImage: "battery.100")
                }
                .settingsHighlight(id: highlightID("Show battery percentage text in HUD"))
                Defaults.Toggle(key: .showBluetoothDeviceNameMarquee) {
                    Label("Scroll device name in HUD", systemImage: "hand.draw")
                }
                .settingsHighlight(id: highlightID("Scroll device name in HUD"))
                Defaults.Toggle(key: .showAirPodsListeningModeChanges) {
                    Label("Show AirPods listening mode changes", systemImage: "headphones")
                }
                .settingsHighlight(id: highlightID("Show AirPods listening mode changes"))
                VStack(alignment: .leading, spacing: 12) {
                    Label("HUD icon style", systemImage: "square.grid.2x2")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 16) {
                        Spacer(minLength: 0)
                        BluetoothHUDIconStyleCard(
                            style: .symbol,
                            isSelected: !useBluetoothHUD3DIcon
                        ) {
                            useBluetoothHUD3DIcon = false
                        }
                        BluetoothHUDIconStyleCard(
                            style: .threeD,
                            isSelected: useBluetoothHUD3DIcon
                        ) {
                            useBluetoothHUD3DIcon = true
                        }
                        Spacer(minLength: 0)
                    }
                }
                .settingsHighlight(id: highlightID("Use 3D Bluetooth HUD icon"))
            } header: {
                Text("Bluetooth Audio Devices")
            } footer: {
                Text("Displays a HUD notification when Bluetooth audio devices (headphones, AirPods, speakers) connect, showing device name and battery level.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .useColorCodedBatteryDisplay) {
                    Label("Use color-coded battery display", systemImage: "battery.100")
                }
                .disabled(colorCodingDisabled)
                .settingsHighlight(id: highlightID("Use color-coded battery display"))
            } header: {
                Text("Battery Indicator Styling")
            } footer: {
                if progressBarStyle == .segmented {
                    Text("Color-coded fills are unavailable in Segmented mode. Switch to Hierarchical or Gradient inside Controls › Dynamic Island to adjust advanced options.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else if Defaults[.useSmoothColorGradient] {
                    Text("Smooth transitions blend Green (0–60%), Yellow (60–85%), and Red (85–100%) through the entire fill. Adjust gradient behavior from Controls › Dynamic Island.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text("Discrete transitions snap between Green (0–60%), Yellow (60–85%), and Red (85–100%).")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Devices")
    }
}

struct HUD: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.progressBarStyle) var progressBarStyle
    @Default(.enableSystemHUD) var enableSystemHUD
    @Default(.enableVolumeHUD) var enableVolumeHUD
    @Default(.enableBrightnessHUD) var enableBrightnessHUD
    @Default(.enableKeyboardBacklightHUD) var enableKeyboardBacklightHUD
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.systemHUDSensitivity) var systemHUDSensitivity
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    private var hasAccessibilityPermission: Bool {
        accessibilityPermission.isAuthorized
    }

    private var colorCodingDisabled: Bool {
        progressBarStyle == .segmented
    }

    var body: some View {
        Group {
            if !enableThirdPartyDDCIntegration {
                Section {
                    AccessibilitySettingsPermissionRow(message: "Accessibility permission lets Dynamic Island replace the native volume, brightness, and keyboard HUDs.")
                } header: {
                    Text("Accessibility")
                }
            }



            if enableSystemHUD && !Defaults[.enableCustomOSD] && (hasAccessibilityPermission || enableThirdPartyDDCIntegration) {
                Section {
                    Toggle("Show volume HUD", systemImage: "speaker.wave.2", isOn: $enableVolumeHUD)
                    Toggle("Show brightness HUD", systemImage: "sun.max", isOn: $enableBrightnessHUD)
                    Toggle("Show keyboard backlight HUD", systemImage: "keyboard", isOn: $enableKeyboardBacklightHUD)
                        .disabledWhileExternalAppOwnsKeys("Disabled while the external display app is running \u{2014} that app owns the keyboard backlight keys.")
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Choose which system controls should display HUD notifications.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section {
                Defaults.Toggle(key: .playVolumeChangeFeedback) {
                    Label("Play feedback when volume is changed", systemImage: "speaker.wave.2")
                }
                .settingsHighlight(id: highlightID("Play feedback when volume is changed"))
                .help("Plays the supplied feedback clip whenever you press the hardware volume keys.")
            } header: {
                Text("Audio feedback")
            } footer: {
                Text("Requires Accessibility permission so Dynamic Island can intercept the hardware volume keys.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .useColorCodedVolumeDisplay) {
                    Label("Use color-coded volume display", systemImage: "speaker.wave.2")
                }
                .disabled(colorCodingDisabled)
                .settingsHighlight(id: highlightID("Use color-coded volume display"))

                if !colorCodingDisabled && (Defaults[.useColorCodedBatteryDisplay] || Defaults[.useColorCodedVolumeDisplay]) {
                    Defaults.Toggle(key: .useSmoothColorGradient) {
                        Label("Use smooth color transitions", systemImage: "paintpalette")
                    }
                    .settingsHighlight(id: highlightID("Use smooth color transitions"))
                }

                Defaults.Toggle(key: .showProgressPercentages) {
                    Label("Show percentages beside progress bars", systemImage: "power")
                }
                .settingsHighlight(id: highlightID("Show percentages beside progress bars"))
            } header: {
                Text("Dynamic Island Progress Bars")
            } footer: {
                if colorCodingDisabled {
                    Text("Color-coded fills and smooth gradients are unavailable in Segmented mode. Switch to Hierarchical or Gradient to adjust these options.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else if Defaults[.useSmoothColorGradient] {
                    Text("Smooth transitions blend Green (0–60%), Yellow (60–85%), and Red (85–100%) through the entire fill.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text("Discrete transitions snap between Green (0–60%), Yellow (60–85%), and Red (85–100%).")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section {
                HStack(spacing: 12) {
                    Label("HUD style", systemImage: "circle.lefthalf.filled").accessibilityHidden(true)
                    Spacer(minLength: 12)
                    Picker(selection: $inlineHUD) {
                        Text("Default")
                            .tag(false)
                        Text("Inline")
                            .tag(true)
                    } label: {
                        Label("HUD style", systemImage: "circle.lefthalf.filled")
                    }
                        .labelsHidden()
                }
                .settingsHighlight(id: highlightID("HUD style"))
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.progressBarStyle] = .hierarchical
                        }
                    }
                }
                HStack(spacing: 12) {
                    Label("Progressbar style", systemImage: "circle.lefthalf.filled").accessibilityHidden(true)
                    Spacer(minLength: 12)
                    Picker(selection: $progressBarStyle) {
                        Text("Hierarchical")
                            .tag(ProgressBarStyle.hierarchical)
                        Text("Gradient")
                            .tag(ProgressBarStyle.gradient)
                        Text("Segmented")
                            .tag(ProgressBarStyle.segmented)
                    } label: {
                        Label("Progressbar style", systemImage: "circle.lefthalf.filled")
                    }
                        .labelsHidden()
                }
                .settingsHighlight(id: highlightID("Progressbar style"))
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Label("Enable glowing effect", systemImage: "sparkles")
                }
                .settingsHighlight(id: highlightID("Enable glowing effect"))
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Label("Use accent color", systemImage: "paintpalette")
                }
                .settingsHighlight(id: highlightID("Use accent color"))
            } header: {
                HStack {
                    Text("Appearance")
                }
            }
        }
        .navigationTitle("Controls")
        .onAppear {
            accessibilityPermission.refreshStatus()
        }
        .onChange(of: accessibilityPermission.isAuthorized) { _, granted in
            if !granted {
                enableSystemHUD = false
            }
        }
    }
}

private struct MusicSourceSelector: View {
    @Binding var selection: MediaControllerType
    let controllers: [MediaControllerType]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(controllers) { controller in
                        MusicSourceCard(
                            controller: controller,
                            isSelected: selection == controller
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selection = controller
                            }
                        }
                        .id(controller)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
            }
            .onAppear {
                proxy.scrollTo(selection, anchor: .center)
            }
            .onChange(of: selection) { _, controller in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(controller, anchor: .center)
                }
            }
        }
        .frame(height: 112)
    }
}

private struct MusicSourceCard: View {
    let controller: MediaControllerType
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                // Every source shows the app's own icon, so the row does not
                // mix real icons for the apps we happen to ship a logo for
                // with flat brand marks for the rest. The bundled logo is the
                // fallback for when the app is not installed, which is better
                // than the generic symbol that used to stand in there.
                AppIconImage(
                    bundleIdentifiers: controller.applicationBundleIdentifiers,
                    assetFallback: controller.officialLogoAssetName,
                    symbolFallback: controller.fallbackSymbol,
                    symbolColor: controller.fallbackColor,
                    size: 42
                )
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 42, height: 42)

                Text(controller.localizedName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 112, height: 92)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2.5 : 1)
            }
            .scaleEffect(isHovering && !isSelected ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(controller.localizedName)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        if isHovering {
            return Color(nsColor: .controlBackgroundColor).opacity(0.92)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.7)
    }

    private var borderColor: Color {
        if isSelected {
            return .accentColor
        }
        return Color(nsColor: .separatorColor).opacity(isHovering ? 0.8 : 0.45)
    }
}

private extension MediaControllerType {
    var officialLogoAssetName: String? {
        switch self {
        case .youtubeMusic: return "YouTubeMusicLogo"
        case .amazonMusic: return "AmazonMusicLogo"
        case .tidal: return "TidalLogo"
        case .cider: return "CiderLogo"
        default: return nil
        }
    }

    var applicationBundleIdentifiers: [String] {
        switch self {
        case .nowPlaying:
            return []
        case .appleMusic:
            return ["com.apple.Music"]
        case .spotify:
            return ["com.spotify.client"]
        case .youtubeMusic:
            return ["com.github.th-ch.youtube-music"]
        case .amazonMusic:
            return ["com.amazon.music"]
        case .tidal:
            return [TidalController.bundleIdentifier]
        case .cider:
            return ["sh.cider.genten.mac"]
        }
    }

    var fallbackSymbol: String {
        switch self {
        case .nowPlaying: return "waveform"
        case .appleMusic: return "music.note"
        case .spotify: return "dot.radiowaves.left.and.right"
        case .youtubeMusic: return "play.rectangle.fill"
        case .amazonMusic: return "music.note.list"
        case .tidal: return "waveform.path"
        case .cider: return "cup.and.saucer.fill"
        }
    }

    var fallbackColor: Color {
        switch self {
        case .nowPlaying: return .accentColor
        case .appleMusic: return .pink
        case .spotify: return .green
        case .youtubeMusic: return .red
        case .amazonMusic: return .cyan
        case .tidal: return .primary
        case .cider: return .orange
        }
    }
}

struct Media: View {
    @Default(.sliderColor) private var sliderColor
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.showShuffleAndRepeat) private var showShuffleAndRepeat
    @Default(.showMediaOutputControl) private var showMediaOutputControl
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @Default(.musicControlWindowEnabled) private var musicControlWindowEnabled
    @Default(.enableLockScreenMediaWidget) private var enableLockScreenMediaWidget
    @Default(.showSneakPeekOnTrackChange) private var showSneakPeekOnTrackChange
    @Default(.lockScreenGlassStyle) private var lockScreenGlassStyle
    @Default(.lockScreenGlassCustomizationMode) private var lockScreenGlassCustomizationMode
    @Default(.lockScreenMusicAlbumParallaxEnabled) private var lockScreenMusicAlbumParallaxEnabled
    @Default(.lockScreenMusicFullscreenArtworkEnabled) private var lockScreenMusicFullscreenArtworkEnabled
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.autoHideInactiveNotchMediaPlayer) private var autoHideInactiveNotchMediaPlayer
    @Default(.enableLyrics) private var enableLyrics
    @Default(.pinLyricsWhenClosed) private var pinLyricsWhenClosed
    @Default(.pinnedLyricFontSize) private var pinnedLyricFontSize
    @Default(.pinnedLyricContext) private var pinnedLyricContext
    @Default(.lyricHighlightStyle) private var lyricHighlightStyle
    @Default(.lyricsScript) private var lyricsScript
    @Default(.lyricsTimingOffset) private var lyricsTimingOffset
    @Default(.lyricsPanelWidth) private var lyricsPanelWidth
    @Default(.lyricsPanelOffset) private var lyricsPanelOffset
    @Default(.visualizerBarCount) private var visualizerBarCount
    @Default(.enableWaveformScrubber) private var enableWaveformScrubber
    @Default(.colorExtractionMode) private var colorExtractionMode
    @Default(.parallaxEffectIntensity) private var parallaxEffectIntensity


    @ObservedObject private var musicManager = MusicManager.shared

    private var isAppleMusicActive: Bool {
        musicManager.bundleIdentifier == "com.apple.Music"
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.media.highlightID(for: title)
    }

    private var standardControlsSuppressed: Bool {
        !showStandardMediaControls && !enableMinimalisticUI
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Label("Music Source", systemImage: "music.note")
                            .font(.system(size: 13, weight: .semibold))
                        MediaSourceCapabilitiesButton(controllers: MediaControllerType.allCases)
                        Spacer()
                        ScrollHintIndicator()
                    }

                    MusicSourceSelector(
                        selection: $mediaController,
                        controllers: MediaControllerType.allCases
                    )
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
                .settingsHighlight(id: highlightID("Music Source"))
            } header: {
                Text("Media Source")
            } footer: {
                if mediaController == .youtubeMusic {
                    HStack {
                        Text("YouTube Music requires this third-party app to be installed: ")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link("https://github.com/th-ch/youtube-music", destination: URL(string: "https://github.com/th-ch/youtube-music")!)
                            .font(.caption)
                            .foregroundColor(.blue) // Ensures it's visibly a link
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "'Now Playing' was the only option on previous versions and works with all media apps."))
                        if mediaController == .amazonMusic || mediaController == .tidal || mediaController == .cider {
                            Text(mediaController.description)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }

            if mediaController == .spotify {
                SpotifyAuthSettingsSection()
                SpotifyLikeButtonSettingsSection()
            }

            if mediaController == .cider {
                CiderFavoritingSettingsSection()
            }

            Section {
                Defaults.Toggle(key: .showStandardMediaControls) {
                    Label("Show media controls in Dynamic Island", systemImage: "music.note")
                }
                .disabled(enableMinimalisticUI)
                .settingsHighlight(id: highlightID("Show media controls in Dynamic Island"))

                Defaults.Toggle(key: .autoHideInactiveNotchMediaPlayer) {
                    Label("Auto-hide inactive notch media player", systemImage: "music.note")
                }
                .disabled(enableMinimalisticUI || !showStandardMediaControls)
                .settingsHighlight(id: highlightID("Auto-hide inactive notch media player"))

                if enableMinimalisticUI {
                    Text("Disable Minimalistic UI to configure the standard notch media controls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if standardControlsSuppressed {
                    Text("Standard notch media controls are hidden. Re-enable the toggle above to restore them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !autoHideInactiveNotchMediaPlayer {
                    Text("When disabled, the notch music player stays visible with placeholder metadata even when playback is inactive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Dynamic Island Visibility")
            }
            Section {
                Defaults.Toggle(key: .showShuffleAndRepeat) {
                    HStack {
                        Label("Enable customizable controls", systemImage: "slider.horizontal.3")
                        customBadge(text: "Beta")
                    }
                }
                Group {
                    Defaults.Toggle(key: .showMediaOutputControl) {
                        Label("Show \"Change Media Output\" control", systemImage: "airplay.audio")
                    }
                    .settingsHighlight(id: highlightID("Show Change Media Output control"))
                    .help("Adds the AirPlay/route picker button back to the customizable controls palette. The lock screen panel also uses this button for its volume slider, so turning it off leaves that panel with no volume control.")
                    MusicSlotConfigurationView()
                }
                .disabled(!showShuffleAndRepeat)
            } header: {
                Text("Media controls")
            }

            Section("Lock Screen Media") {
                LockScreenSettingsLink(title: "Show lock screen media panel")
            }
            Section {
                SettingsSegmentedPicker(
                    "Skip buttons",
                    selection: $musicSkipBehavior,
                    items: Array(MusicSkipBehavior.allCases)
                ) { $0.displayName }
                .settingsHighlight(id: highlightID("Skip buttons"))

                Text(musicSkipBehavior.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Skip button behaviour")
            } footer: {
                Text("Applies everywhere the transport controls appear: the notch player, the lock screen panel, and the floating window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(
                    "Enable music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                .disabled(standardControlsSuppressed)
                .help(standardControlsSuppressed ? "Standard notch media controls are hidden while this toggle is off." : "")
                Defaults.Toggle(key: .showMusicPerimeterProgress) {
                    Label("Show music perimeter progress", systemImage: "music.note")
                }
                .settingsHighlight(id: highlightID("Show music perimeter progress"))
                Defaults.Toggle(key: .musicControlWindowEnabled) {
                    Label("Show floating media controls", systemImage: "music.note")
                }
                .disabled(!coordinator.musicLiveActivityEnabled || standardControlsSuppressed)
                .help("Displays play/pause and skip buttons beside the notch while music is active. Disabled by default.")
                Toggle("Enable sneak peek", systemImage: "power", isOn: $enableSneakPeek)
                Toggle("Show sneak peek on playback changes", systemImage: "music.note", isOn: $showSneakPeekOnTrackChange)
                    .disabled(!enableSneakPeek)
                Defaults.Toggle(key: .showLiveCanvasInDynamicIsland) {
                    Label("Show live canvas in Dynamic Island", systemImage: "power")
                }
                .settingsHighlight(id: highlightID("Show live canvas in Dynamic Island"))
                .help("Replaces the artwork tile with the live canvas when the current app provides one, and reuses that moving canvas for the surrounding lighting effect.")

                //Parallax Effect Intensity to control how much parallax is wanted
                SettingsSlider(value: $parallaxEffectIntensity, in: 0...12, step: 1.0, valueLabel: Text("\(parallaxEffectIntensity, specifier: "%0.1f")")) {
                    HStack {
                        Text("Parallax Effect Intensity")
                        Spacer()
                    }
                }
                .settingsHighlight(id: highlightID("Enable album art parallax effect"))

                HStack(spacing: 12) {
                    Label("Sneak Peek Style", systemImage: "circle.lefthalf.filled").accessibilityHidden(true)
                    Spacer(minLength: 12)
                    Picker(selection: $sneakPeekStyles){
                        ForEach(SneakPeekStyle.allCases) { style in
                            Text(style.localizedName).tag(style)
                        }
                    } label: {
                        Label("Sneak Peek Style", systemImage: "circle.lefthalf.filled")
                    }
                        .labelsHidden()
                }
                .disabled(!enableSneakPeek)
                .settingsHighlight(id: highlightID("Sneak Peek Style"))

                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Defaults.Toggle(key: .showSongMetadataInClosedNotch) {
                    Label("Show song title and artist on non-notch displays", systemImage: "music.note")
                }
                .settingsHighlight(id: highlightID("Show song title and artist in closed notch"))
            } header: {
                Text("Media playback live activity")
            }

            Section {
                Defaults.Toggle(key: .enableLyrics) {
                    Label("Show lyrics", systemImage: "power")
                }
                .disabled(enableMinimalisticUI || !showStandardMediaControls)
                .help(
                    enableMinimalisticUI
                        ? "Disable Minimalistic UI to show lyrics."
                        : !showStandardMediaControls
                            ? "Enable Dynamic Island media controls to show lyrics."
                            : ""
                )
                .settingsHighlight(id: highlightID("Show lyrics"))

                Group {
                    SettingsSegmentedPicker(
                        "Lyrics script",
                        selection: $lyricsScript,
                        items: Array(LyricsScript.allCases)
                    ) { $0.localizedName }
                    .settingsHighlight(id: highlightID("Lyrics script"))

                    // Caption inside the row rather than after it: a Form gives
                    // every top-level view its own row and a divider, so the
                    // explanation was being ruled off from the control it
                    // explains and read as belonging to nothing.
                    VStack(alignment: .leading, spacing: 6) {
                        SettingsSegmentedPicker(
                            "Highlight",
                            selection: $lyricHighlightStyle,
                            items: Array(LyricHighlightStyle.allCases)
                        ) { $0.localizedName }

                        Text(lyricHighlightStyle.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .settingsHighlight(id: highlightID("Lyric highlight"))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center) {
                            Label("Lyrics timing adjustment", systemImage: "slider.horizontal.3")
                            Spacer()
                            Text(lyricsTimingOffset, format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
                                .monospacedDigit()
                            Button("Reset to Default") { lyricsTimingOffset = 0 }
                                .disabled(lyricsTimingOffset == 0)
                            Stepper("Lyrics timing adjustment", value: $lyricsTimingOffset, in: -10...10, step: 0.1)
                                .labelsHidden()
                                .fixedSize()
                                .accessibilityValue(lyricsTimingOffset.formatted(.number.precision(.fractionLength(1))))
                        }
                        Text("Seconds: + advances lyrics, − delays them. Applies to all songs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .settingsHighlight(id: highlightID("Lyrics timing adjustment"))
                }
                .disabled(!(enableLyrics && !enableMinimalisticUI && showStandardMediaControls))

                Group {
                    Defaults.Toggle(key: .pinLyricsWhenClosed) {
                        Label("Keep lyrics under the closed notch", systemImage: "slider.horizontal.3")
                    }
                    .settingsHighlight(id: highlightID("Keep lyrics under the closed notch"))

                    SettingsSegmentedPicker(
                        "Pinned lyric context",
                        selection: $pinnedLyricContext,
                        items: Array(PinnedLyricContext.allCases)
                    ) { $0.localizedName }
                    .disabled(!pinLyricsWhenClosed)
                    .settingsHighlight(id: highlightID("Pinned lyric context"))

                    SettingsSlider(value: $pinnedLyricFontSize, in: 8...24, step: 1, valueLabel: Text("\(Int(pinnedLyricFontSize)) pt")) {
                        HStack {
                            Label("Pinned lyric font size", systemImage: "arrow.left.and.right")
                            Spacer()
                        }
                    }
                    .disabled(!pinLyricsWhenClosed)
                    .settingsHighlight(id: highlightID("Pinned lyric font size"))


                    Text("Shows timed lyrics below the closed notch with the selected context. Keeps the space during instrumental breaks; hides the words while a HUD is on screen. Can also be toggled from the pin on the lyrics panel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .disabled(!(enableLyrics && !enableMinimalisticUI && showStandardMediaControls))

                Text("Lyrics get their own panel beside the player.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if enableMinimalisticUI {
                    Text("Disable Minimalistic UI to use lyrics.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !showStandardMediaControls {
                    Text("Enable Dynamic Island media controls to use lyrics.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Group {
                    SettingsSlider(value: $lyricsPanelWidth, in: 180...420, step: 10, valueLabel: Text("\(Int(lyricsPanelWidth)) px")) {
                        HStack {
                            Label("Side lyrics width", systemImage: "arrow.left.and.right")
                            Spacer()
                        }
                    }
                    .settingsHighlight(id: highlightID("Side lyrics width"))

                    SettingsSlider(value: $lyricsPanelOffset, in: -100...100, step: 1, valueLabel: Text("\(lyricsPanelOffset >= 0 ? "+" : "")\(Int(lyricsPanelOffset)) px")) {
                        HStack {
                            Label("Side lyrics horizontal offset", systemImage: "slider.horizontal.3")
                            Spacer()
                        }
                    }
                    .settingsHighlight(id: highlightID("Side lyrics horizontal offset"))

                    Text("These controls apply when the calendar is disabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!(enableLyrics && !enableMinimalisticUI && showStandardMediaControls))
            } header: {
                Text("Lyrics")
            }

            Section {
                Defaults.Toggle(key: .enableRealTimeWaveform) {
                    HStack {
                        Label("Enable real-time waveform", systemImage: "clock")
                        customBadge(text: "Beta")
                    }
                }
                .settingsHighlight(id: highlightID("Enable real-time waveform"))
                
                HStack(spacing: 12) {
                    Label("Visualizer candles", systemImage: "music.note").accessibilityHidden(true)
                    Spacer(minLength: 12)
                    Picker(selection: $visualizerBarCount) {
                        Text("4").tag(4)
                        Text("5").tag(5)
                        Text("6").tag(6)
                    } label: {
                        Label("Visualizer candles", systemImage: "music.note")
                    }
                        .labelsHidden()
                }

                HStack(spacing: 12) {
                    Label("Color extraction", systemImage: "paintpalette").accessibilityHidden(true)
                    Spacer(minLength: 12)
                    Picker(selection: $colorExtractionMode) {
                        Text("Legacy").tag(ColorExtractionMode.legacy)
                        Text("Vibrant").tag(ColorExtractionMode.vibrant)
                    } label: {
                        Label("Color extraction", systemImage: "paintpalette")
                    }
                        .labelsHidden()
                }

                Toggle("Enable waveform scrubbing", systemImage: "power", isOn: $enableWaveformScrubber)
            } header: {
                Text("Music Visualizer")
            } footer: {
                Text("When enabled, the music visualizer displays real-time audio spectrum data synced to your music. Requires macOS 14.2+ and uses minimal CPU/GPU resources via the Accelerate framework.")
            }



            Picker(selection: $hideNotchOption, label:
                    HStack {
                Label("Hide DynamicIsland Options", systemImage: "rectangle.topthird.inset.filled")
                customBadge(text: "Beta")
            }) {
                Text("Always hide in fullscreen").tag(HideNotchOption.always)
                Text("Hide only when NowPlaying app is in fullscreen").tag(HideNotchOption.nowPlayingOnly)
                Text("Never hide").tag(HideNotchOption.never)
            }
            .onChange(of: hideNotchOption) {
                Defaults[.enableFullscreenMediaDetection] = hideNotchOption != .never
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Label("Use colored spectrograms", systemImage: "paintpalette")
                }
                .settingsHighlight(id: highlightID("Use colored spectrograms"))
                Defaults.Toggle(key: .playerColorTinting) {
                    Label("Use album artwork colors for player controls", systemImage: "paintpalette")
                }
                Defaults.Toggle(key: .lightingEffect) {
                    Label("Enable blur effect behind album art", systemImage: "sparkles")
                }
                .settingsHighlight(id: highlightID("Enable blur effect behind album art"))
                HStack(spacing: 12) {
                    Label("Slider color", systemImage: "paintpalette").accessibilityHidden(true)
                    Spacer(minLength: 12)
                    Picker(selection: $sliderColor) {
                        ForEach(SliderColorEnum.allCases, id: \.self) { option in
                            Text(option.localizedName)
                        }
                    } label: {
                        Label("Slider color", systemImage: "paintpalette")
                    }
                        .labelsHidden()
                }
                .settingsHighlight(id: highlightID("Slider color"))
            } header: {
                Text("Media")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                MediaSettingsPreview()
            }
            .frame(maxWidth: 900)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
        .navigationTitle("Media")
    }


}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.enableReminderLiveActivity) var enableReminderLiveActivity
    @Default(.reminderPresentationStyle) var reminderPresentationStyle
    @Default(.reminderLeadTime) var reminderLeadTime
    @Default(.reminderSneakPeekDuration) var reminderSneakPeekDuration
    @Default(.enableLockScreenReminderWidget) var enableLockScreenReminderWidget
    @Default(.lockScreenReminderChipStyle) var lockScreenReminderChipStyle
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.showFullEventTitles) var showFullEventTitles
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent
    @Default(.lockScreenShowCalendarCountdown) private var lockScreenShowCalendarCountdown
    @Default(.lockScreenShowCalendarEvent) private var lockScreenShowCalendarEvent
    @Default(.lockScreenShowCalendarEventEntireDuration) private var lockScreenShowCalendarEventEntireDuration
    @Default(.lockScreenShowCalendarEventAfterStartWindow) private var lockScreenShowCalendarEventAfterStartWindow
    @Default(.lockScreenShowCalendarTimeRemaining) private var lockScreenShowCalendarTimeRemaining
    @Default(.lockScreenShowCalendarStartTimeAfterBegins) private var lockScreenShowCalendarStartTimeAfterBegins
    @Default(.lockScreenCalendarEventLookaheadWindow) private var lockScreenCalendarEventLookaheadWindow
    @Default(.lockScreenCalendarSelectionMode) private var lockScreenCalendarSelectionMode
    @Default(.lockScreenSelectedCalendarIDs) private var lockScreenSelectedCalendarIDs
    @Default(.lockScreenShowCalendarEventAfterStartEnabled) private var lockScreenShowCalendarEventAfterStartEnabled
    @Default(.enableThirdPartyCalendarApp) private var enableThirdPartyCalendarApp
    @Default(.selectedCalendarApp) private var selectedCalendarApp
    @Default(.fantasticalDefaultView) private var fantasticalDefaultView

    private func highlightID(_ title: String) -> String {
        SettingsTab.calendar.highlightID(for: title)
    }

    private enum CalendarLookaheadOption: String, CaseIterable, Identifiable {
        case mins15 = "15m"
        case mins30 = "30m"
        case hour1 = "1h"
        case hours3 = "3h"
        case hours6 = "6h"
        case hours12 = "12h"
        case restOfDay = "rest_of_day"
        case allTime = "all_time"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mins15: return String(localized: "15 mins")
            case .mins30: return String(localized: "30 mins")
            case .hour1: return String(localized: "1 hour")
            case .hours3: return String(localized: "3 hours")
            case .hours6: return String(localized: "6 hours")
            case .hours12: return String(localized: "12 hours")
            case .restOfDay: return String(localized: "Rest of the day")
            case .allTime: return String(localized: "All time")
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showCalendar) {
                    Label("Enable calendar", systemImage: "calendar")
                }
                .settingsHighlight(id: highlightID("Enable calendar"))
            }

            Section("Permissions") {
                calendarPermissionRow(.event, title: "Calendars", message: "Allows reading and managing calendar events.")
                calendarPermissionRow(.reminder, title: "Reminders", message: "Allows reading and completing reminders.")
            }
            Group {

                Section(header: Text("Event List")) {
                    Toggle("Hide completed reminders", systemImage: "calendar", isOn: $hideCompletedReminders)
                        .settingsHighlight(id: highlightID("Hide completed reminders"))
                    Toggle("Show full event titles", systemImage: "calendar", isOn: $showFullEventTitles)
                        .settingsHighlight(id: highlightID("Show full event titles"))
                    Toggle("Auto-scroll to next event", systemImage: "calendar", isOn: $autoScrollToNextEvent)
                        .settingsHighlight(id: highlightID("Auto-scroll to next event"))
                }

                .disabled(!showCalendar)

                Section(header: Text("All-Day Events")) {
                    Toggle("Hide all-day events", systemImage: "calendar", isOn: $hideAllDayEvents)
                        .settingsHighlight(id: highlightID("Hide all-day events"))
                        .disabled(!showCalendar)

                    Text("Turn this off to include all-day entries in the notch calendar and reminder live activity.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section(header: Text("Reminder Live Activity")) {
                    Defaults.Toggle(key: .enableReminderLiveActivity) {
                        Label("Enable reminder live activity", systemImage: "calendar")
                    }
                    .settingsHighlight(id: highlightID("Enable reminder live activity"))

                    SettingsSegmentedPicker(
                        "Countdown style",
                        selection: $reminderPresentationStyle,
                        items: Array(ReminderPresentationStyle.allCases)
                    ) { $0.displayName }
                    .disabled(!enableReminderLiveActivity)
                    .settingsHighlight(id: highlightID("Countdown style"))

                    HStack {
                        Text("Notify before")
                        SettingsSlider(
                            value: Binding(
                                get: { Double(reminderLeadTime) },
                                set: { reminderLeadTime = Int($0) }
                            ),
                            in: 1...60,
                            step: 1,
                            valueLabel: Text("\(reminderLeadTime) min")
                        )
                        .disabled(!enableReminderLiveActivity)
                    }

                    HStack {
                        Text("Sneak peek duration")
                        SettingsSlider(
                            value: $reminderSneakPeekDuration,
                            in: 3...20,
                            step: 1,
                            valueLabel: Text("\(Int(reminderSneakPeekDuration)) s")
                        )
                        .disabled(!enableReminderLiveActivity)
                    }
                }

                Section("Lock Screen Reminder Widget") {
                    LockScreenSettingsLink(title: "Show lock screen reminder")
                }

                Section("Calendar Widget") {
                    LockScreenSettingsLink(title: "Show next calendar event")
                }

                // MARK: - Third-party Calendar Integration
                Section {
                    Defaults.Toggle(key: .enableThirdPartyCalendarApp) {
                        HStack {
                            Image(systemName: "ellipsis.calendar")
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)
                            Label("Enable third-party calendar app launch", systemImage: "calendar")
                        }
                    }
                    .settingsHighlight(id: highlightID("Enable third-party calendar app launch"))
                    
                    Group {
                        HStack(spacing: 12) {
                            Label("Calendar App", systemImage: "calendar").accessibilityHidden(true)
                            Spacer(minLength: 12)
                            Picker(selection: $selectedCalendarApp) {
                                ForEach(ThirdPartyCalendarApp.allCases) { app in
                                    HStack {
                                        AppIconImage(
                                            bundleIdentifiers: app.bundleIdentifiers,
                                            symbolFallback: app.fallbackIconName,
                                            symbolColor: app.fallbackIconColor
                                        )
                                        Text(app.displayName)
                                    }
                                    .tag(app)
                                }
                            } label: {
                                Label("Calendar App", systemImage: "calendar")
                            }
                                .labelsHidden()
                        }
                        .settingsHighlight(id: highlightID("Calendar App"))
                        
                        if selectedCalendarApp == .fantastical {
                            HStack(spacing: 12) {
                                Label("Default View", systemImage: "slider.horizontal.3").accessibilityHidden(true)
                                Spacer(minLength: 12)
                                Picker(selection: $fantasticalDefaultView) {
                                    ForEach(FantasticalViewStyle.allCases, id: \.self) { style in
                                        Text(style.displayName).tag(style)
                                    }
                                } label: {
                                    Label("Default View", systemImage: "slider.horizontal.3")
                                }
                                    .labelsHidden()
                            }
                            .settingsHighlight(id: highlightID("Fantastical Default View"))
                        }
                    }
                    .disabled(!enableThirdPartyCalendarApp)
                } header: {
                    Text("Third-party Calendar Integration")
                } footer: {
                    Text("When enabled, clicking on calendar events will open the selected third-party calendar app instead of Apple Calendar.")
                }

                Section(header: Text("Select Calendars")) {
                    let grouped = Dictionary(grouping: calendarManager.allCalendars, by: \.accountName)
                    let sortedAccounts = grouped.keys.sorted()

                    ForEach(sortedAccounts, id: \.self) { account in
                        let accountCalendars = grouped[account] ?? []
                        let allAccountSelected = accountCalendars.allSatisfy { calendarManager.getCalendarSelected($0) }

                        Section(header: HStack {
                            Text(account)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { allAccountSelected },
                                set: { isSelected in
                                    Task {
                                        await calendarManager.setCalendarsSelected(accountCalendars, isSelected: isSelected)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .controlSize(.mini)
                            .disabled(!showCalendar)
                        }) {
                            ForEach(accountCalendars, id: \.id) { calendar in
                                Toggle(isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(calendar, isSelected: isSelected)
                                        }
                                    }
                                )) {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(calendar.color))
                                            .frame(width: 8, height: 8)
                                        Text(calendar.title)
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .disabled(!showCalendar)
                            }
                        }
                    }
                }
            }
        }
        .task { await calendarManager.reloadCalendarAndReminderLists() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await calendarManager.reloadCalendarAndReminderLists() }
        }
        .navigationTitle("Calendar")
    }

    private func calendarPermissionRow(_ type: EKEntityType, title: String, message: String) -> some View {
        let status = type == .event ? calendarManager.calendarAuthorizationStatus : calendarManager.reminderAuthorizationStatus
        return SettingsPermissionRow(title: title, message: message, state: .init(calendar: status), request: {
            Task { await calendarManager.requestAuthorization(for: type) }
        }, openSettings: {
            openPermissionSettings(type == .event ? "Calendars" : "Reminders")
        })
    }
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    @ObservedObject private var updates = EaveUpdater.shared
    @State private var showDevNotice = false
    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Label("Product name", systemImage: "app")
                        Spacer()
                        Text("Eave")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        HStack {
                            Label("Version", systemImage: "info.circle")
                            Spacer()

                            // Channel badge
                            Text(UpdateChannel.buildChannel.displayName)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(UpdateChannel.buildChannel.badgeColor).opacity(0.2))
                                .foregroundStyle(Color(UpdateChannel.buildChannel.badgeColor))
                                .clipShape(Capsule())

                            if showBuildNumber {
                                Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                    .foregroundStyle(.secondary)
                            }
                            Text(Bundle.main.releaseVersionNumber ?? "—")
                                .foregroundStyle(.secondary)
                        }
                        .onTapGesture {
                            withAnimation {
                                showBuildNumber.toggle()
                            }
                        }
                        Button("Check for Updates…") {
                            if UpdateChannel.buildChannel == .release {
                                updates.checkForUpdates()
                            } else {
                                showDevNotice = true
                            }
                        }
                        .disabled(updates.updater != nil && !updates.canCheckForUpdates)
                    }
                } header: {
                    Text("Version info")
                }

                if UpdateChannel.buildChannel == .release {
                    Section {
                        Toggle("Automatically check for updates", systemImage: "arrow.triangle.2.circlepath", isOn: $updates.automaticallyChecksForUpdates)
                    }
                }

            }
        }
        .navigationTitle("About")
        .alert("Release updates only", isPresented: $showDevNotice) {
            Button("Download Release") {
                NSWorkspace.shared.open(URL(string: "https://github.com/k1ngr4m/eave/releases/latest")!)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Development builds do not install updates. Download a release build to enable automatic updates.")
        }
    }
}

private extension DevicesSettingsView {
    enum BluetoothHUDIconStyle: String {
        case symbol
        case threeD

        var title: String {
            switch self {
            case .symbol:
                return String(localized: "Symbol")
            case .threeD:
                return String(localized: "3D")
            }
        }
    }

    struct BluetoothHUDIconStyleCard: View {
        let style: BluetoothHUDIconStyle
        let isSelected: Bool
        let action: () -> Void

        @State private var isHovering = false

        var body: some View {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
                        )

                    preview
                }
                .frame(width: 90, height: 64)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovering = hovering
                    }
                }

                Text(style.title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .contentShape(Rectangle())
            .onTapGesture { action() }
        }

        private var preview: some View {
            Group {
                switch style {
                case .symbol:
                    Image(systemName: BluetoothAudioDeviceType.airpods.sfSymbol)
                        .font(.system(size: 24, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                case .threeD:
                    if let url = BluetoothAudioDeviceType.airpods.inlineHUDAnimationURL {
                        SettingsLoopingVideoIcon(url: url, size: CGSize(width: 28, height: 28))
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: BluetoothAudioDeviceType.airpods.sfSymbol)
                            .font(.system(size: 24, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }

        private var backgroundColor: Color {
            if isSelected { return Color.accentColor.opacity(0.12) }
            if isHovering { return Color.primary.opacity(0.05) }
            return Color(nsColor: .controlBackgroundColor)
        }

        private var borderColor: Color {
            if isSelected { return Color.accentColor }
            if isHovering { return Color.primary.opacity(0.1) }
            return Color.clear
        }
    }
}

private struct SettingsLoopingVideoIcon: NSViewRepresentable {
    let url: URL
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true

        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        layer.frame = view.bounds
        view.layer?.addSublayer(layer)
        context.coordinator.attach(layer: layer, url: url)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var controller: SettingsLoopingPlayerController?

        func attach(layer: AVPlayerLayer, url: URL) {
            controller = SettingsLoopingPlayerController(url: url, autoPlay: true)
            layer.player = controller?.player
        }
    }
}

private final class SettingsLoopingPlayerController {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?

    init(url: URL, autoPlay: Bool = true) {
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: item)
        if autoPlay {
            player.play()
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    deinit {
        player.pause()
        looper = nil
    }
}

struct Shelf: View {
    @Default(.dynamicShelf) private var shelfEnabled
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.expandedDragDetection) var expandedDragDetection
    @Default(.copyOnDrag) var copyOnDrag
    @Default(.autoRemoveShelfItems) var autoRemoveShelfItems
    @StateObject private var quickShareService = QuickShareService.shared
    @ObservedObject private var fullDiskAccessPermission = FullDiskAccessPermissionStore.shared
    @ObservedObject private var shelfFolderAccessPermission = ShelfFolderAccessPermissionStore.shared
    @AppStorage("shelfFolderPermissionRequested") private var folderPermissionRequested = false

    private var hasDocumentsAndDownloadsAccess: Bool {
        shelfFolderAccessPermission.hasDocumentsAndDownloadsAccess
    }

    private var canEnableShelf: Bool {
        fullDiskAccessPermission.isAuthorized || hasDocumentsAndDownloadsAccess
    }

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }

    init() {
        QuickShareService.shared.ensureDiscovered()
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.shelf.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .dynamicShelf) {
                    Label("Enable shelf", systemImage: "power")
                }
                .disabled(!canEnableShelf)
                .settingsHighlight(id: highlightID("Enable shelf"))
            }

            Section("Permissions") {
                SettingsPermissionRow(title: "Documents and Downloads", message: "Allows Shelf to read these folders. Not required when Full Disk Access is granted.",
                                      state: canEnableShelf ? .granted : (folderPermissionRequested ? .denied : .notDetermined),
                                      request: {
                    folderPermissionRequested = true
                    shelfFolderAccessPermission.requestAccessPrompt()
                },
                                      openSettings: { shelfFolderAccessPermission.openSystemSettings() })
                SettingsPermissionRow(title: "Full Disk Access", message: "Optional. Allows Shelf to read files outside Documents and Downloads.",
                                      state: fullDiskAccessPermission.isAuthorized ? .granted : .denied,
                                      openSettings: { fullDiskAccessPermission.openSystemSettings() })
            }

            Section {

                Defaults.Toggle(key: .expandedDragDetection) {
                    Label("Expand drag detection area", systemImage: "slider.horizontal.3")
                }
                .disabled(!shelfEnabled)
                .settingsHighlight(id: highlightID("Expand drag detection area"))

                Defaults.Toggle(key: .copyOnDrag) {
                    Label("Copy items on drag", systemImage: "doc.on.clipboard")
                }
                .disabled(!shelfEnabled)
                .settingsHighlight(id: highlightID("Copy items on drag"))

                Defaults.Toggle(key: .allowMoveOnDrag) {
                    Label("Allow moving files when dragging out", systemImage: "slider.horizontal.3")
                }
                .disabled(!shelfEnabled)
                .settingsHighlight(id: highlightID("Allow moving files when dragging out"))

                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Label("Remove from shelf after dragging", systemImage: "slider.horizontal.3")
                }
                .disabled(!shelfEnabled)
                .settingsHighlight(id: highlightID("Remove from shelf after dragging"))
            } header: {
                HStack {
                    Text("General")
                }
            }

            Section {
                HStack(spacing: 12) {
                    Label("Quick Share Service", systemImage: "slider.horizontal.3").accessibilityHidden(true)
                    Spacer(minLength: 12)
                    Picker(selection: $quickShareProvider) {
                        ForEach(quickShareService.availableProviders, id: \.id) { provider in
                            HStack {
                                QuickShareProviderIconImage(provider: provider, size: 16)
                                Text(provider.id)
                            }
                            .tag(provider.id)
                        }
                    } label: {
                        Label("Quick Share Service", systemImage: "slider.horizontal.3")
                    }
                        .labelsHidden()
                }
                .pickerStyle(.menu)
                .settingsHighlight(id: highlightID("Quick Share Service"))

                if let selectedProvider {
                    HStack {
                        QuickShareProviderIconImage(provider: selectedProvider, size: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Currently selected: \(selectedProvider.id)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Files dropped on the shelf will be shared via this service")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text("Quick Share")
                }
            } footer: {
                Text("Choose which service to use when sharing files from the shelf. Drag files onto the shelf or click the shelf button to pick files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if quickShareProvider == "LocalSend" {
                LocalSendSettingsSection(highlightID: highlightID)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shelf")
        .onAppear {
            fullDiskAccessPermission.refreshStatus()
            shelfFolderAccessPermission.refreshStatus()
        }
    }
}

// MARK: - LocalSend Settings Section

private struct LocalSendSettingsSection: View {
    let highlightID: (String) -> String
    
    @Default(.localSendDevicePickerGlassMode) private var glassMode
    @Default(.localSendDevicePickerLiquidGlassVariant) private var liquidGlassVariant
    
    var body: some View {
        Section {
            HStack(spacing: 12) {
                Label("Device Picker Style", systemImage: "circle.lefthalf.filled").accessibilityHidden(true)
                Spacer(minLength: 12)
                Picker(selection: $glassMode) {
                    ForEach(LockScreenGlassCustomizationMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                } label: {
                    Label("Device Picker Style", systemImage: "circle.lefthalf.filled")
                }
                    .labelsHidden()
            }
            .pickerStyle(.menu)
            
            if glassMode == .customLiquid {
                HStack(spacing: 12) {
                    Label("Liquid Glass Variant", systemImage: "circle.lefthalf.filled").accessibilityHidden(true)
                    Spacer(minLength: 12)
                    Picker(selection: $liquidGlassVariant) {
                        ForEach(LiquidGlassVariant.allCases) { variant in
                            Text("Variant \(variant.rawValue)").tag(variant)
                        }
                    } label: {
                        Label("Liquid Glass Variant", systemImage: "circle.lefthalf.filled")
                    }
                        .labelsHidden()
                }
                .pickerStyle(.menu)
            }
        } header: {
            Text("LocalSend Device Picker")
        } footer: {
            Text("Customize the appearance of the LocalSend device selection popup that appears when you drop files.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct LiveActivitiesSettings: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @ObservedObject var privacyManager = PrivacyIndicatorManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @ObservedObject private var fullDiskAccessPermission = FullDiskAccessPermissionStore.shared

    @Default(.enableScreenRecordingDetection) var enableScreenRecordingDetection
    @Default(.showRecordingIndicator) var showRecordingIndicator
    @Default(.recordingHoverStyle) var recordingHoverStyle
    @Default(.recordingControlMode) var recordingControlMode
    @Default(.enableDoNotDisturbDetection) var enableDoNotDisturbDetection
    @Default(.focusIndicatorNonPersistent) var focusIndicatorNonPersistent
    @Default(.capsLockIndicatorTintMode) var capsLockTintMode

    private func highlightID(_ title: String) -> String {
        SettingsTab.liveActivities.highlightID(for: title)
    }

    var body: some View {
        Form {
            BatteryHUDSettingsSections()

            DownloadSettingsSection()

            Section {
                Defaults.Toggle(key: .enableScreenRecordingDetection) {
                    Label("Enable screen recording detection", systemImage: "display")
                }
                .settingsHighlight(id: highlightID("Enable screen recording detection"))

                Defaults.Toggle(key: .showRecordingIndicator) {
                    Label("Show recording indicator", systemImage: "power")
                }
                .disabled(!enableScreenRecordingDetection)
                .settingsHighlight(id: highlightID("Show recording indicator"))

                VStack(alignment: .leading, spacing: 8) {
                    SettingsSegmentedPicker(
                        "Recording controls",
                        selection: $recordingControlMode,
                        items: Array(RecordingControlMode.allCases)
                    ) { $0.title }

                    Text("Indicator only keeps the recording live activity passive. With stop button enables native recording controls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!enableScreenRecordingDetection)
                .settingsHighlight(id: highlightID("Recording Controls"))

                VStack(alignment: .leading, spacing: 8) {
                    SettingsSegmentedPicker(
                        "Recording hover style",
                        selection: $recordingHoverStyle,
                        items: Array(RecordingHoverStyle.allCases)
                    ) { $0.title }

                    Text("Default uses the expanded recording HUD. Inline keeps the stop control inside the notch height.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!enableScreenRecordingDetection || !showRecordingIndicator || recordingControlMode != .withStopButton)
                .settingsHighlight(id: highlightID("Recording Hover Style"))

                if recordingManager.isMonitoring {
                    HStack {
                        Text("Detection Status")
                        Spacer()
                        if recordingManager.isRecording {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("Recording Detected")
                                    .foregroundColor(.red)
                            }
                        } else {
                            Text("Active - No Recording")
                                .foregroundColor(.green)
                        }
                    }
                }
            } header: {
                Text("Screen Recording")
            } footer: {
                Text("Uses event-driven private API for real-time screen recording detection")
            }

            Section {
                SettingsPermissionRow(title: "Full Disk Access", message: "Optional. Enables custom Focus icons, colors, and labels. Standard Focus detection works without it.",
                                      state: fullDiskAccessPermission.isAuthorized ? .granted : .denied,
                                      openSettings: { fullDiskAccessPermission.openSystemSettings() })

                Defaults.Toggle(key: .enableDoNotDisturbDetection) {
                    Label("Enable Focus detection", systemImage: "power")
                }
                .settingsHighlight(id: highlightID("Enable Focus detection"))

                Defaults.Toggle(key: .showDoNotDisturbIndicator) {
                    Label("Show Focus indicator", systemImage: "power")
                }
                .disabled(!enableDoNotDisturbDetection)
                .settingsHighlight(id: highlightID("Show Focus indicator"))

                Defaults.Toggle(key: .showDoNotDisturbLabel) {
                    Label("Show Focus label", systemImage: "power")
                }
                .disabled(!enableDoNotDisturbDetection || focusIndicatorNonPersistent)
                .help(focusIndicatorNonPersistent ? "Labels are forced to compact on/off text while brief toast mode is enabled." : "Show the active Focus name inside the indicator.")
                .settingsHighlight(id: highlightID("Show Focus label"))

                Defaults.Toggle(key: .focusIndicatorNonPersistent) {
                    Label("Show Focus as brief toast", systemImage: "power")
                }
                .disabled(!enableDoNotDisturbDetection)
                .settingsHighlight(id: highlightID("Show Focus as brief toast"))
                .help("When enabled, Focus appears briefly (on/off) and then collapses instead of staying visible.")

                if doNotDisturbManager.isMonitoring {
                    HStack {
                        Text("Focus Status")
                        Spacer()
                        if doNotDisturbManager.isDoNotDisturbActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.purple)
                                    .frame(width: 8, height: 8)
                                Text(doNotDisturbManager.currentFocusModeName.isEmpty ? String(localized: "Focus Enabled") : doNotDisturbManager.currentFocusModeName)
                                    .foregroundColor(.purple)
                            }
                        } else {
                            Text("Active - No Focus")
                                .foregroundColor(.green)
                        }
                    }
                } else {
                    HStack {
                        Text("Focus Status")
                        Spacer()
                        Text("Disabled")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Do Not Disturb")
            } footer: {
                Text("Listens for Focus session changes via distributed notifications")
            }

            Section {
                Defaults.Toggle(key: .enableCapsLockIndicator) {
                    Label("Show Caps Lock indicator", systemImage: "lock")
                }
                .settingsHighlight(id: highlightID("Show Caps Lock indicator"))

                Defaults.Toggle(key: .showCapsLockLabel) {
                    Label("Show Caps Lock label", systemImage: "lock")
                }
                .disabled(!Defaults[.enableCapsLockIndicator])
                .settingsHighlight(id: highlightID("Show Caps Lock label"))

                SettingsSegmentedPicker(
                    "Caps Lock color",
                    selection: $capsLockTintMode,
                    items: Array(CapsLockIndicatorTintMode.allCases)
                ) { $0.displayName }
                .disabled(!Defaults[.enableCapsLockIndicator])
                .settingsHighlight(id: highlightID("Caps Lock color"))
            } header: {
                Text("Caps Lock Indicator")
            } footer: {
                Text("Adds a notch HUD when Caps Lock is enabled, with optional label and tint controls.")
            }

            Section {
                Defaults.Toggle(key: .enableCameraDetection) {
                    Label("Enable camera detection", systemImage: "camera")
                }
                .settingsHighlight(id: highlightID("Enable camera detection"))
                Defaults.Toggle(key: .enableMicrophoneDetection) {
                    Label("Enable microphone detection", systemImage: "power")
                }
                .settingsHighlight(id: highlightID("Enable microphone detection"))

                if privacyManager.isMonitoring {
                    HStack {
                        Text("Camera Status")
                        Spacer()
                        if privacyManager.cameraActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Camera Active")
                                    .foregroundColor(.green)
                            }
                        } else {
                            Text("Inactive")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Microphone Status")
                        Spacer()
                        if privacyManager.microphoneActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.yellow)
                                    .frame(width: 8, height: 8)
                                Text("Microphone Active")
                                    .foregroundColor(.yellow)
                            }
                        } else {
                            Text("Inactive")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Privacy Indicators")
            } footer: {
                Text("Shows green camera icon and yellow microphone icon when in use. Uses event-driven CoreAudio and CoreMediaIO APIs.")
            }

            Section {
                Toggle(
                    "Enable music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                .settingsHighlight(id: highlightID("Enable music live activity"))
            } header: {
                Text("Media Live Activity")
            } footer: {
                Text("Use the Media tab to configure sneak peek, lyrics, and floating media controls.")
            }

            Section {
                Defaults.Toggle(key: .enableReminderLiveActivity) {
                    Label("Enable reminder live activity", systemImage: "calendar")
                }
                .settingsHighlight(id: highlightID("Enable reminder live activity"))
            } header: {
                Text("Reminder Live Activity")
            } footer: {
                Text("Configure countdown style and lock screen widgets in the Calendar tab.")
            }
        }
        .navigationTitle("Live Activities")
        .onAppear {
            fullDiskAccessPermission.refreshStatus()
        }
    }
}

struct Appearance: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.reopenTab) private var reopenTab
    @ObservedObject var webcamManager = WebcamManager.shared
    @Default(.headerTabSpacing) private var headerTabSpacing
    @Default(.mirrorShape) var mirrorShape
    @Default(.selectedCameraID) var selectedCameraID
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.customVisualizers) var customVisualizers
    @Default(.selectedVisualizer) var selectedVisualizer
    @Default(.customAppIcons) private var customAppIcons
    @Default(.selectedAppIconID) private var selectedAppIconID
    @Default(.openNotchWidth) var openNotchWidth
    @Default(.closedNotchWidth) var closedNotchWidth
    @Default(.customizePhysicalNotchWidth) var customizePhysicalNotchWidth
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.lockScreenGlassCustomizationMode) private var lockScreenGlassCustomizationMode
    @Default(.lockScreenGlassStyle) private var lockScreenGlassStyle
    @Default(.lockScreenTimerGlassStyle) private var lockScreenTimerGlassStyle
    @Default(.lockScreenTimerGlassCustomizationMode) private var lockScreenTimerGlassCustomizationMode
    @Default(.lockScreenTimerWidgetUsesBlur) private var timerGlassModeIsGlass
    @Default(.externalDisplayStyle) private var externalDisplayStyle
    @State private var selectedListVisualizer: CustomVisualizer? = nil

    @State private var isIconImporterPresented = false
    @State private var isIconDropTarget = false
    @State private var iconImportError: String?

    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var speed: CGFloat = 1.0

    /// Whether the main screen has a physical notch.
    private var mainScreenHasPhysicalNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }

    private var notchWidthRange: ClosedRange<Double> {
        let minW = Double(currentRecommendedMinimumNotchWidth())
        let maxW = min(900, Double(maxAllowedNotchWidth()))
        return minW...max(minW, maxW)
    }
    private var defaultOpenNotchWidth: CGFloat {
        currentRecommendedMinimumNotchWidth()
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.appearance.highlightID(for: title)
    }



    private var timerSurfaceBinding: Binding<LockScreenTimerSurfaceMode> {
        Binding(
            get: { timerGlassModeIsGlass ? .glass : .classic },
            set: { mode in timerGlassModeIsGlass = (mode == .glass) }
        )
    }

    var body: some View {
        Form {
            Section {
                NotchAppearanceSettings()
                .settingsHighlight(id: highlightID("Notch appearance"))
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Label("Show settings icon in the notch", systemImage: "power")
                }
                .settingsHighlight(id: highlightID("Show settings icon in the notch"))
                VStack(alignment: .leading, spacing: 8) {
                    Label("Top tab spacing", systemImage: "arrow.left.and.right")
                    SettingsSlider(value: $headerTabSpacing, in: 4...32, step: 1, valueLabel: Text(verbatim: "\(Int(headerTabSpacing)) pt"))
                        .accessibilityLabel(Text("Top tab spacing"))
                    Button("Reset") { Defaults.reset(.headerTabSpacing) }
                        .disabled(headerTabSpacing == 24)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("Spacing automatically tightens when needed to keep tabs clear of the notch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .settingsHighlight(id: highlightID("Top tab spacing"))
                Defaults.Toggle(key: .enableShadow) {
                    Label("Enable window shadow", systemImage: "power")
                }
                .settingsHighlight(id: highlightID("Enable window shadow"))
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Label("Scale corner radius with notch size", systemImage: "arrow.left.and.right")
                }
                .settingsHighlight(id: highlightID("Scale corner radius with notch size"))
                Defaults.Toggle(key: .useModernCloseAnimation) {
                    Label("Use simpler close animation", systemImage: "sparkles")
                }
                .settingsHighlight(id: highlightID("Use simpler close animation"))
            } header: {
                Text("General")
            }

            // Show display style picker only on non-notch Macs (main screen has no physical notch)
            if !mainScreenHasPhysicalNotch {
                Section {
                    HStack(spacing: 12) {
                        Label("Main screen style", systemImage: "display").accessibilityHidden(true)
                        Spacer(minLength: 12)
                        Picker(selection: $externalDisplayStyle) {
                            ForEach(ExternalDisplayStyle.allCases) { style in
                                Text(style.localizedName)
                                    .tag(style)
                            }
                        } label: {
                            Label("Main screen style", systemImage: "display")
                        }
                            .labelsHidden()
                    }
                    .onChange(of: externalDisplayStyle) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                    .settingsHighlight(id: highlightID("Main screen style"))
                    Text(externalDisplayStyle.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Display Style")
                }
            }

            notchWidthControls()
            notchHeightControls()
            notchBehaviorControls()


            Section {
                Toggle(
                    "Use music visualizer spectrogram",
                    isOn: $useMusicVisualizer.animation()
                )
                .disabled(true)
                if !useMusicVisualizer {
                    if customVisualizers.count > 0 {
                        Picker(
                            "Selected animation",
                            selection: $selectedVisualizer
                        ) {
                            ForEach(
                                customVisualizers,
                                id: \.self
                            ) { visualizer in
                                Text(visualizer.name)
                                    .tag(visualizer)
                            }
                        }
                    } else {
                        HStack {
                            Text("Selected animation")
                            Spacer()
                            Text("No custom animation available")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Custom music live activity animation")
                    customBadge(text: "Coming soon")
                }
            }

            Section {
                List {
                    ForEach(customVisualizers, id: \.self) { visualizer in
                        HStack {
                            LottieView(state: LUStateData(type: .loadedFrom(visualizer.url), speed: visualizer.speed, loopMode: .loop))
                                .frame(width: 30, height: 30, alignment: .center)
                            Text(visualizer.name)
                            Spacer(minLength: 0)
                            if selectedVisualizer == visualizer {
                                Text("selected")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 2)
                        .background(
                            selectedListVisualizer != nil ? selectedListVisualizer == visualizer ? Color.accentColor : Color.clear : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedListVisualizer == visualizer {
                                selectedListVisualizer = nil
                                return
                            }
                            selectedListVisualizer = visualizer
                        }
                    }
                }
                .safeAreaPadding(
                    EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
                )
                .frame(minHeight: 120)
                .actionBar {
                    HStack(spacing: 5) {
                        Button {
                            name = ""
                            url = ""
                            speed = 1.0
                            isPresented.toggle()
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        Divider()
                        Button {
                            if selectedListVisualizer != nil {
                                let visualizer = selectedListVisualizer!
                                selectedListVisualizer = nil
                                customVisualizers.remove(at: customVisualizers.firstIndex(of: visualizer)!)
                                if visualizer == selectedVisualizer && customVisualizers.count > 0 {
                                    selectedVisualizer = customVisualizers[0]
                                }
                            }
                        } label: {
                            Image(systemName: "minus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                    }
                }
                .controlSize(.small)
                .buttonStyle(PlainButtonStyle())
                .overlay {
                    if customVisualizers.isEmpty {
                        Text("No custom visualizer")
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
                .sheet(isPresented: $isPresented) {
                    VStack(alignment: .leading) {
                        Text("Add new visualizer")
                            .font(.largeTitle.bold())
                            .padding(.vertical)
                        TextField("Name", text: $name)
                        TextField("Lottie JSON URL", text: $url)
                        HStack {
                            Text("Speed")
                            Spacer(minLength: 80)
                            SettingsSlider(value: $speed, in: 0...2, step: 0.1, valueLabel: Text("\(speed, specifier: "%.1f")s"))
                        }
                        .padding(.vertical)
                        HStack {
                            Button {
                                isPresented.toggle()
                            } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }

                            Button {
                                let visualizer: CustomVisualizer = .init(
                                    UUID: UUID(),
                                    name: name,
                                    url: URL(string: url)!,
                                    speed: speed
                                )

                                if !customVisualizers.contains(visualizer) {
                                    customVisualizers.append(visualizer)
                                }

                                isPresented.toggle()
                            } label: {
                                Text("Add")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .controlSize(.extraLarge)
                    .padding()
                }
            } header: {
                HStack(spacing: 0) {
                    Text("Custom vizualizers (Lottie)")
                    if !Defaults[.customVisualizers].isEmpty {
                        Text(" – \(Defaults[.customVisualizers].count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                CameraSettingsPermissionRow()
                Defaults.Toggle(key: .showMirror) {
                    Label("Enable dynamic mirror", systemImage: "camera")
                }
                .disabled(!checkVideoInput())
                .settingsHighlight(id: highlightID("Enable dynamic mirror"))
                HStack(spacing: 12) {
                    Label("Mirror shape", systemImage: "camera").accessibilityHidden(true)
                    Spacer(minLength: 12)
                    Picker(selection: $mirrorShape) {
                        Text("Circle")
                            .tag(MirrorShapeEnum.circle)
                        Text("Square")
                            .tag(MirrorShapeEnum.rectangle)
                    } label: {
                        Label("Mirror shape", systemImage: "camera")
                    }
                        .labelsHidden()
                }
                .settingsHighlight(id: highlightID("Mirror shape"))
                
                if webcamManager.cameraAvailable {
                    HStack(spacing: 12) {
                        Label("Mirror Camera", systemImage: "camera").accessibilityHidden(true)
                        Spacer(minLength: 12)
                        Picker(selection: Binding(
                            get: {
                                webcamManager.availableCameras.contains { $0.uniqueID == selectedCameraID }
                                    ? selectedCameraID : ""
                            },
                            set: { selectedCameraID = $0 }
                        )) {
                            Text("Auto Select").tag("")
                            ForEach(webcamManager.availableCameras, id: \.uniqueID) { device in
                                Text(device.localizedName)
                                    .tag(device.uniqueID)
                            }
                        } label: {
                            Label("Mirror Camera", systemImage: "camera")
                        }
                            .labelsHidden()
                    }
                    .onChange(of: selectedCameraID) { _, _ in
                        if Defaults[.showMirror] {
                            webcamManager.stopSession()
                            webcamManager.startSession()
                        }
                    }
                    .settingsHighlight(id: highlightID("Mirror Camera"))
                }
                Defaults.Toggle(key: .showNotHumanFace) {
                    Label("Enable idle animation", systemImage: "sparkles")
                }
                .settingsHighlight(id: highlightID("Enable idle animation"))
            } header: {
                HStack {
                    Text("Additional features")
                }
            }

            // MARK: - Custom Idle Animations Section
            IdleAnimationsSettingsSection()

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        appIconCard(
                            title: "Default",
                            image: defaultAppIconImage(),
                            isSelected: selectedAppIconID == nil
                        ) {
                            selectedAppIconID = nil
                            applySelectedAppIcon()
                        }

                        ForEach(customAppIcons) { icon in
                            appIconCard(
                                title: icon.name,
                                image: customIconImage(for: icon),
                                isSelected: selectedAppIconID == icon.id.uuidString
                            ) {
                                selectedAppIconID = icon.id.uuidString
                                applySelectedAppIcon()
                            }
                            .contextMenu {
                                Button("Remove") {
                                    removeCustomIcon(icon)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(isIconDropTarget ? 0.18 : 0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(isIconDropTarget ? 0.8 : 0), lineWidth: 2)
                    )
                    .onDrop(of: [UTType.fileURL], isTargeted: $isIconDropTarget) { providers in
                        handleIconDrop(providers)
                    }

                    HStack(spacing: 8) {
                        Button("Add icon") {
                            iconImportError = nil
                            isIconImporterPresented = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Remove selected") {
                            if let id = selectedAppIconID,
                               let icon = customAppIcons.first(where: { $0.id.uuidString == id }) {
                                removeCustomIcon(icon)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedAppIconID == nil)
                    }

                    if let iconImportError {
                        Text(iconImportError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Drop a PNG, JPEG, TIFF, or ICNS file to add it to your icon library.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsHighlight(id: highlightID("App icon"))
            } header: {
                HStack {
                    Label("App icon", systemImage: "slider.horizontal.3")
                }
            }
        }
        .onAppear(perform: enforceLockScreenGlassConsistency)
        .onChange(of: lockScreenGlassStyle) { _, _ in enforceLockScreenGlassConsistency() }
        .onChange(of: lockScreenGlassCustomizationMode) { _, _ in enforceLockScreenGlassConsistency() }
        .fileImporter(
            isPresented: $isIconImporterPresented,
            allowedContentTypes: [.png, .jpeg, .tiff, .icns, .image]
        ) { result in
            switch result {
            case .success(let url):
                importCustomIcon(from: url)
            case .failure:
                iconImportError = String(localized: "Icon import was canceled or failed.")
            }
        }
        .navigationTitle("Appearance")
    }

    private func defaultAppIconImage() -> NSImage? {
        let fallbackName = Bundle.main.iconFileName ?? "AppIcon"
        return NSImage(named: fallbackName)
    }

    private func customIconImage(for icon: CustomAppIcon) -> NSImage? {
        NSImage(contentsOf: icon.fileURL)
    }

    private func appIconCard(title: String, image: NSImage?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )

                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isSelected ? Color.accentColor : .clear)
                    )
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func handleIconDrop(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.first { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard let provider = matching else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let directURL = item as? URL {
                url = directURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }
            guard let url else { return }
            Task { @MainActor in importCustomIcon(from: url) }
        }
        return true
    }

    private func importCustomIcon(from url: URL) {
        guard NSImage(contentsOf: url) != nil else {
            iconImportError = String(localized: "That file could not be loaded as an image.")
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let id = UUID()
        let fileName = "custom-icon-\(id.uuidString).\(ext)"
        let destination = CustomAppIcon.iconDirectory.appendingPathComponent(fileName)

        do {
            let data = try Data(contentsOf: url)
            try data.write(to: destination, options: [.atomic])
        } catch {
            iconImportError = String(localized: "Unable to save the icon file.")
            return
        }

        let newIcon = CustomAppIcon(id: id, name: name.isEmpty ? "Custom Icon" : name, fileName: fileName)
        if !customAppIcons.contains(newIcon) {
            customAppIcons.append(newIcon)
        }
        selectedAppIconID = newIcon.id.uuidString
        applySelectedAppIcon()
        iconImportError = nil
    }

    private func removeCustomIcon(_ icon: CustomAppIcon) {
        if let index = customAppIcons.firstIndex(of: icon) {
            customAppIcons.remove(at: index)
        }
        if FileManager.default.fileExists(atPath: icon.fileURL.path) {
            try? FileManager.default.removeItem(at: icon.fileURL)
        }
        if selectedAppIconID == icon.id.uuidString {
            selectedAppIconID = nil
            applySelectedAppIcon()
        }
    }

    func checkVideoInput() -> Bool {
        if let _ = AVCaptureDevice.default(for: .video) {
            return true
        }

        return false
    }

    @ViewBuilder
    private func notchHeightControls() -> some View {
        Section {
            HStack(spacing: 12) {
                Label("Notch display height", systemImage: "arrow.left.and.right")
                    .accessibilityHidden(true)
                Spacer(minLength: 12)
                Picker(selection: $notchHeightMode) {
                    Text("Match real notch size")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                } label: {
                    Label("Notch display height", systemImage: "arrow.left.and.right")
                }
                .labelsHidden()
            }
            .onChange(of: notchHeightMode) {
                switch notchHeightMode {
                case .matchRealNotchSize:
                    notchHeight = 38
                case .matchMenuBar:
                    notchHeight = 44
                case .custom:
                    notchHeight = 38
                }
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
            .settingsHighlight(id: highlightID("Notch display height"))
            if notchHeightMode == .custom {
                SettingsSlider(value: $notchHeight, in: 15...45, step: 1, valueLabel: Text("\(Int(notchHeight))")) {
                    Text("Custom notch size")
                }
                .onChange(of: notchHeight) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
            HStack(spacing: 12) {
                Label("Non-notch display height", systemImage: "arrow.left.and.right").accessibilityHidden(true)
                Spacer(minLength: 12)
                Picker(selection: $nonNotchHeightMode) {
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Match real notch size")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                } label: {
                    Label("Non-notch display height", systemImage: "arrow.left.and.right")
                }
                    .labelsHidden()
            }
            .onChange(of: nonNotchHeightMode) {
                switch nonNotchHeightMode {
                case .matchMenuBar:
                    nonNotchHeight = 24
                case .matchRealNotchSize:
                    nonNotchHeight = 32
                case .custom:
                    nonNotchHeight = 32
                }
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
            if nonNotchHeightMode == .custom {
                SettingsSlider(value: $nonNotchHeight, in: 0...40, step: 1, valueLabel: Text("\(Int(nonNotchHeight))")) {
                    Text("Custom notch size")
                }
                .onChange(of: nonNotchHeight) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text("Notch Height")
        }
    }

    @ViewBuilder
    private func notchBehaviorControls() -> some View {
        Section {
            Defaults.Toggle(key: .extendHoverArea) {
                Label("Extend hover area", systemImage: "hand.draw")
            }
            .settingsHighlight(id: highlightID("Extend hover area"))
            Defaults.Toggle(key: .enableHaptics) {
                Label("Enable haptics", systemImage: "power")
            }
            .settingsHighlight(id: highlightID("Enable haptics"))
            Defaults.Toggle(key: .openNotchOnHover) {
                Label("Open notch on hover", systemImage: "hand.draw")
            }
            .onChange(of: openNotchOnHover) {
                if !openNotchOnHover {
                    Defaults[.enableGestures] = true
                }
            }
            .settingsHighlight(id: highlightID("Open notch on hover"))
            Defaults.Toggle(key: .keepNotchExpanded) {
                Label("Keep expanded", systemImage: "slider.horizontal.3")
            }
            .settingsHighlight(id: highlightID("Keep expanded"))
            Text("Keeps the panel expanded after opening, even when the pointer leaves. You can still close it manually.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label("When reopening", systemImage: "slider.horizontal.3").accessibilityHidden(true)
                Spacer(minLength: 12)
                Picker(selection: Binding(
                    get: { coordinator.availableTabs.contains { $0.id == reopenTab } ? reopenTab : ReopenTabSelection.lastPage },
                    set: { reopenTab = $0 }
                )) {
                    Text("Last page").tag(ReopenTabSelection.lastPage)
                    ForEach(coordinator.availableTabs) { tab in
                        Text(LocalizedStringKey(tab.label))
                            .tag(tab.id)
                    }
                } label: {
                    Label("When reopening", systemImage: "slider.horizontal.3")
                }
                    .labelsHidden()
            }
            .pickerStyle(.menu)
            .settingsHighlight(id: highlightID("When reopening"))
            if openNotchOnHover {
                SettingsSlider(value: $minimumHoverDuration, in: 0...1, step: 0.1, valueLabel: Text("\(minimumHoverDuration, specifier: "%.1f")s")) {
                    HStack {
                        Text("Minimum hover duration")
                        Spacer()
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
            HStack(spacing: 12) {
                Label("External display style", systemImage: "display").accessibilityHidden(true)
                Spacer(minLength: 12)
                Picker(selection: $externalDisplayStyle) {
                    ForEach(ExternalDisplayStyle.allCases) { style in
                        Text(style.localizedName)
                            .tag(style)
                    }
                } label: {
                    Label("External display style", systemImage: "display")
                }
                    .labelsHidden()
            }
            .onChange(of: externalDisplayStyle) {
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
            .settingsHighlight(id: highlightID("External display style"))
            Text(externalDisplayStyle.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Defaults.Toggle(key: .hideNonNotchUntilHover) {
                Label("Hide until hovered on non-notch displays", systemImage: "display")
            }
            .settingsHighlight(id: highlightID("Hide until hovered"))
            Text("When enabled, the notch slides up and hides on external (non-notch) displays until you hover over it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Notch behavior")
        }
    }

    @ViewBuilder
    private func notchWidthControls() -> some View {
        Section {
            let recommendedMin = currentRecommendedMinimumNotchWidth()
            let tabCount = enabledStandardTabCount()
            let dynamicRange = Double(recommendedMin)...900
            
            let closedRange = Double(80)...400
            let minimalisticRange = Double(250)...600

            let widthBinding = Binding<Double>(
                get: { Double(openNotchWidth) },
                set: { newValue in
                    let clamped = min(max(newValue, dynamicRange.lowerBound), dynamicRange.upperBound)
                    let value = CGFloat(clamped)
                    if openNotchWidth != value {
                        openNotchWidth = value
                    }
                }
            )
            
            let closedWidthBinding = Binding<Double>(
                get: { Double(closedNotchWidth) },
                set: { newValue in
                    let clamped = min(max(newValue, closedRange.lowerBound), closedRange.upperBound)
                    let value = CGFloat(clamped)
                    if closedNotchWidth != value {
                        closedNotchWidth = value
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            )

            VStack(alignment: .leading, spacing: 10) {
                Defaults.Toggle(key: .customizePhysicalNotchWidth) {
                    Label("Customize physical notch width", systemImage: "arrow.left.and.right")
                }
                .onChange(of: customizePhysicalNotchWidth) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
                .settingsHighlight(id: highlightID("Customize physical notch width"))
                
                SettingsSlider(
                    value: closedWidthBinding,
                    in: closedRange,
                    step: 5,
                    valueLabel: Text("\(Int(closedNotchWidth)) px")
                ) {
                    HStack {
                        Label("Closed notch / pill width", systemImage: "arrow.left.and.right")
                        Spacer()
                    }
                }
                .settingsHighlight(id: highlightID("Closed notch / pill width"))

                Divider().padding(.vertical, 4)

                SettingsSlider(
                    value: widthBinding,
                    in: dynamicRange,
                    step: 10,
                    valueLabel: Text("\(Int(openNotchWidth)) px")
                ) {
                    HStack {
                        Label("Expanded notch width", systemImage: "arrow.left.and.right")
                        Spacer()
                    }
                }
                .disabled(enableMinimalisticUI)
                .settingsHighlight(id: highlightID("Expanded notch width"))

                HStack {
                    Text("\(tabCount) tab\(tabCount == 1 ? "" : "s") enabled · min \(Int(recommendedMin)) px")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Width") {
                        openNotchWidth = recommendedMin
                    }
                    .disabled(abs(openNotchWidth - recommendedMin) < 0.5)
                    .buttonStyle(.bordered)
                }

                let description = enableMinimalisticUI
                ? String(localized: "Expanded width adjustments apply only to the standard notch layout. Disable Minimalistic UI to edit this value.")
                : String(localized: "Recommended minimum width adjusts automatically based on the number of enabled tabs.")

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onAppear {
                enforceMinimumNotchWidth()
            }
        } header: {
            HStack {
                Text("Notch Width")
                customBadge(text: "Beta")
            }
        }
    }

    private func enforceLockScreenGlassConsistency() {
        if lockScreenGlassStyle == .frosted && lockScreenGlassCustomizationMode != .standard {
            lockScreenGlassCustomizationMode = .standard
        }
        if lockScreenGlassCustomizationMode == .customLiquid && lockScreenGlassStyle != .liquid {
            lockScreenGlassStyle = .liquid
        }
    }
}


/// A segmented control with a soft track and an animated rounded selection.
struct SettingsSegmentedControl<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> String
    /// Segments share the width equally instead of sizing to their text. Used
    /// where the control is a tab bar rather than a row's right-hand control.
    var fillsWidth: Bool = false

    @Namespace private var selectionNamespace
    @State private var hovered: Item?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                segment(for: item)
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
        // Driven from the value, not only from `withAnimation` at the tap: a
        // selection changed from anywhere else -- settings search switching
        // segments, a Defaults write from another window -- should slide too,
        // and inside a Form row the tap's transaction does not always reach
        // the row's own content.
        .animation(selectionAnimation, value: selection)
    }

    private var selectionAnimation: Animation { .spring(response: 0.32, dampingFraction: 0.82) }

    @ViewBuilder
    private func segment(for item: Item) -> some View {
        let isSelected = selection == item
        let isHovered = hovered == item

        Button {
            guard selection != item else { return }
            withAnimation(selectionAnimation) { selection = item }
        } label: {
            Text(label(item))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .frame(height: 24)
                .background {
                    if isSelected {
                        // The system accent colour, so the control follows
                        // System Settings > Appearance the way the stock
                        // segmented picker did.
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "selectedSegment", in: selectionNamespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) {
                if inside {
                    hovered = item
                } else if hovered == item {
                    hovered = nil
                }
            }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A settings row whose control is a ``SettingsSegmentedControl``.
///
/// Drop-in for `Picker(title, selection:).pickerStyle(.segmented)`: label on
/// the left, control on the right, same as every other row in the form.
struct SettingsSegmentedPicker<Item: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Item
    let items: [Item]
    let label: (Item) -> String

    init(
        _ title: LocalizedStringKey,
        selection: Binding<Item>,
        items: [Item],
        label: @escaping (Item) -> String
    ) {
        self.title = title
        self._selection = selection
        self.items = items
        self.label = label
    }

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: "slider.horizontal.3")
            Spacer(minLength: 8)
            SettingsSegmentedControl(items: items, selection: $selection, label: label)
        }
    }
}

/// Page-level tab strip shown at the top of a settings section that owns
/// several sub-pages (e.g. Appearance & Interaction). Unlike
/// ``SettingsSegmentedControl`` -- a right-hand control inside a form row --
/// this one is a centered floating pill with icon + label segments, sized and
/// styled for whole-page navigation.
struct SettingsPageTabBar<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let icon: (Item) -> String
    /// VoiceOver name for the whole strip.
    let accessibilityTitle: String

    @Namespace private var selectionNamespace
    @State private var hovered: Item?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                segment(for: item)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                )
        }
        // Driven from the value, not only from `withAnimation` at the tap, so
        // a selection changed from elsewhere -- settings search jumping to a
        // page, another window -- slides the thumb too.
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilityTitle))
    }

    private var selectionAnimation: Animation { .spring(response: 0.32, dampingFraction: 0.82) }

    @ViewBuilder
    private func segment(for item: Item) -> some View {
        let isSelected = selection == item
        let isHovered = hovered == item

        Button {
            guard selection != item else { return }
            withAnimation(selectionAnimation) { selection = item }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon(item))
                    .font(.system(size: 12, weight: .semibold))
                Text(title(item))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .frame(height: 30)
            .background {
                if isSelected {
                    // System accent colour, so the strip follows
                    // System Settings > Appearance like the row controls do.
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor)
                        .overlay(
                            LinearGradient(colors: [.white.opacity(0.22), .clear],
                                           startPoint: .top, endPoint: .center)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        )
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 5, x: 0, y: 1.5)
                        .matchedGeometryEffect(id: "pageTabSelection", in: selectionNamespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) {
                if inside {
                    hovered = item
                } else if hovered == item {
                    hovered = nil
                }
            }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct LockScreenSettings: View {
    @Default(.enableDoNotDisturbDetection) private var focusDetectionEnabled
    @Default(.showDoNotDisturbIndicator) private var focusIndicatorEnabled
    @Default(.showMediaOutputControl) private var showMediaOutputControl
    @Default(.enableReminderLiveActivity) private var enableReminderLiveActivity
    @Default(.lockScreenLiveActivityIconStyle) private var lockScreenLiveActivityIconStyle
    @ObservedObject private var calendarManager = CalendarManager.shared
    @ObservedObject private var previewManager = LockScreenWidgetPreviewManager.shared
    @Default(.lockScreenGlassStyle) private var lockScreenGlassStyle
    @Default(.lockScreenGlassCustomizationMode) private var lockScreenGlassCustomizationMode
    @Default(.lockScreenMusicLiquidGlassVariant) private var lockScreenMusicLiquidGlassVariant
    @Default(.lockScreenTimerLiquidGlassVariant) private var lockScreenTimerLiquidGlassVariant
    @Default(.lockScreenTimerGlassStyle) private var lockScreenTimerGlassStyle
    @Default(.lockScreenTimerGlassCustomizationMode) private var lockScreenTimerGlassCustomizationMode
    @Default(.lockScreenTimerWidgetUsesBlur) private var timerGlassModeIsGlass
    @Default(.enableLockScreenMediaWidget) private var enableLockScreenMediaWidget
    @Default(.lockScreenMusicFullscreenArtworkEnabled) private var lockScreenMusicFullscreenArtworkEnabled
    @Default(.enableLockScreenTimerWidget) private var enableLockScreenTimerWidget
    @Default(.enableLockScreenWeatherWidget) private var enableLockScreenWeatherWidget
    @Default(.enableLockScreenFocusWidget) private var enableLockScreenFocusWidget
    @Default(.siriResponsivenessMode) private var siriResponsivenessMode
    @Default(.lockScreenWeatherWidgetStyle) private var lockScreenWeatherWidgetStyle
    @Default(.lockScreenWeatherProviderSource) private var lockScreenWeatherProviderSource
    @Default(.lockScreenWeatherTemperatureUnit) private var lockScreenWeatherTemperatureUnit
    @Default(.lockScreenBatteryShowsCharging) private var lockScreenWeatherShowsCharging
    @Default(.lockScreenBatteryShowsBatteryGauge) private var lockScreenWeatherShowsBatteryGauge
    @Default(.lockScreenWeatherShowsAQI) private var lockScreenWeatherShowsAQI
    @Default(.lockScreenWeatherShowsSunrise) private var lockScreenWeatherShowsSunrise
    @Default(.lockScreenWeatherAQIScale) private var lockScreenWeatherAQIScale
    @Default(.enableLockScreenReminderWidget) private var enableLockScreenReminderWidget
    @Default(.lockScreenReminderChipStyle) private var lockScreenReminderChipStyle
    @Default(.lockScreenReminderWidgetHorizontalAlignment) private var lockScreenReminderWidgetHorizontalAlignment
    @Default(.lockScreenReminderWidgetVerticalOffset) private var lockScreenReminderWidgetVerticalOffset
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.lockScreenShowCalendarCountdown) private var lockScreenShowCalendarCountdown
    @Default(.lockScreenShowCalendarEvent) private var lockScreenShowCalendarEvent
    @Default(.lockScreenShowCalendarEventEntireDuration) private var lockScreenShowCalendarEventEntireDuration
    @Default(.lockScreenShowCalendarEventAfterStartWindow) private var lockScreenShowCalendarEventAfterStartWindow
    @Default(.lockScreenShowCalendarTimeRemaining) private var lockScreenShowCalendarTimeRemaining
    @Default(.lockScreenShowCalendarStartTimeAfterBegins) private var lockScreenShowCalendarStartTimeAfterBegins
    @Default(.lockScreenCalendarEventLookaheadWindow) private var lockScreenCalendarEventLookaheadWindow
    @Default(.lockScreenCalendarSelectionMode) private var lockScreenCalendarSelectionMode
    @Default(.lockScreenSelectedCalendarIDs) private var lockScreenSelectedCalendarIDs
    @Default(.lockScreenShowCalendarEventAfterStartEnabled) private var lockScreenShowCalendarEventAfterStartEnabled
    @Default(.lockScreenMusicMergedAirPlayOutput) private var lockScreenMusicMergedAirPlayOutput
    @Default(.lockScreenWidgetAppearance) private var lockScreenWidgetAppearance
    @ObservedObject private var musicManager = MusicManager.shared

    private var isAppleMusicActive: Bool {
        musicManager.bundleIdentifier == "com.apple.Music"
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.lockScreen.highlightID(for: title)
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private enum CalendarLookaheadOption: String, CaseIterable, Identifiable {
        case mins15 = "15m"
        case mins30 = "30m"
        case hour1 = "1h"
        case hours3 = "3h"
        case hours6 = "6h"
        case hours12 = "12h"
        case restOfDay = "rest_of_day"
        case allTime = "all_time"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mins15: return String(localized: "15 mins")
            case .mins30: return String(localized: "30 mins")
            case .hour1: return String(localized: "1 hour")
            case .hours3: return String(localized: "3 hours")
            case .hours6: return String(localized: "6 hours")
            case .hours12: return String(localized: "12 hours")
            case .restOfDay: return String(localized: "Rest of the day")
            case .allTime: return String(localized: "All time")
            }
        }
    }

    private enum ReminderAlignmentOption: String, CaseIterable, Identifiable {
        case leading
        case center
        case trailing

        var id: String { rawValue }

        var title: String {
            switch self {
            case .leading: return String(localized: "Left")
            case .center: return String(localized: "Center")
            case .trailing: return String(localized: "Right")
            }
        }
    }

    private var musicVariantBinding: Binding<Double> {
        Binding(
            get: { Double(lockScreenMusicLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                lockScreenMusicLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    private var timerVariantBinding: Binding<Double> {
        Binding(
            get: { Double(lockScreenTimerLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                lockScreenTimerLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    private var timerSurfaceBinding: Binding<LockScreenTimerSurfaceMode> {
        Binding(
            get: { timerGlassModeIsGlass ? .glass : .classic },
            set: { mode in timerGlassModeIsGlass = (mode == .glass) }
        )
    }

    private enum SubTab: Hashable, CaseIterable {
        case general, widgets, layout
        var title: String {
            switch self {
            case .general: return String(localized: "General")
            case .widgets: return String(localized: "Widgets")
            case .layout: return String(localized: "Layout")
            }
        }
        var icon: String {
            switch self {
            case .general: return "switch.2"
            case .widgets: return "widget.small"
            case .layout: return "rectangle.3.group"
            }
        }
    }

    @EnvironmentObject private var coordinator: SettingsHighlightCoordinator
    @State private var selectedSubTab: SubTab = .general
    @State private var advancedExpanded = false
    @State private var mediaMoreExpanded = false
    @State private var revealedSection: String?
    @State private var searchedTitle: String?

    private var calendarBehaviorBinding: Binding<LockScreenCalendarBehavior> {
        Binding(
            get: {
                LockScreenCalendarBehavior(
                    entireDuration: lockScreenShowCalendarEventEntireDuration,
                    afterStartEnabled: lockScreenShowCalendarEventAfterStartEnabled)
            },
            set: { behavior in
                lockScreenShowCalendarEventEntireDuration = behavior.entireDuration
                lockScreenShowCalendarEventAfterStartEnabled = behavior.afterStartEnabled
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    tabBar
                    Spacer(minLength: 12)
                    previewButton
                }
                VStack(alignment: .leading, spacing: 12) {
                    tabBar
                    previewButton
                }
            }
            .frame(maxWidth: 712)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Group {
                switch selectedSubTab {
                case .general: generalForm
                case .widgets: widgetsForm
                case .layout:
                    Form {
                        LockScreenPositioningControls().settingsHighlight(id: highlightID("Lock Screen Positioning"))
                    }
                }
            }
            .modifier(SettingsPageStyle(compact: true))
        }
        .onAppear(perform: enforceLockScreenGlassConsistency)
        .onChange(of: lockScreenGlassStyle) { _, _ in enforceLockScreenGlassConsistency() }
        .onChange(of: lockScreenGlassCustomizationMode) { _, _ in enforceLockScreenGlassConsistency() }
        .navigationTitle("Lock Screen")
        .onReceive(coordinator.$pendingScrollRequest) { request in
            guard let request, request.tab == .lockScreen,
                request.id.hasPrefix("lockScreen-")
            else { return }
            revealSearchResult(String(request.id.dropFirst("lockScreen-".count)))
        }
    }

    private var tabBar: some View {
        SettingsPageTabBar(
            items: SubTab.allCases,
            selection: Binding(
                get: { selectedSubTab },
                set: {
                    selectedSubTab = $0
                    revealedSection = nil
                    searchedTitle = nil
                }),
            title: { $0.title }, icon: { $0.icon },
            accessibilityTitle: String(localized: "Lock Screen")
        )
        .fixedSize()
    }

    private var previewButton: some View {
        Button(previewManager.isPreviewVisible ? "Hide lock screen preview" : "Preview lock screen widgets") {
            previewManager.togglePreview()
        }
        .settingsHighlight(id: highlightID("Preview lock screen widgets"))
    }

    private func dependencyLink(_ label: LocalizedStringKey, tab: SettingsTab, title: String) -> some View {
        Button {
            coordinator.focus(
                on: SettingsSearchEntry(
                    tab: tab, title: title, keywords: [],
                    highlightID: tab.highlightID(for: title)))
        } label: {
            Label(label, systemImage: "arrow.up.forward.square")
        }
        .buttonStyle(.link)
    }

    private func revealSearchResult(_ title: String) {
        searchedTitle = title
        switch title {
        case "Enable lock screen live activity", "Live activity icon", "Play lock/unlock sounds", "Widget appearance",
            "Siri detection speed", "Preview lock screen widgets":
            selectedSubTab = .general
            advancedExpanded = title == "Siri detection speed"
        case "Show lock screen media panel", "Enable album art parallax", "Always show volume control",
            "Show media app icon", "Show merged AirPlay and output devices", "Material", "Glass mode",
            "Show panel border", "Use enhanced liquid border", "Music panel variant", "Enable media panel blur",
            "Show fullscreen artwork on right-click", "Use album art layout over fullscreen canvas",
            "Keep album art visible during fullscreen artwork":
            selectedSubTab = .widgets
            revealedSection = "media"
            mediaMoreExpanded = true
        case "Show lock screen timer", "Timer surface", "Timer glass material", "Timer liquid mode",
            "Timer widget variant":
            selectedSubTab = .widgets
            revealedSection = "timer"
        case "Show lock screen weather", "Weather data provider", "Temperature unit", "Show location label",
            "Show sunrise time", "Show AQI widget", "Air quality scale", "Use colored gauges":
            selectedSubTab = .widgets
            revealedSection = "weather"
        case "Show battery indicator", "Use MacBook icon when on battery", "Show charging status",
            "Show charging percentage", "Show Bluetooth battery":
            selectedSubTab = .widgets
            revealedSection = "battery"
        case "Show next calendar event", "Show events within the next", "Show events from all calendars",
            "Show countdown", "Show event for entire duration", "Hide active event and show next upcoming event",
            "After an event starts", "Show time remaining", "Show start time after event begins":
            selectedSubTab = .widgets
            revealedSection = "calendar"
        case "Show lock screen reminder", "Chip color", "Reminder alignment", "Reminder vertical offset":
            selectedSubTab = .widgets
            revealedSection = "reminder"
        case "Lock Screen Positioning":
            selectedSubTab = .layout
        default:
            selectedSubTab = .widgets
        }
    }

    private var generalForm: some View {
        Form {
            activitySection
            appearanceSection
            advancedSection
        }
    }

    private var widgetsForm: some View {
        Form {
            mediaSection
            timerSection
            statusLayoutSection
            weatherSection
            batterySection
            focusSection
            calendarSection
            reminderSection
        }
    }

    private var activitySection: some View {
        Section {
            Defaults.Toggle(key: .enableLockScreenLiveActivity) {
                Label("Enable lock screen live activity", systemImage: "display")
            }
            .settingsHighlight(id: highlightID("Enable lock screen live activity"))

            LockScreenSegmentedPicker(
                "Live activity icon", selection: $lockScreenLiveActivityIconStyle,
                items: [LockScreenLiveActivityIconStyle.lock, .fingerprint, .both]
            ) { style in
                switch style {
                case .lock: return String(localized: "Lock")
                case .fingerprint: return String(localized: "Fingerprint")
                case .both: return String(localized: "Lock and fingerprint")
                }
            }
            .settingsHighlight(id: highlightID("Live activity icon"))

            Defaults.Toggle(key: .enableLockSounds) {
                Label("Play lock/unlock sounds", systemImage: "speaker.wave.2")
            }
            .settingsHighlight(id: highlightID("Play lock/unlock sounds"))
        } header: {
            Text("Live Activity & Feedback")
        } footer: {
            Text(
                "Select the lock, the fingerprint, or both icons. When the fingerprint is selected, the live activity stays open long enough to complete its unlock animation."
            )
        }
    }

    private var appearanceSection: some View {
        Section {
            LockScreenSegmentedPicker(
                "Widget appearance",
                selection: $lockScreenWidgetAppearance,
                items: Array(LockScreenWidgetAppearance.allCases)
            ) { $0.localizedName }
            .settingsHighlight(id: highlightID("Widget appearance"))

        } header: {
            Text("Widget appearance")
        } footer: {
            Text(
                "Sets the text contrast for media, timer, status and reminder widgets. Choose Light for a bright wallpaper."
            )
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: 16) {

                    VStack(alignment: .leading, spacing: 6) {
                        LockScreenSettingRow("Siri detection speed") {
                            Picker(selection: $siriResponsivenessMode) {
                                ForEach(SiriResponsivenessMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            } label: {
                                Label("Siri detection speed", systemImage: "clock")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        Text(siriResponsivenessMode.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .help(
                        "Higher speeds allow widgets to hide almost instantly when Siri is invoked, but may impact battery life when on battery power."
                    )
                    .settingsHighlight(id: highlightID("Siri detection speed"))
                    Divider()
                    Button("Copy Latest Crash Report") { copyLatestCrashReport() }
                }
                .padding(.top, 12)
            }
        }
    }

    private var mediaSection: some View {
        Section {
            Defaults.Toggle(key: .enableLockScreenMediaWidget) {
                Label("Show lock screen media panel", systemImage: "music.note")
            }
            .disabled(!showStandardMediaControls)
            .settingsHighlight(id: highlightID("Show lock screen media panel"))
            if !showStandardMediaControls {
                dependencyLink(
                    "Enable media controls in Media settings", tab: .media,
                    title: "Show media controls in Dynamic Island")
            }
            if enableLockScreenMediaWidget && showStandardMediaControls || revealedSection == "media" {
                Group {
                    Defaults.Toggle(key: .lockScreenMusicAlbumParallaxEnabled) {
                        Label("Enable album art parallax", systemImage: "power")
                    }
                    .settingsHighlight(id: highlightID("Enable album art parallax"))
                    .help("Applies the notch-style parallax effect to the lock screen media widget album art.")

                    VStack(alignment: .leading, spacing: 6) {
                        Defaults.Toggle(key: .alwaysShowLockScreenVolume) {
                            Label("Always show volume control", systemImage: "speaker.wave.2")
                        }
                        .disabled(!showMediaOutputControl)
                        Text(
                            showMediaOutputControl
                                ? "Keeps a volume slider under the playback controls on the lock screen, instead of leaving it behind the output button. The volume keys move it while the Mac is locked, where the notch cannot draw."
                                : "Needs the \"Show Change Media Output control\" setting on the Media tab, which the lock screen panel takes its volume slider from."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .settingsHighlight(id: highlightID("Always show volume control"))
                    if !showMediaOutputControl {
                        dependencyLink("Open Media settings", tab: .media, title: "Show Change Media Output control")
                    }

                    Defaults.Toggle(key: .lockScreenShowAppIcon) {
                        Label("Show media app icon", systemImage: "music.note")
                    }
                    .disabled(!enableLockScreenMediaWidget)
                    .settingsHighlight(id: highlightID("Show media app icon"))
                    if isAppleMusicActive {
                        Defaults.Toggle(key: .lockScreenMusicMergedAirPlayOutput) {
                            Label("Show merged AirPlay and output devices", systemImage: "power")
                        }
                        .disabled(!enableLockScreenMediaWidget)
                        .settingsHighlight(id: highlightID("Show merged AirPlay and output devices"))
                    }
                    DisclosureGroup("More settings", isExpanded: $mediaMoreExpanded) {
                        mediaAppearanceControls
                            .padding(.top, 12)
                    }

                }
                .disabled(!(enableLockScreenMediaWidget && showStandardMediaControls))
            }
        } header: {
            Text("Media Panel")
        } footer: {
            Text("Enable and style the media controls that appear above the system clock when the screen is locked.")
        }
    }

    private var mediaAppearanceControls: some View {
        VStack(alignment: .leading, spacing: 16) {

            if #available(macOS 26.0, *) {
                LockScreenSettingRow("Material") {
                    Picker(selection: $lockScreenGlassStyle) {
                        ForEach(LockScreenGlassStyle.allCases) { style in
                            Text(style.localizedName).tag(style)
                        }
                    } label: {
                        Label("Material", systemImage: "circle.lefthalf.filled")
                    }
                    .labelsHidden()
                }
                .settingsHighlight(id: highlightID("Material"))
            } else {
                LockScreenSettingRow("Material") {
                    Picker(selection: $lockScreenGlassStyle) {
                        ForEach(LockScreenGlassStyle.allCases) { style in
                            Text(style.localizedName).tag(style)
                        }
                    } label: {
                        Label("Material", systemImage: "circle.lefthalf.filled")
                    }
                    .labelsHidden()
                }
                .disabled(true)
                .settingsHighlight(id: highlightID("Material"))
                Text("Liquid Glass requires macOS 26 or later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if lockScreenGlassStyle == .liquid || searchedTitle == "Glass mode" {
                LockScreenSegmentedPicker(
                    "Glass mode",
                    selection: $lockScreenGlassCustomizationMode,
                    items: Array(LockScreenGlassCustomizationMode.allCases)
                ) { $0.localizedName }
                .disabled(lockScreenGlassStyle != .liquid)
                .settingsHighlight(id: highlightID("Glass mode"))

                if lockScreenGlassCustomizationMode == .customLiquid {
                    Text("Choose a glass variant for the media panel below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Custom Liquid settings require the Liquid Glass material.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Defaults.Toggle(key: .lockScreenPanelShowsBorder) {
                Label("Show panel border", systemImage: "power")
            }
            .disabled(!enableLockScreenMediaWidget)
            .settingsHighlight(id: highlightID("Show panel border"))
            if lockScreenGlassCustomizationMode == .customLiquid {
                Defaults.Toggle(key: .lockScreenMusicUsesEnhancedLiquidBorder) {
                    Label("Use enhanced liquid border", systemImage: "slider.horizontal.3")
                }
                .disabled(!enableLockScreenMediaWidget)
                .settingsHighlight(id: highlightID("Use enhanced liquid border"))
            }
            if lockScreenGlassCustomizationMode == .customLiquid {
                variantSlider(
                    title: "Music panel variant",
                    value: musicVariantBinding,
                    currentValue: lockScreenMusicLiquidGlassVariant.rawValue,
                    isEnabled: enableLockScreenMediaWidget,
                    highlight: highlightID("Music panel variant"),
                    preview: AnyView(
                        LockScreenGlassVariantPreviewCell(variant: $lockScreenMusicLiquidGlassVariant)
                    )
                )
            } else if lockScreenGlassStyle == .frosted {
                Defaults.Toggle(key: .lockScreenPanelUsesBlur) {
                    Label("Enable media panel blur", systemImage: "music.note")
                }
                .disabled(!enableLockScreenMediaWidget)
                .settingsHighlight(id: highlightID("Enable media panel blur"))
            } else {
                blurSettingUnavailableRow

                    .settingsHighlight(id: highlightID("Enable media panel blur"))
            }
            Defaults.Toggle(key: .lockScreenMusicFullscreenArtworkEnabled) {
                Label("Show fullscreen artwork on right-click", systemImage: "display")
            }
            .disabled(!enableLockScreenMediaWidget)
            .settingsHighlight(id: highlightID("Show fullscreen artwork on right-click"))
            Defaults.Toggle(key: .lockScreenUseArtworkLayoutOverFullscreenCanvas) {
                Label("Use album art layout over fullscreen canvas", systemImage: "display")
            }
            .disabled(!enableLockScreenMediaWidget || !lockScreenMusicFullscreenArtworkEnabled)
            .settingsHighlight(id: highlightID("Use album art layout over fullscreen canvas"))
            VStack(alignment: .leading, spacing: 4) {
                Defaults.Toggle(key: .lockScreenKeepAlbumArtVisibleDuringFullscreenArtwork) {
                    Label("Keep album art visible during fullscreen artwork", systemImage: "display")
                }
                .disabled(!enableLockScreenMediaWidget || !lockScreenMusicFullscreenArtworkEnabled)
                .settingsHighlight(id: highlightID("Keep album art visible during fullscreen artwork"))
                Text(
                    "Right-click the album art on the lock screen to set it as the wallpaper. Right-click again or click the background to restore the original wallpaper. If a canvas is available, Eave can also keep the same album art + player layout on top of the live canvas."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

        }
    }

    private var timerSection: some View {
        Section {
            Defaults.Toggle(key: .enableLockScreenTimerWidget) {
                Label("Show lock screen timer", systemImage: "clock")
            }
            .settingsHighlight(id: highlightID("Show lock screen timer"))
            if enableLockScreenTimerWidget || revealedSection == "timer" {
                Group {
                    LockScreenSegmentedPicker(
                        "Timer surface",
                        selection: timerSurfaceBinding,
                        items: Array(LockScreenTimerSurfaceMode.allCases)
                    ) { $0.localizedName }
                    .disabled(!enableLockScreenTimerWidget)

                    .settingsHighlight(id: highlightID("Timer surface"))

                    if timerGlassModeIsGlass || searchedTitle == "Timer glass material"
                        || searchedTitle == "Timer liquid mode" || searchedTitle == "Timer widget variant"
                    {
                        LockScreenSettingRow("Timer glass material") {
                            Picker(selection: $lockScreenTimerGlassStyle) {
                                ForEach(LockScreenGlassStyle.allCases) { style in
                                    Text(style.localizedName).tag(style)
                                }
                            } label: {
                                Label("Timer glass material", systemImage: "clock")
                            }
                            .labelsHidden()
                        }
                        .disabled(!enableLockScreenTimerWidget)

                        .disabled(!timerGlassModeIsGlass)
                        .settingsHighlight(id: highlightID("Timer glass material"))

                        if lockScreenTimerGlassStyle == .liquid || searchedTitle == "Timer liquid mode"
                            || searchedTitle == "Timer widget variant"
                        {
                            LockScreenSegmentedPicker(
                                "Timer liquid mode",
                                selection: $lockScreenTimerGlassCustomizationMode,
                                items: Array(LockScreenGlassCustomizationMode.allCases)
                            ) { $0.localizedName }
                            .disabled(!enableLockScreenTimerWidget)

                            .disabled(!timerGlassModeIsGlass || lockScreenTimerGlassStyle != .liquid)
                            .settingsHighlight(id: highlightID("Timer liquid mode"))

                            if lockScreenTimerGlassCustomizationMode == .customLiquid
                                || searchedTitle == "Timer widget variant"
                            {
                                variantSlider(
                                    title: "Timer widget variant",
                                    value: timerVariantBinding,
                                    currentValue: lockScreenTimerLiquidGlassVariant.rawValue,
                                    isEnabled: enableLockScreenTimerWidget && timerGlassModeIsGlass
                                        && lockScreenTimerGlassStyle == .liquid
                                        && lockScreenTimerGlassCustomizationMode == .customLiquid,
                                    highlight: highlightID("Timer widget variant")
                                )
                            }
                        } else {
                            Text("Uses the frosted blur treatment while glass mode is enabled.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text("Classic mode keeps the original translucent black background.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                    }

                }
                .disabled(!(enableLockScreenTimerWidget))
            }
        } header: {
            Text("Timer Widget")
        } footer: {
            Text("The timer sits above the media panel and has its own surface and material settings.")
        }
    }

    private var statusLayoutSection: some View {
        Section {
            LockScreenSegmentedPicker(
                "Status area layout",
                selection: $lockScreenWeatherWidgetStyle,
                items: Array(LockScreenWeatherWidgetStyle.allCases)
            ) { $0.localizedName }
            .settingsHighlight(id: highlightID("Widget layout"))

            if lockScreenWeatherWidgetStyle == .circular {
                Text(
                    "The circular layout has no room for the location label or sunrise time, and draws the battery gauge as a ring."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Status area")
        } footer: {
            Text("Shared layout for weather, battery, Focus and calendar events.")
        }
    }

    private var weatherSection: some View {
        Section {
            Defaults.Toggle(key: .enableLockScreenWeatherWidget) {
                Label("Show lock screen weather", systemImage: "display")
            }
            .settingsHighlight(id: highlightID("Show lock screen weather"))
            if enableLockScreenWeatherWidget || revealedSection == "weather" {
                Group {
                    LocationSettingsPermissionRow(message: "Optional. Allows weather to use your current location.")

                    Group {
                        LockScreenSegmentedPicker(
                            "Weather data provider",
                            selection: $lockScreenWeatherProviderSource,
                            items: Array(LockScreenWeatherProviderSource.allCases)
                        ) { $0.displayName }
                        .settingsHighlight(id: highlightID("Weather data provider"))

                        LockScreenSegmentedPicker(
                            "Temperature unit",
                            selection: $lockScreenWeatherTemperatureUnit,
                            items: Array(LockScreenWeatherTemperatureUnit.allCases)
                        ) { $0.localizedName }
                        .settingsHighlight(id: highlightID("Temperature unit"))

                        Defaults.Toggle(key: .lockScreenWeatherShowsLocation) {
                            Label("Show location label", systemImage: "power")
                        }
                        .disabled(lockScreenWeatherWidgetStyle == .circular)
                        .help(lockScreenWeatherWidgetStyle == .circular ? "Available in the inline layout only." : "")
                        .settingsHighlight(id: highlightID("Show location label"))

                        Defaults.Toggle(key: .lockScreenWeatherShowsSunrise) {
                            Label("Show sunrise time", systemImage: "clock")
                        }
                        .disabled(lockScreenWeatherWidgetStyle != .inline)
                        .help(lockScreenWeatherWidgetStyle != .inline ? "Available in the inline layout only." : "")
                        .settingsHighlight(id: highlightID("Show sunrise time"))

                        Defaults.Toggle(key: .lockScreenWeatherShowsAQI) {
                            Label("Show AQI widget", systemImage: "power")
                        }
                        .disabled(!lockScreenWeatherProviderSource.supportsAirQuality)
                        .settingsHighlight(id: highlightID("Show AQI widget"))

                        Group {
                            LockScreenSegmentedPicker(
                                "Air quality scale",
                                selection: $lockScreenWeatherAQIScale,
                                items: Array(LockScreenWeatherAirQualityScale.allCases)
                            ) { $0.displayName }
                            .settingsHighlight(id: highlightID("Air quality scale"))
                        }
                        .disabled(!(lockScreenWeatherShowsAQI && lockScreenWeatherProviderSource.supportsAirQuality))

                        if !lockScreenWeatherProviderSource.supportsAirQuality {
                            Text("Air quality requires the Open Meteo provider.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Defaults.Toggle(key: .lockScreenWeatherUsesGaugeTint) {
                            Label("Use colored gauges", systemImage: "paintpalette")
                        }
                        .settingsHighlight(id: highlightID("Use colored gauges"))
                    }
                    .disabled(!enableLockScreenWeatherWidget)

                }
                .disabled(!(enableLockScreenWeatherWidget))
            }
        } header: {
            Text("Status area · Weather")
        } footer: {
            Text("Weather uses the shared status area layout.")
        }
    }

    @ViewBuilder
    private var batterySection: some View {
        if BatteryActivityManager.shared.hasBattery() {
            Section {
                Defaults.Toggle(key: .lockScreenBatteryShowsBatteryGauge) {
                    Label("Show battery indicator", systemImage: "battery.100")
                }
                .settingsHighlight(id: highlightID("Show battery indicator"))

                if lockScreenWeatherShowsBatteryGauge || revealedSection == "battery" {
                    Defaults.Toggle(key: .lockScreenBatteryUsesLaptopSymbol) {
                        Label("Use MacBook icon when on battery", systemImage: "battery.100")
                    }
                    .disabled(!lockScreenWeatherShowsBatteryGauge)
                    .settingsHighlight(id: highlightID("Use MacBook icon when on battery"))

                    Defaults.Toggle(key: .lockScreenBatteryShowsCharging) {
                        Label("Show charging status", systemImage: "battery.100")
                    }
                    .disabled(!lockScreenWeatherShowsBatteryGauge)
                    .settingsHighlight(id: highlightID("Show charging status"))

                    if lockScreenWeatherShowsCharging || searchedTitle == "Show charging percentage" {
                        Defaults.Toggle(key: .lockScreenBatteryShowsChargingPercentage) {
                            Label("Show charging percentage", systemImage: "battery.100")
                        }
                        .disabled(!lockScreenWeatherShowsBatteryGauge || !lockScreenWeatherShowsCharging)
                        .settingsHighlight(id: highlightID("Show charging percentage"))
                    }

                    Defaults.Toggle(key: .lockScreenBatteryShowsBluetooth) {
                        Label("Show Bluetooth battery", systemImage: "battery.100")
                    }
                    .disabled(!lockScreenWeatherShowsBatteryGauge)
                    .settingsHighlight(id: highlightID("Show Bluetooth battery"))
                }
            } header: {
                Text("Status area · Battery")
            } footer: {
                Text("Enable the battery capsule and configure its layout.")
            }
        }
    }

    private var focusSection: some View {
        Section {
            Defaults.Toggle(key: .enableLockScreenFocusWidget) {
                Label("Show focus widget", systemImage: "power")
            }
            .settingsHighlight(id: highlightID("Show focus widget"))
            if !focusDetectionEnabled || !focusIndicatorEnabled {
                dependencyLink(
                    "Open Focus settings", tab: .liveActivities,
                    title: focusDetectionEnabled ? "Show Focus indicator" : "Enable Focus detection")
            }
        } header: {
            Text("Status area · Focus")
        } footer: {
            Text("Displays the current Focus state above the weather capsule whenever Focus detection is enabled.")
        }
    }

    private var calendarSection: some View {
        Section {
            Defaults.Toggle(key: .lockScreenShowCalendarEvent) {
                Label("Show next calendar event", systemImage: "calendar")
            }
            .settingsHighlight(id: highlightID("Show next calendar event"))
            if lockScreenShowCalendarEvent || revealedSection == "calendar" {
                Group {

                    LockScreenSettingRow("Show events within the next") {
                        Picker("Show events within the next", selection: $lockScreenCalendarEventLookaheadWindow) {
                            ForEach(CalendarLookaheadOption.allCases) { option in
                                Text(option.title).tag(option.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .disabled(!lockScreenShowCalendarEvent)
                    .settingsHighlight(id: highlightID("Show events within the next"))

                    Toggle(
                        "Show events from all calendars", systemImage: "calendar",
                        isOn: Binding(
                            get: { lockScreenCalendarSelectionMode == "all" },
                            set: { useAll in
                                if useAll {
                                    lockScreenCalendarSelectionMode = "all"
                                } else {
                                    lockScreenCalendarSelectionMode = "selected"
                                    lockScreenSelectedCalendarIDs = Set(calendarManager.eventCalendars.map { $0.id })
                                }
                            }
                        )
                    )
                    .disabled(!lockScreenShowCalendarEvent)
                    .settingsHighlight(id: highlightID("Show events from all calendars"))

                    if lockScreenCalendarSelectionMode != "all" {
                        HStack {
                            Spacer()
                            Button("Deselect All") {
                                lockScreenSelectedCalendarIDs = []
                            }
                            .buttonStyle(.link)
                        }
                        .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                                Toggle(
                                    isOn: Binding(
                                        get: { lockScreenSelectedCalendarIDs.contains(calendar.id) },
                                        set: { isOn in
                                            if isOn {
                                                lockScreenSelectedCalendarIDs.insert(calendar.id)
                                            } else {
                                                lockScreenSelectedCalendarIDs.remove(calendar.id)
                                            }
                                        }
                                    )
                                ) {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(calendar.color))
                                            .frame(width: 8, height: 8)
                                        Text(calendar.title)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                        .padding(.top, 4)
                        .padding(.leading, 2)
                        .disabled(!lockScreenShowCalendarEvent)
                    }

                    Defaults.Toggle(key: .lockScreenShowCalendarCountdown) {
                        Label("Show countdown", systemImage: "power")
                    }
                    .disabled(!lockScreenShowCalendarEvent)
                    .settingsHighlight(id: highlightID("Show countdown"))

                    LockScreenSettingRow("After an event starts") {
                        Picker("After an event starts", selection: calendarBehaviorBinding) {
                            ForEach(LockScreenCalendarBehavior.allCases, id: \.self) { behavior in
                                Text(LocalizedStringKey(behavior.rawValue)).tag(behavior)
                            }
                        }
                        .labelsHidden()
                    }
                    .settingsHighlight(id: highlightID("Show event for entire duration"))
                    .settingsHighlight(id: highlightID("Hide active event and show next upcoming event"))
                    .settingsHighlight(id: highlightID("After an event starts"))

                    if calendarBehaviorBinding.wrappedValue == .briefly {
                        LockScreenSettingRow("Show event after it starts") {
                            Picker(
                                "Show event after it starts", selection: $lockScreenShowCalendarEventAfterStartWindow
                            ) {
                                Text("1 min").tag("1m")
                                Text("5 mins").tag("5m")
                                Text("10 mins").tag("10m")
                                Text("15 mins").tag("15m")
                                Text("30 mins").tag("30m")
                                Text("45 mins").tag("45m")
                                Text("1 hour").tag("1h")
                                Text("2 hours").tag("2h")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .disabled(
                            !lockScreenShowCalendarEvent || lockScreenShowCalendarEventEntireDuration
                                || !lockScreenShowCalendarEventAfterStartEnabled)

                    }

                    Defaults.Toggle(key: .lockScreenShowCalendarTimeRemaining) {
                        Label("Show time remaining", systemImage: "clock")
                    }
                    .disabled(!lockScreenShowCalendarEvent)
                    .settingsHighlight(id: highlightID("Show time remaining"))

                    Defaults.Toggle(key: .lockScreenShowCalendarStartTimeAfterBegins) {
                        Label("Show start time after event begins", systemImage: "clock")
                    }
                    .disabled(!lockScreenShowCalendarEvent)
                    .settingsHighlight(id: highlightID("Show start time after event begins"))

                }
                .disabled(!(lockScreenShowCalendarEvent))
            }
        } header: {
            Text("Status area · Calendar")
        } footer: {
            Text(
                "Displays your next upcoming calendar event above or below the weather capsule. Calendar selection here is independent from the Dynamic Island calendar filter."
            )
        }
    }

    private var reminderSection: some View {
        Section {
            Defaults.Toggle(key: .enableLockScreenReminderWidget) {
                Label("Show lock screen reminder", systemImage: "calendar")
            }
            .disabled(!enableReminderLiveActivity)

            .settingsHighlight(id: highlightID("Show lock screen reminder"))
            if !enableReminderLiveActivity {
                dependencyLink(
                    "Enable reminders in Calendar settings", tab: .calendar, title: "Enable reminder live activity")
            }
            if enableLockScreenReminderWidget && enableReminderLiveActivity || revealedSection == "reminder" {
                Group {

                    LockScreenSegmentedPicker(
                        "Chip color",
                        selection: $lockScreenReminderChipStyle,
                        items: Array(LockScreenReminderChipStyle.allCases)
                    ) { $0.localizedName }
                    .disabled(!enableLockScreenReminderWidget || !enableReminderLiveActivity)
                    .settingsHighlight(id: highlightID("Chip color"))

                    LockScreenSegmentedPicker(
                        "Alignment",
                        selection: $lockScreenReminderWidgetHorizontalAlignment,
                        items: ReminderAlignmentOption.allCases.map(\.rawValue)
                    ) { ReminderAlignmentOption(rawValue: $0)?.title ?? $0 }
                    .disabled(!enableLockScreenReminderWidget || !enableReminderLiveActivity)
                    .settingsHighlight(id: highlightID("Reminder alignment"))

                    LockScreenSettingRow("Vertical offset") {
                        SettingsSlider(
                            value: $lockScreenReminderWidgetVerticalOffset,
                            in: -160...160,
                            step: 2,
                            valueLabel: Text("\(Int(lockScreenReminderWidgetVerticalOffset)) px")
                        )
                        .disabled(!enableLockScreenReminderWidget || !enableReminderLiveActivity)
                    }
                    .settingsHighlight(id: highlightID("Reminder vertical offset"))

                }
                .disabled(!(enableLockScreenReminderWidget && enableReminderLiveActivity))
            }
        } header: {
            Text("Reminder Widget")
        } footer: {
            Text("Controls the lock screen reminder chip and its positioning.")
        }
    }

}

extension LockScreenSettings {
    private func enforceLockScreenGlassConsistency() {
        if lockScreenGlassStyle == .frosted && lockScreenGlassCustomizationMode != .standard {
            lockScreenGlassCustomizationMode = .standard
        }
        if lockScreenGlassCustomizationMode == .customLiquid && lockScreenGlassStyle != .liquid {
            lockScreenGlassStyle = .liquid
        }
    }

    private var blurSettingUnavailableRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Enable media panel blur", systemImage: "music.note")
                .foregroundStyle(.secondary)
            Text("Only available when Material is set to Frosted Glass.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func variantSlider(
        title: String,
        value: Binding<Double>,
        currentValue: Int,
        isEnabled: Bool,
        highlight: String,
        preview: AnyView? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LockScreenSettingRow(LocalizedStringKey(title)) {
                SettingsSlider(value: value, in: liquidVariantRange, step: 1, valueLabel: Text("v\(currentValue)"))
                    .accessibilityLabel(Text(LocalizedStringKey(title)))
            }

            if let preview {
                preview
                    .frame(maxWidth: 360)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 6)
            }
        }
        .settingsHighlight(id: highlight)
        .disabled(!isEnabled)

    }
}

private struct LockScreenSettingRow<Control: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var control: () -> Control

    init(_ title: LocalizedStringKey, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.control = control
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                Text(title).fixedSize()
                Spacer(minLength: 12)
                control().fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                HStack {
                    Spacer(minLength: 0)
                    control()
                }
            }
        }
    }
}

private struct LockScreenSegmentedPicker<Item: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Item
    let items: [Item]
    let label: (Item) -> String

    init(_ title: LocalizedStringKey, selection: Binding<Item>, items: [Item], label: @escaping (Item) -> String) {
        self.title = title
        self._selection = selection
        self.items = items
        self.label = label
    }

    var body: some View {
        LockScreenSettingRow(title) {
            SettingsSegmentedControl(items: items, selection: $selection, label: label)
        }
    }
}

private struct LockScreenGlassVariantPreviewCell: View {
    @Binding var variant: LiquidGlassVariant

    private let cornerRadius: CGFloat = 16
    private let previewCornerRadius: CGFloat = 14
    private let previewSize = CGSize(width: 190, height: 96)

    var body: some View {
        ZStack {
            Image("glassdesktop")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            liquidGlassPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.vertical, 6)
        .allowsHitTesting(false)
        .onAppear {
            Logger.log("Lock screen glass preview appeared (variant v\(variant.rawValue))", category: .performance)
        }
        .onDisappear {
            Logger.log("Lock screen glass preview disappeared", category: .performance)
        }
        .onChange(of: variant) { _, newValue in
            Logger.log("Lock screen glass preview variant changed to v\(newValue.rawValue)", category: .performance)
        }
    }

    private var liquidGlassPreview: some View {
        LiquidGlassBackground(
            variant: variant,
            cornerRadius: previewCornerRadius
        ) {
            Color.white.opacity(0.04)
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 6)
    }
}

private struct LockScreenPositioningControls: View {
    @Default(.lockScreenWeatherVerticalOffset) private var weatherOffset
    @Default(.lockScreenMusicVerticalOffset) private var musicOffset
    @Default(.lockScreenTimerVerticalOffset) private var timerOffset
    @Default(.lockScreenMusicPanelWidth) private var musicWidth
    @Default(.lockScreenTimerWidgetWidth) private var timerWidth
    private let offsetRange: ClosedRange<Double> = -160...160
    // Upper bound sits above the default so the panel can still be widened.
    private let musicWidthRange: ClosedRange<Double> = 320...460
    private let timerWidthRange: ClosedRange<Double> = 320...LockScreenTimerWidget.defaultWidth

    var body: some View {
        Section {
            let weatherBinding = Binding<Double>(
                get: { weatherOffset },
                set: { newValue in
                    let clampedValue = clampOffset(newValue)
                    if weatherOffset != clampedValue {
                        weatherOffset = clampedValue
                    }
                    propagateWeatherOffsetChange(animated: false)
                }
            )

            let timerBinding = Binding<Double>(
                get: { timerOffset },
                set: { newValue in
                    let clampedValue = clampOffset(newValue)
                    if timerOffset != clampedValue {
                        timerOffset = clampedValue
                    }
                    propagateTimerOffsetChange(animated: false)
                }
            )

            let musicBinding = Binding<Double>(
                get: { musicOffset },
                set: { newValue in
                    let clampedValue = clampOffset(newValue)
                    if musicOffset != clampedValue {
                        musicOffset = clampedValue
                    }
                    propagateMusicOffsetChange(animated: false)
                }
            )

            let musicWidthBinding = Binding<Double>(
                get: { musicWidth },
                set: { newValue in
                    let clampedValue = clamp(newValue, within: musicWidthRange)
                    if musicWidth != clampedValue {
                        musicWidth = clampedValue
                        propagateMusicWidthChange(animated: false)
                    }
                }
            )

            let timerWidthBinding = Binding<Double>(
                get: { timerWidth },
                set: { newValue in
                    let clampedValue = clamp(newValue, within: timerWidthRange)
                    if timerWidth != clampedValue {
                        timerWidth = clampedValue
                        propagateTimerWidthChange(animated: false)
                    }
                }
            )

            LockScreenPositioningPreview(
                weatherOffset: weatherBinding,
                timerOffset: timerBinding,
                musicOffset: musicBinding,
                musicWidth: musicWidthBinding,
                timerWidth: timerWidthBinding
            )
            .frame(height: 260)
            .padding(.vertical, 8)

            adjustmentRow(
                title: Text("\(String(localized: "Weather")) Offset"),
                value: weatherBinding,
                range: offsetRange,
                valueLabel: Text("\(formattedPoints(weatherOffset)) pt"),
                resetTitle: String(localized: "Reset Weather"),
                resetAction: resetWeatherOffset
            )

            adjustmentRow(
                title: Text("\(String(localized: "Timer")) Offset"),
                value: timerBinding,
                range: offsetRange,
                valueLabel: Text("\(formattedPoints(timerOffset)) pt"),
                resetTitle: String(localized: "Reset Timer"),
                resetAction: resetTimerOffset
            )

            adjustmentRow(
                title: Text("\(String(localized: "Music")) Offset"),
                value: musicBinding,
                range: offsetRange,
                valueLabel: Text("\(formattedPoints(musicOffset)) pt"),
                resetTitle: String(localized: "Reset Music"),
                resetAction: resetMusicOffset
            )

            adjustmentRow(
                title: Text("Media Panel Width"),
                value: musicWidthBinding,
                range: musicWidthRange,
                valueLabel: Text(formattedWidth(musicWidth)),
                resetTitle: String(localized: "Reset Media Width"),
                resetAction: resetMusicWidth
            )
            .help("Shrinks the lock screen media panel while keeping the expanded view full width.")

            adjustmentRow(
                title: Text("Timer Widget Width"),
                value: timerWidthBinding,
                range: timerWidthRange,
                valueLabel: Text(formattedWidth(timerWidth)),
                resetTitle: String(localized: "Reset Timer Width"),
                resetAction: resetTimerWidth
            )
            .help("Adjusts the lock screen timer widget width without affecting button sizing.")
        } header: {
            Text("Lock Screen Positioning")
        } footer: {
            Text("Drag the previews to adjust vertical placement. Positive values lift the panel; negative values lower it. Use the width sliders below to size the media and timer widgets \u{2014} the media panel can go wider than its default as well as narrower, while the timer stops at its default width. Changes apply instantly while the widgets are visible.")
                .textCase(nil)
        }
    }

    private func clampOffset(_ value: Double) -> Double {
        min(max(value, offsetRange.lowerBound), offsetRange.upperBound)
    }

    private func clamp(_ value: Double, within range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func resetWeatherOffset() {
        weatherOffset = 0
        propagateWeatherOffsetChange(animated: true)
    }

    private func resetTimerOffset() {
        timerOffset = 0
        propagateTimerOffsetChange(animated: true)
    }

    private func resetMusicOffset() {
        musicOffset = 0
        propagateMusicOffsetChange(animated: true)
    }

    private func resetMusicWidth() {
        musicWidth = Double(LockScreenMusicPanel.defaultCollapsedWidth)
        propagateMusicWidthChange(animated: true)
    }

    private func resetTimerWidth() {
        timerWidth = LockScreenTimerWidget.defaultWidth
        propagateTimerWidthChange(animated: true)
    }

    private func propagateWeatherOffsetChange(animated: Bool) {
        Task { @MainActor in
            LockScreenWeatherPanelManager.shared.refreshPositionForOffsets(animated: animated)
        }
    }

    private func propagateTimerOffsetChange(animated: Bool) {
        Task { @MainActor in
            LockScreenTimerWidgetManager.shared.refreshPositionForOffsets(animated: animated)
        }
    }

    private func propagateMusicOffsetChange(animated: Bool) {
        Task { @MainActor in
            LockScreenPanelManager.shared.applyOffsetAdjustment(animated: animated)
        }
    }

    private func propagateMusicWidthChange(animated: Bool) {
        Task { @MainActor in
            LockScreenPanelManager.shared.applyOffsetAdjustment(animated: animated)
        }
    }

    private func propagateTimerWidthChange(animated: Bool) {
        Task { @MainActor in
            LockScreenTimerWidgetPanelManager.shared.refreshPosition(animated: animated)
        }
    }

    private func adjustmentRow(
        title: Text,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueLabel: Text,
        resetTitle: String,
        resetAction: @escaping () -> Void
    ) -> some View {
        let controls = HStack(spacing: 12) {
            SettingsSlider(value: value, in: range, valueLabel: valueLabel)
                .accessibilityLabel(title)
            Button("Reset", action: resetAction)
                .buttonStyle(.bordered)
                .help(resetTitle)
                .accessibilityLabel(Text(resetTitle))
        }
        .fixedSize(horizontal: true, vertical: false)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                title.fixedSize()
                Spacer(minLength: 0)
                controls
            }
            VStack(alignment: .leading, spacing: 8) {
                title
                controls.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func formattedPoints(_ value: Double) -> String {
        String(format: "%+.0f", value)
    }

    private func formattedWidth(_ value: Double) -> String {
        String(format: "%.0f pt", value)
    }
}

private struct LockScreenPositioningPreview: View {
    @Binding var weatherOffset: Double
    @Binding var timerOffset: Double
    @Binding var musicOffset: Double
    @Binding var musicWidth: Double
    @Binding var timerWidth: Double

    @State private var weatherStartOffset: Double = 0
    @State private var timerStartOffset: Double = 0
    @State private var musicStartOffset: Double = 0
    @State private var isWeatherDragging = false
    @State private var isTimerDragging = false
    @State private var isMusicDragging = false

    private let offsetRange: ClosedRange<Double> = -160...160

    var body: some View {
        GeometryReader { geometry in
            let screenPadding: CGFloat = 26
            let screenCornerRadius: CGFloat = 28
            let screenRect = CGRect(
                x: screenPadding,
                y: screenPadding,
                width: geometry.size.width - (screenPadding * 2),
                height: geometry.size.height - (screenPadding * 2)
            )
            let centerX = screenRect.midX
            let weatherBaseY = screenRect.minY + (screenRect.height * 0.28)
            let timerBaseY = screenRect.minY + (screenRect.height * 0.5)
            let musicBaseY = screenRect.minY + (screenRect.height * 0.78)
            let weatherSize = CGSize(width: screenRect.width * 0.42, height: screenRect.height * 0.22)
            let defaultMusicWidth = Double(LockScreenMusicPanel.defaultCollapsedWidth)
            let musicWidthScale = CGFloat(musicWidth / defaultMusicWidth)
            let timerWidthScale = CGFloat(timerWidth / LockScreenTimerWidget.defaultWidth)
            let timerSize = CGSize(
                width: (screenRect.width * 0.5) * timerWidthScale,
                height: screenRect.height * 0.2
            )
            let musicSize = CGSize(
                width: (screenRect.width * 0.56) * musicWidthScale,
                height: screenRect.height * 0.34
            )

            ZStack {
                RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.55))
                    .frame(width: screenRect.width, height: screenRect.height)
                    .overlay(
                        RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 20, x: 0, y: 18)
                    .position(x: screenRect.midX, y: screenRect.midY)

                weatherPanel(size: weatherSize)
                    .position(x: centerX, y: weatherBaseY - CGFloat(weatherOffset))
                    .gesture(weatherDragGesture(in: screenRect, baseY: weatherBaseY))

                timerPanel(size: timerSize)
                    .position(x: centerX, y: timerBaseY - CGFloat(timerOffset))
                    .gesture(timerDragGesture(in: screenRect, baseY: timerBaseY))

                musicPanel(size: musicSize)
                    .position(x: centerX, y: musicBaseY - CGFloat(musicOffset))
                    .gesture(musicDragGesture(in: screenRect, baseY: musicBaseY))
            }
        }
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: weatherOffset)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: musicOffset)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: timerOffset)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: musicWidth)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.82), value: timerWidth)
    }

    private func weatherPanel(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.blue.opacity(0.78), Color.blue.opacity(0.52)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Weather", systemImage: "cloud.sun.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("Inline snapshot preview")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .padding(.horizontal, 16)
            }
            .shadow(color: Color.blue.opacity(0.22), radius: 10, x: 0, y: 8)
    }

    private func musicPanel(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.purple.opacity(0.68), Color.pink.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Media", systemImage: "play.square.stack")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Text("Lock screen panel preview")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .padding(.horizontal, 18)
            }
            .shadow(color: Color.purple.opacity(0.24), radius: 12, x: 0, y: 9)
    }

    private func timerPanel(size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.orange.opacity(0.75), Color.purple.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay {
                VStack(spacing: 6) {
                    Text("Timer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("00:05:00")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
            .shadow(color: Color.orange.opacity(0.3), radius: 12, x: 0, y: 8)
    }

    private func weatherDragGesture(in screenRect: CGRect, baseY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isWeatherDragging {
                    isWeatherDragging = true
                    weatherStartOffset = weatherOffset
                }

                let proposed = weatherStartOffset - Double(value.translation.height)
                weatherOffset = clampedOffset(
                    proposed,
                    baseCenterY: baseY,
                    screenRect: screenRect
                )
            }
            .onEnded { _ in
                isWeatherDragging = false
            }
    }

    private func musicDragGesture(in screenRect: CGRect, baseY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isMusicDragging {
                    isMusicDragging = true
                    musicStartOffset = musicOffset
                }

                let proposed = musicStartOffset - Double(value.translation.height)
                musicOffset = clampedOffset(
                    proposed,
                    baseCenterY: baseY,
                    screenRect: screenRect
                )
            }
            .onEnded { _ in
                isMusicDragging = false
            }
    }

    private func timerDragGesture(in screenRect: CGRect, baseY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isTimerDragging {
                    isTimerDragging = true
                    timerStartOffset = timerOffset
                }

                let proposed = timerStartOffset - Double(value.translation.height)
                timerOffset = clampedOffset(
                    proposed,
                    baseCenterY: baseY,
                    screenRect: screenRect
                )
            }
            .onEnded { _ in
                isTimerDragging = false
            }
    }

    private func clampedOffset(
        _ proposed: Double,
        baseCenterY: CGFloat,
        screenRect: CGRect
    ) -> Double {
        // Keep the widget's centre on screen rather than the whole of it.
        //
        // These boxes are rough stand-ins, and the music one is drawn at 34% of
        // the screen height where the real panel is nearer 18% (180pt). Holding
        // the whole box inside the screen therefore clamped against a size the
        // panel does not have: the music widget sits at 78% of the height, so
        // it ran out of travel about 10pt down, well short of the +/-160pt the
        // setting itself allows. Letting a widget overhang the edge it is being
        // pushed towards costs nothing -- the outer clamp below is still the
        // real limit -- and it is honest, since the panel can be positioned
        // past the visible area at runtime too.
        let minCenterY = screenRect.minY
        let maxCenterY = screenRect.maxY
        let proposedCenter = baseCenterY - CGFloat(proposed)
        let clampedCenter = min(max(proposedCenter, minCenterY), maxCenterY)
        let derivedOffset = Double(baseCenterY - clampedCenter)
        return min(max(derivedOffset, offsetRange.lowerBound), offsetRange.upperBound)
    }
}

private func copyLatestCrashReport() {
    let crashReportsPath = NSString(string: "~/Library/Logs/DiagnosticReports").expandingTildeInPath
    let fileManager = FileManager.default

    do {
        let files = try fileManager.contentsOfDirectory(atPath: crashReportsPath)
        let crashFiles = files.filter { $0.contains("DynamicIsland") && $0.hasSuffix(".crash") }

        guard let latestCrash = crashFiles.sorted(by: >).first else {
            let alert = NSAlert()
            alert.messageText = String(localized: "No Crash Reports Found")
            alert.informativeText = String(localized: "No crash reports found for DynamicIsland")
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        let crashPath = (crashReportsPath as NSString).appendingPathComponent(latestCrash)
        let crashContent = try String(contentsOfFile: crashPath, encoding: .utf8)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(crashContent, forType: .string)

        let alert = NSAlert()
        alert.messageText = String(localized: "Crash Report Copied")
        alert.informativeText = String(localized: "Crash report '\(latestCrash)' has been copied to clipboard")
        alert.alertStyle = .informational
        alert.runModal()
    } catch {
        let alert = NSAlert()
        alert.messageText = String(localized: "Error")
        alert.informativeText = String(localized: "Failed to read crash reports: \(error.localizedDescription)")
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct ScreenTextSettings: View {
    @Default(.enableScreenText) private var enableScreenText
    @AppStorage("screenOCRRemoveLineBreaks") private var removeLineBreaks = false
    @AppStorage("screenOCRDetectQRCodes") private var detectQRCodes = true
    @Default(.enableShortcuts) private var enableShortcuts
    @State private var screenRecordingAllowed = CGPreflightScreenCaptureAccess()
    @AppStorage("screenRecordingPermissionRequested") private var permissionRequested = false

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableScreenText) {
                    Label("Enable copy text from screen", systemImage: "textformat")
                }
                    .settingsHighlight(id: SettingsTab.screenText.highlightID(for: "Enable copy text from screen"))
            }

            Section {
                SettingsPermissionRow(title: "Screen Recording", message: "Allows capturing the selected area. Text and QR codes are recognized offline.",
                                      state: screenRecordingAllowed ? .granted : (permissionRequested ? .denied : .notDetermined),
                                      request: {
                    permissionRequested = true
                    screenRecordingAllowed = CGRequestScreenCaptureAccess()
                }, openSettings: { openPermissionSettings("ScreenCapture") })
            } header: { Text("Screen Recording") } footer: {
                Text("Allow screen recording to capture the selected area. Text and QR codes are recognized offline.")
            }

            Section {
                HStack {
                    Label("Copy text from screen", systemImage: "text.viewfinder")
                    Spacer()
                    Button("Copy text from screen") { ScreenTextManager.shared.capture() }
                        .disabled(!enableScreenText)
                }
            } footer: {
                Text("Select an area on any display. Recognized text is copied so you can paste it anywhere.")
            }
            .settingsHighlight(id: SettingsTab.screenText.highlightID(for: "Copy text from screen"))

            Section {
                Toggle(isOn: $removeLineBreaks) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Remove line breaks")
                        Text("Join recognized lines into one paragraph. Chinese text is joined without extra spaces.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $detectQRCodes) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Read QR codes")
                        Text("When a QR code is found, show its contents for copying or opening. Otherwise, recognize text.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Recognition") }
            .disabled(!enableScreenText)

            Section {
                KeyboardShortcuts.Recorder("Copy text from screen:", name: .copyScreenText)
                    .disabled(!enableShortcuts || !enableScreenText)
            } header: { Text("Shortcuts") } footer: {
                if !enableShortcuts {
                    Text("Enable global keyboard shortcuts in Shortcuts settings to use this binding.")
                }
            }
        }

        .onAppear { screenRecordingAllowed = CGPreflightScreenCaptureAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screenRecordingAllowed = CGPreflightScreenCaptureAccess()
        }
    }
}

struct Shortcuts: View {
    @ObservedObject private var clipboardStore = ClipboardHistoryStore.shared
    @Default(.enableScreenText) private var enableScreenText
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableShortcuts) var enableShortcuts
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.enableCaffeinate) var enableCaffeinateFeature

    private func highlightID(_ title: String) -> String {
        SettingsTab.shortcuts.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableShortcuts) {
                    Label("Enable global keyboard shortcuts", systemImage: "keyboard")
                }
                .settingsHighlight(id: highlightID("Enable global keyboard shortcuts"))
            } header: {
                Text("General")
            } footer: {
                Text("When disabled, all keyboard shortcuts will be inactive. You can still use the UI controls.")
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section {
                shortcutRow("Copy text from screen:", systemImage: "text.viewfinder", name: .copyScreenText)
                    .disabled(!enableShortcuts || !enableScreenText)
            } header: {
                Text("Screen Text")
            } footer: {
                Text("Configure recognition options in Utilities → Copy text from screen.")
            }
            .settingsHighlight(id: highlightID("Screen Text"))

            Section("Clipboard") {
                shortcutRow("Open Clipboard:", systemImage: "doc.on.clipboard", name: .toggleClipboard)
                    .disabled(!enableShortcuts || !clipboardStore.enabled)
                Button { ClipboardPanelController.shared.toggle() } label: {
                    Label("Open Clipboard", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .disabled(!clipboardStore.enabled)
            }

            Group {
                Section {
                    shortcutRow("Toggle Sneak Peek:", systemImage: "music.note", name: .toggleSneakPeek)
                        .disabled(!enableShortcuts)
                } header: {
                    Text("Media")
                } footer: {
                    Text("Sneak Peek shows the media title and artist under the notch for a few seconds.")
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                Section {
                    VStack(alignment: .leading) {
                        shortcutRow("Toggle Keep Awake:", systemImage: "cup.and.saucer", name: .toggleCaffeinate)
                            .disabled(!enableShortcuts || !enableCaffeinateFeature)
                        if !enableCaffeinateFeature {
                            Text("Keep Awake is disabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }
                } header: {
                    Text("Keep Awake")
                } footer: {
                    Text("Starts the default duration set in General, or ends a running session.")
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                Section {
                    shortcutRow("Toggle Notch Open:", systemImage: "rectangle.topthird.inset.filled", name: .toggleNotchOpen)
                        .disabled(!enableShortcuts)
                    shortcutRow("Open Monitoring:", systemImage: "gauge.with.dots.needle.33percent", name: .openMonitoring)
                        .disabled(!enableStatsFeature)
                } header: {
                    Text("Navigation")
                } footer: {
                    Text("Toggle the Dynamic Island open or closed from anywhere.")
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        shortcutRow("Start Demo Timer:", systemImage: "timer", name: .startDemoTimer)
                            .disabled(!enableShortcuts || !enableTimerFeature)
                        if !enableTimerFeature {
                            Text("Timer feature is disabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }
                } header: {
                    Text("Timer")
                } footer: {
                    Text("Starts a 5-minute demo timer to test the timer live activity feature. Only works when timer feature is enabled.")
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        shortcutRow("Toggle Terminal Tab:", systemImage: "terminal", name: .toggleTerminalTab)
                            .disabled(!enableShortcuts || !Defaults[.enableTerminalFeature])
                        if !Defaults[.enableTerminalFeature] {
                            Text("Terminal feature is disabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }
                } header: {
                    Text("Terminal")
                } footer: {
                    Text("Opens the terminal tab in the notch. Default is Ctrl+`. Only works when terminal feature is enabled.")
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .disabled(!enableShortcuts)
        }
        .navigationTitle("Shortcuts")
    }

    private func shortcutRow(_ title: LocalizedStringKey, systemImage: String,
                             name: KeyboardShortcuts.Name) -> some View {
        HStack(spacing: 16) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 12)
            SettingsShortcutButton(title: title, name: name)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct SettingsShortcutButton: View {
    let title: LocalizedStringKey
    let name: KeyboardShortcuts.Name
    @Environment(\.isEnabled) private var isEnabled
    @State private var isPresented = false
    @State private var shortcut: KeyboardShortcuts.Shortcut?

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 12) {
                if let shortcut {
                    Text(shortcut.description)
                        .font(.system(.body, design: .rounded).weight(.medium))
                } else {
                    Text("Set Shortcut")
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(width: 190, height: 34)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(shortcut?.description ?? String(localized: "Set Shortcut"))
        .onAppear { refreshShortcut() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            refreshShortcut()
        }
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Record Shortcut").font(.headline)
                        Text(title).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Close"))
                }

                SettingsShortcutRecorder(name: name) { shortcut = $0 }
                    .frame(height: 28)
                    .padding(22)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .allowsHitTesting(false)
                    }
                    .accessibilityLabel(Text(title))

                Text("Click the field to record. Esc stops recording; Delete clears the shortcut. Changes save automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Restore Defaults") {
                        KeyboardShortcuts.reset(name)
                        refreshShortcut()
                    }
                    Button("Clear") {
                        KeyboardShortcuts.setShortcut(nil, for: name)
                        refreshShortcut()
                    }
                    Spacer()
                    Button("Done") { isPresented = false }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.regular)
            }
            .padding(20)
            .frame(width: 360)
        }
    }

    private func refreshShortcut() {
        shortcut = KeyboardShortcuts.getShortcut(for: name)
    }
}

private struct SettingsShortcutRecorder: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    let onChange: (KeyboardShortcuts.Shortcut?) -> Void

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let recorder = KeyboardShortcuts.RecorderCocoa(for: name, onChange: onChange)
        recorder.isBezeled = false
        recorder.drawsBackground = false
        recorder.font = .monospacedSystemFont(ofSize: 18, weight: .medium)
        DispatchQueue.main.async { [weak recorder] in
            guard let recorder else { return }
            recorder.window?.makeFirstResponder(recorder)
        }
        return recorder
    }

    func updateNSView(_ recorder: KeyboardShortcuts.RecorderCocoa, context: Context) {
        recorder.shortcutName = name
    }
}

func proFeatureBadge() -> some View {
    Text("Upgrade to Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(LocalizedStringKey(text))
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func alphaBadge() -> some View {
    Text("ALPHA")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.9))
        )
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct TimerSettings: View {
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.timerPresets) private var timerPresets
    @Default(.timerIconColorMode) private var colorMode
    @Default(.timerSolidColor) private var solidColor
    @Default(.timerShowsCountdown) private var showsCountdown
    @Default(.timerShowsLabel) private var showsLabel
    @Default(.timerShowsProgress) private var showsProgress
    @Default(.timerProgressStyle) private var progressStyle
    @Default(.showTimerPresetsInNotchTab) private var showTimerPresetsInNotchTab
    @Default(.timerControlWindowEnabled) private var controlWindowEnabled
    @Default(.mirrorSystemTimer) private var mirrorSystemTimer
    @Default(.timerDisplayMode) private var timerDisplayMode
    @Default(.timerInputStyle) private var timerInputStyle
    @Default(.enableLockScreenTimerWidget) private var enableLockScreenTimerWidget
    @Default(.lockScreenTimerGlassStyle) private var lockScreenTimerGlassStyle
    @Default(.lockScreenTimerGlassCustomizationMode) private var lockScreenTimerGlassCustomizationMode
    @Default(.lockScreenTimerLiquidGlassVariant) private var lockScreenTimerLiquidGlassVariant
    @AppStorage("customTimerDuration") private var customTimerDuration: Double = 600
    @State private var customHours: Int = 0
    @State private var customMinutes: Int = 10
    @State private var customSeconds: Int = 0
    @State private var showingResetConfirmation = false

    private func highlightID(_ title: String) -> String {
        SettingsTab.timer.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableTimerFeature) {
                    Label("Enable timer", systemImage: "clock")
                }
                .settingsHighlight(id: highlightID("Enable timer"))
            }

            Section("Permissions") {
                AccessibilitySettingsPermissionRow(message: "Allows reading macOS Clock timers for timer mirroring.")
            }

            Group {
                timerFeatureSection
                timerConfigurationSections
            }
            .disabled(!enableTimerFeature)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                TimerSettingsPreview()
            }
            .frame(maxWidth: 900)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
        .navigationTitle("Timer")
        .onAppear { syncCustomDuration() }
        .onChange(of: customTimerDuration) { _, newValue in syncCustomDuration(newValue) }
    }

    @ViewBuilder
    private var timerFeatureSection: some View {
        Section {

            Group {
                Toggle("Enable timer live activity", systemImage: "clock", isOn: $coordinator.timerLiveActivityEnabled)
                    .animation(.easeInOut, value: coordinator.timerLiveActivityEnabled)
                Defaults.Toggle(key: .mirrorSystemTimer) {
                    HStack(spacing: 8) {
                        Label("Mirror macOS Clock timers", systemImage: "clock")
                        alphaBadge()
                    }
                }
                .help("Shows the system Clock timer in the notch when available. Requires Accessibility permission to read the status item.")
                .settingsHighlight(id: highlightID("Mirror macOS Clock timers"))

                SettingsSegmentedPicker(
                    "Timer controls appear as",
                    selection: $timerDisplayMode,
                    items: Array(TimerDisplayMode.allCases)
                ) { $0.displayName }
                .help(timerDisplayMode.description)
                .settingsHighlight(id: highlightID("Timer controls appear as"))
            }
            .disabled(!enableTimerFeature)
        } header: {
            Text("Timer Feature")
        } footer: {
            Text("Control timer availability, live activity behaviour, and whether the app mirrors timers started from the macOS Clock app.")
        }
    }

    @ViewBuilder
    private var timerConfigurationSections: some View {
        Group {
            lockScreenIntegrationSection
            customTimerSection
            appearanceSection
            timerPresetsSection
            timerSoundSection
        }
    }

    @ViewBuilder
    private var lockScreenIntegrationSection: some View {
        Section("Lock Screen Integration") {
            LockScreenSettingsLink(title: "Show lock screen timer")
        }
    }

    @ViewBuilder
    private var customTimerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Default Custom Timer")
                    .font(.headline)

                TimerDurationSliderRow(title: String(localized: "Hours"), value: $customHours, range: 0...23)
                TimerDurationSliderRow(title: String(localized: "Minutes"), value: $customMinutes, range: 0...59)
                TimerDurationSliderRow(title: String(localized: "Seconds"), value: $customSeconds, range: 0...59)

                HStack {
                    Text("Current default:")
                        .foregroundStyle(.secondary)
                    Text(customDurationDisplay)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    Spacer()
                }
            }
            .padding(.vertical, 4)
            .onChange(of: customHours) { _, _ in updateCustomDuration() }
            .onChange(of: customMinutes) { _, _ in updateCustomDuration() }
            .onChange(of: customSeconds) { _, _ in updateCustomDuration() }
        } header: {
            Text("Custom Timer")
        } footer: {
            Text("This duration powers the \"Custom\" option inside the timer popover for quick access.")
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            SettingsSegmentedPicker(
                "Timer tint",
                selection: $colorMode,
                items: Array(TimerIconColorMode.allCases)
            ) { $0.displayName }
            .settingsHighlight(id: highlightID("Timer tint"))

            if colorMode == .solid {
                HStack(spacing: 12) {
                    Label("Solid colour", systemImage: "paintpalette").accessibilityHidden(true)
                    Spacer(minLength: 12)
                    ColorPicker(selection: $solidColor, supportsOpacity: false) { Label("Solid colour", systemImage: "paintpalette") }
                        .labelsHidden()
                }
                    .settingsHighlight(id: highlightID("Solid colour"))
            }

            SettingsSegmentedPicker(
                "Custom timer style",
                selection: $timerInputStyle,
                items: Array(TimerInputStyle.allCases)
            ) { $0.displayName }
            .settingsHighlight(id: highlightID("Custom timer style"))

            Toggle("Show timer name", systemImage: "clock", isOn: $showsLabel)
            Toggle("Show countdown", systemImage: "power", isOn: $showsCountdown)
            Toggle("Show progress", systemImage: "power", isOn: $showsProgress)
            Toggle("Show preset list in timer tab", systemImage: "clock", isOn: $showTimerPresetsInNotchTab)
                .settingsHighlight(id: highlightID("Show preset list in timer tab"))

            Toggle("Show pause/stop controls in the notch", systemImage: "power", isOn: $controlWindowEnabled)
                .help("Pause and stop buttons appear inline inside the notch while a timer runs.")
                .settingsHighlight(id: highlightID("Show pause/stop controls in the notch"))

            SettingsSegmentedPicker(
                "Progress style",
                selection: $progressStyle,
                items: Array(TimerProgressStyle.allCases)
            ) { $0.localizedName }
            .disabled(!showsProgress)
            .settingsHighlight(id: highlightID("Progress style"))
        } header: {
            Text("Appearance")
        } footer: {
            Text("Configure how the timer looks inside the closed notch. Progress can render as a ring around the icon or as horizontal bars.")
        }
    }

    @ViewBuilder
    private var timerPresetsSection: some View {
        Section {
            if timerPresets.isEmpty {
                Text("No presets configured. Add a preset to make it appear in the timer popover.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                TimerPresetListView(
                    presets: $timerPresets,
                    highlightProvider: highlightID,
                    moveUp: movePresetUp,
                    moveDown: movePresetDown,
                    remove: removePreset
                )
            }

            HStack {
                Button(action: addPreset) {
                    Label("Add Preset", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(role: .destructive, action: { showingResetConfirmation = true }) {
                    Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .confirmationDialog("Restore default timer presets?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                    Button("Restore", role: .destructive, action: resetPresets)
                }
            }
        } header: {
            Text("Timer Presets")
        } footer: {
            Text("Presets show up inside the timer popover with the configured name, duration, and accent colour. Reorder them to change the display order.")
        }
    }

    @ViewBuilder
    private var timerSoundSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Timer Sound")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    Button("Choose File", action: selectCustomTimerSound)
                        .buttonStyle(.bordered)
                }

                if let customTimerSoundPath = UserDefaults.standard.string(forKey: "customTimerSoundPath") {
                    Text("Custom: \(URL(fileURLWithPath: customTimerSoundPath).lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Default: dynamic.m4a")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Reset to Default") {
                    UserDefaults.standard.removeObject(forKey: "customTimerSoundPath")
                }
                .buttonStyle(.bordered)
                .disabled(UserDefaults.standard.string(forKey: "customTimerSoundPath") == nil)
            }
        } header: {
            Text("Timer Sound")
        } footer: {
            Text("Select a custom sound to play when a timer ends. Supported formats include MP3, M4A, WAV, and AIFF.")
        }
    }

    private var customDurationDisplay: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = customTimerDuration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: customTimerDuration) ?? "0:00"
    }

    private func syncCustomDuration(_ value: Double? = nil) {
        let baseValue = value ?? customTimerDuration
        let components = TimerPreset.components(for: baseValue)
        customHours = components.hours
        customMinutes = components.minutes
        customSeconds = components.seconds
    }

    private func updateCustomDuration() {
        let duration = TimeInterval(customHours * 3600 + customMinutes * 60 + customSeconds)
        customTimerDuration = duration
    }

    private func addPreset() {
        let nextIndex = timerPresets.count + 1
        let defaultColor = Defaults[.accentColor]
        let newPreset = TimerPreset(name: "Preset \(nextIndex)", duration: 5 * 60, color: defaultColor)
        _ = withAnimation(.smooth) {
            timerPresets.append(newPreset)
        }
    }

    private func movePresetUp(_ index: Int) {
        guard index > timerPresets.startIndex else { return }
        _ = withAnimation(.smooth) {
            timerPresets.swapAt(index, index - 1)
        }
    }

    private func movePresetDown(_ index: Int) {
        guard index < timerPresets.index(before: timerPresets.endIndex) else { return }
        _ = withAnimation(.smooth) {
            timerPresets.swapAt(index, index + 1)
        }
    }

    private func removePreset(_ index: Int) {
        guard timerPresets.indices.contains(index) else { return }
        _ = withAnimation(.smooth) {
            timerPresets.remove(at: index)
        }
    }

    private func resetPresets() {
        _ = withAnimation(.smooth) {
            timerPresets = TimerPreset.defaultPresets
        }
    }

    private func selectCustomTimerSound() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Select Timer Sound")
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            if let url = panel.url {
                UserDefaults.standard.set(url.path, forKey: "customTimerSoundPath")
            }
        }
    }
}

private struct TimerDurationSliderRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        SettingsSlider(
            value: Binding(
                get: { Double(value) },
                set: { value = Int($0.rounded()) }
            ),
            in: Double(range.lowerBound)...Double(range.upperBound),
            step: 1,
            valueLabel: Text("\(value)")
        ) {
            Text(title)
        }
    }
}

private struct TimerPresetListView: View {
    @Binding var presets: [TimerPreset]
    let highlightProvider: (String) -> String
    let moveUp: (Int) -> Void
    let moveDown: (Int) -> Void
    let remove: (Int) -> Void

    var body: some View {
        ForEach(presets.indices, id: \.self) { index in
            presetRow(at: index)
        }
    }

    @ViewBuilder
    private func presetRow(at index: Int) -> some View {
        TimerPresetEditorRow(
            preset: $presets[index],
            isFirst: index == presets.startIndex,
            isLast: index == presets.index(before: presets.endIndex),
            highlightID: highlightID(for: index),
            moveUp: { moveUp(index) },
            moveDown: { moveDown(index) },
            remove: { remove(index) }
        )
    }

    private func highlightID(for index: Int) -> String? {
        index == presets.startIndex ? highlightProvider("Accent colour") : nil
    }
}

private struct TimerPresetEditorRow: View {
    @Binding var preset: TimerPreset
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void
    let highlightID: String?

    init(
        preset: Binding<TimerPreset>,
        isFirst: Bool,
        isLast: Bool,
        highlightID: String? = nil,
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void,
        remove: @escaping () -> Void
    ) {
        _preset = preset
        self.isFirst = isFirst
        self.isLast = isLast
        self.highlightID = highlightID
        self.moveUp = moveUp
        self.moveDown = moveDown
        self.remove = remove
    }

    private var components: TimerPreset.DurationComponents {
        TimerPreset.components(for: preset.duration)
    }

    private var hoursBinding: Binding<Int> {
        Binding(
            get: { components.hours },
            set: { updateDuration(hours: $0) }
        )
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { components.minutes },
            set: { updateDuration(minutes: $0) }
        )
    }

    private var secondsBinding: Binding<Int> {
        Binding(
            get: { components.seconds },
            set: { updateDuration(seconds: $0) }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { preset.color },
            set: { preset.updateColor($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(preset.color.gradient)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )

                TextField("Preset name", text: $preset.name)
                    .textFieldStyle(.roundedBorder)

                Spacer()

                Text(preset.formattedDuration)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                TimerDurationSliderRow(title: String(localized: "Hours"), value: hoursBinding, range: 0...23)
                TimerDurationSliderRow(title: String(localized: "Minutes"), value: minutesBinding, range: 0...59)
                TimerDurationSliderRow(title: String(localized: "Seconds"), value: secondsBinding, range: 0...59)
            }

            HStack(spacing: 12) {
                Label("Accent colour", systemImage: "paintpalette").accessibilityHidden(true)
                Spacer(minLength: 12)
                ColorPicker(selection: colorBinding, supportsOpacity: false) { Label("Accent colour", systemImage: "paintpalette") }
                    .labelsHidden()
            }
                .frame(maxWidth: 240, alignment: .leading)

            HStack(spacing: 12) {
                Button(action: moveUp) {
                    Label("Move Up", systemImage: "chevron.up")
                }
                .buttonStyle(.bordered)
                .disabled(isFirst)

                Button(action: moveDown) {
                    Label("Move Down", systemImage: "chevron.down")
                }
                .buttonStyle(.bordered)
                .disabled(isLast)

                Spacer()

                Button(role: .destructive, action: remove) {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .padding(.vertical, 6)
        .settingsHighlightIfPresent(highlightID)
    }

    private func updateDuration(hours: Int? = nil, minutes: Int? = nil, seconds: Int? = nil) {
        var values = components
        if let hours { values.hours = hours }
        if let minutes { values.minutes = minutes }
        if let seconds { values.seconds = seconds }
        preset.duration = TimerPreset.duration(from: values)
    }
}

struct StatsSettings: View {
    @ObservedObject private var manager = StatsManager.shared
    @Default(.enableStatsFeature) private var enabled
    @Default(.statsModuleOrder) private var moduleOrder
    @Default(.cpuTemperatureUnit) private var temperatureUnit

    private var modules: [MonitoringModule] { MonitoringModule.ordered(moduleOrder) }
    private let moduleTitles: [MonitoringModule: String] = [
        .cpu: "CPU Usage", .memory: "Memory Usage", .gpu: "GPU Usage",
        .disk: "Disk I/O", .network: "Network Activity", .sensors: "Sensors"
    ]

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableStatsFeature) { Label("Enable system stats monitoring", systemImage: "display") }
                    .settingsHighlight(id: SettingsTab.stats.highlightID(for: "Enable system stats monitoring"))
            }
            Section("Optional Permissions") {
                LocationSettingsPermissionRow(message: "Optional. Allows displaying the current Wi-Fi network name.")
                NotificationsSettingsPermissionRow()
            }
            Group {
                Section("Monitoring Behavior") {
                    Defaults.Toggle(key: .statsStopWhenNotchCloses) { Label("Stop monitoring after closing the notch", systemImage: "display") }
                        .settingsHighlight(id: SettingsTab.stats.highlightID(for: "Stop monitoring after closing the notch"))
                    Text("Only enabled modules are sampled. Process details are collected while their detail view is open.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Modules") {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(modules) { module in
                                let title = moduleTitles[module] ?? module.title
                                VStack(spacing: 8) {
                                    MonitoringWidgetPreview(widgets: module.widgets)
                                        .opacity(manager.enabledModules.contains(module) ? 1 : 0.35)
                                    Defaults.Toggle(key: module.visibilityKey) { Label(LocalizedStringKey(title), systemImage: "gauge.with.dots.needle.33percent") }
                                        .toggleStyle(.checkbox)
                                        .font(.caption)
                                }
                                .padding(4)
                                .contentShape(Rectangle())
                                .draggable("eave-monitoring:" + module.rawValue)
                                .dropDestination(for: String.self) { items, _ in
                                    guard items.count == 1,
                                          let source = modules.first(where: { "eave-monitoring:" + $0.rawValue == items[0] }) else { return false }
                                    withAnimation {
                                        moduleOrder = MonitoringModule.moving(source, to: module, in: moduleOrder)
                                    }
                                    return true
                                }
                                .accessibilityAction(named: Text("Move Up")) {
                                    if let index = modules.firstIndex(of: module), index > 0 {
                                        moduleOrder = MonitoringModule.moving(module, to: modules[index - 1], in: moduleOrder)
                                    }
                                }
                                .accessibilityAction(named: Text("Move Down")) {
                                    if let index = modules.firstIndex(of: module), index + 1 < modules.count {
                                        moduleOrder = MonitoringModule.moving(module, to: modules[index + 1], in: moduleOrder)
                                    }
                                }
                                .settingsHighlight(id: SettingsTab.stats.highlightID(for: title))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    SettingsSegmentedPicker("Temperature unit", selection: $temperatureUnit,
                                            items: Array(LockScreenWeatherTemperatureUnit.allCases)) { $0.localizedName }
                        .settingsHighlight(id: SettingsTab.stats.highlightID(for: "Temperature unit"))
                }
                Section("CPU") {
                    Defaults.Toggle(key: .showCPUWidgetWhenClosed) { Label("Show CPU widget when collapsed", systemImage: "power") }
                        .settingsHighlight(id: SettingsTab.stats.highlightID(for: "Show CPU widget when collapsed"))
                    Button("CPU settings…") { manager.cpu.showSettings() }
                }
                Section("GPU") {
                    Defaults.Toggle(key: .showGPUWidgetWhenClosed) { Label("Show GPU widget when collapsed", systemImage: "power") }
                        .settingsHighlight(id: SettingsTab.stats.highlightID(for: "Show GPU widget when collapsed"))
                    Button("GPU settings…") { manager.gpu.showSettings() }
                }
                Section("Memory") {
                    Defaults.Toggle(key: .showMemoryWidgetWhenClosed) { Label("Show memory widget when collapsed", systemImage: "power") }
                        .settingsHighlight(id: SettingsTab.stats.highlightID(for: "Show memory widget when collapsed"))
                    Button("Memory settings…") { manager.memory.showSettings() }
                }
                Section("Disk") {
                    Defaults.Toggle(key: .showDiskWidgetWhenClosed) { Label("Show disk widget when collapsed", systemImage: "power") }
                        .settingsHighlight(id: SettingsTab.stats.highlightID(for: "Show disk widget when collapsed"))
                    Button("Disk settings…") { manager.disk.showSettings() }
                }
                Section("Network") {
                    Defaults.Toggle(key: .showNetworkWidgetWhenClosed) { Label("Show network widget when collapsed", systemImage: "wifi") }
                        .settingsHighlight(id: SettingsTab.stats.highlightID(for: "Show network widget when collapsed"))
                    Button("Network settings…") { manager.network.showSettings() }
                }
                Section("Sensors") {
                    Defaults.Toggle(key: .showSensorsWidgetWhenClosed) { Label("Show sensor widget when collapsed", systemImage: "power") }
                        .settingsHighlight(id: SettingsTab.stats.highlightID(for: "Show sensor widget when collapsed"))
                    Button("Sensor settings…") { manager.sensors.showSettings() }
                }
                Section("Monitoring Status") {
                    LabeledContent("Status", value: (manager.isMonitoring || manager.network.isEnabled || manager.cpu.isEnabled || manager.gpu.isEnabled || manager.memory.isEnabled || manager.disk.isEnabled || manager.sensors.isEnabled) ? String(localized: "Active") : String(localized: "Stopped"))
                    ForEach(manager.enabledModules) { module in
                        LabeledContent(module.title, value: module == .network
                                       ? manager.network.formattedSpeed(manager.samples[module]?.value ?? 0)
                                       : module == .disk ? manager.disk.formattedSpeed(manager.samples[module]?.value ?? 0)
                                       : module.unit.string(manager.samples[module]?.value, fahrenheit: temperatureUnit == .fahrenheit))
                    }
                    if let date = manager.lastUpdated {
                        HStack { Label("Last Updated", systemImage: "clock"); Spacer(); Text(date, style: .time).foregroundStyle(.secondary) }
                    }
                    Button("Clear Data") { manager.clearHistory() }
                        .disabled(manager.isMonitoring)
                }
            }
            .disabled(!enabled)
        }
        .navigationTitle("Monitoring")
    }
}

struct LLMAgentsSettings: View {
    @Default(.enableLLMUsageFeature) var enableLLMUsageFeature
    @Default(.enableNewAPIProvider) var enableNewAPIProvider
    @State private var newAPIAccounts = Defaults[.newAPIAccounts]
    @State private var isNewAPIEditorPresented = false
    @State private var editingNewAPIAccount: NewAPIAccount?
    @State private var accountPendingDeletion: NewAPIAccount?
    @State private var newAPIAccountErrorMessage: String?

    private func highlightID(_ title: String) -> String {
        SettingsTab.llmAgents.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableLLMUsageFeature) {
                    Label("Enable LLM Usage Monitor", systemImage: "display")
                }
                .settingsHighlight(id: highlightID("Enable LLM Usage Monitor"))
            } header: {
                Text("General")
            } footer: {
                Text("Enabling LLM Usage Monitor adds a Usage tab that tracks token usage and spend across your configured AI providers.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Group {
                AgentPresentationSettings(highlightID: highlightID)
                Section {
                    Defaults.Toggle(key: .enableClaudeProvider) {
                        Label("Enable Claude", systemImage: "power")
                    }
                    .settingsHighlight(id: highlightID("Claude Provider"))

                    Defaults.Toggle(key: .enableCodexProvider) {
                        Label("Enable Codex", systemImage: "power")
                    }
                    .settingsHighlight(id: highlightID("Codex Provider"))

                    Defaults.Toggle(key: .enableCursorProvider) {
                        Label("Enable Cursor", systemImage: "power")
                    }
                    .settingsHighlight(id: highlightID("Cursor Provider"))

                    Defaults.Toggle(key: .enableAntigravityProvider) {
                        Label("Enable Antigravity", systemImage: "power")
                    }
                    .settingsHighlight(id: highlightID("Antigravity Provider"))

                    Defaults.Toggle(key: .enableNewAPIProvider) {
                        Label("Enable New API", systemImage: "power")
                    }
                    .settingsHighlight(id: highlightID("New API Provider"))
                    .onChange(of: enableNewAPIProvider) { _, _ in
                        LLMUsageManager.shared.refreshAll(force: true)
                    }
                } header: {
                    Text("LLM Providers")
                } footer: {
                    Text("Choose which AI providers appear in the Usage tab.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                    .font(.caption)
                }

                Section {
                    if newAPIAccounts.isEmpty {
                        Text("Add one or more New API accounts to monitor their balance and usage.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(newAPIAccounts) { account in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                    Text(account.baseURL)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer()

                                Button {
                                    editingNewAPIAccount = account
                                    isNewAPIEditorPresented = true
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                .help("Edit New API account")

                                Button(role: .destructive) {
                                    accountPendingDeletion = account
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete New API account")
                            }
                        }
                    }

                    Button {
                        editingNewAPIAccount = nil
                        isNewAPIEditorPresented = true
                    } label: {
                        Label("Add New API Account", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .settingsHighlight(id: highlightID("New API Accounts"))
                } header: {
                    Label("New API Accounts", systemImage: "slider.horizontal.3")
                } footer: {
                    Text("API keys are stored in the macOS Keychain. Balance and usage are shown in the quota units reported by your New API server.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .disabled(!enableLLMUsageFeature)
        }
        .navigationTitle("LLM Agents")
        .onAppear {
            newAPIAccounts = Defaults[.newAPIAccounts]
        }
        .sheet(isPresented: $isNewAPIEditorPresented) {
            NewAPIAccountEditor(account: editingNewAPIAccount) { account, apiKey in
                try NewAPIAccountStore.upsert(account, apiKey: apiKey)
                newAPIAccounts = Defaults[.newAPIAccounts]
                LLMUsageManager.shared.refreshAll(force: true)
                isNewAPIEditorPresented = false
            }
        }
        .confirmationDialog(
            "Delete New API account?",
            isPresented: Binding(
                get: { accountPendingDeletion != nil },
                set: { if !$0 { accountPendingDeletion = nil } }
            ),
            presenting: accountPendingDeletion
        ) { account in
            Button("Delete \(account.name)", role: .destructive) {
                do {
                    try NewAPIAccountStore.delete(account)
                    newAPIAccounts = Defaults[.newAPIAccounts]
                    LLMUsageManager.shared.refreshAll(force: true)
                    accountPendingDeletion = nil
                } catch {
                    newAPIAccountErrorMessage = String(localized: "Failed to delete \(account.name): \(error.localizedDescription)")
                }
            }
            Button("Cancel", role: .cancel) {
                accountPendingDeletion = nil
            }
        } message: { account in
            Text("This removes \(account.name) and its stored API key from Eave.")
        }
        .alert("New API Account Error", isPresented: Binding(
            get: { newAPIAccountErrorMessage != nil },
            set: { if !$0 { newAPIAccountErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { newAPIAccountErrorMessage = nil }
        } message: {
            Text(newAPIAccountErrorMessage ?? String(localized: "An unknown error occurred."))
        }
    }
}

private struct NewAPIAccountEditor: View {
    let account: NewAPIAccount?
    let onSave: (NewAPIAccount, String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var errorMessage: String?

    init(account: NewAPIAccount?, onSave: @escaping (NewAPIAccount, String) throws -> Void) {
        self.account = account
        self.onSave = onSave
        _name = State(initialValue: account?.name ?? "")
        _baseURL = State(initialValue: account?.baseURL ?? "https://")
        _apiKey = State(initialValue: account.map { NewAPIKeychain.read(accountID: $0.id) ?? "" } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(account == nil ? "Add New API Account" : "Edit New API Account")
                .font(.title3.weight(.semibold))

            Form {
                TextField("Account name", text: $name)
                TextField("Base URL", text: $baseURL)
                    .textContentType(.URL)
                SecureField("API key", text: $apiKey)
                    .textContentType(.password)
            }
            .formStyle(.grouped)
            .frame(width: 420)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 470)
    }

    private func save() {
        let updated = NewAPIAccount(
            id: account?.id ?? UUID(),
            name: name,
            baseURL: baseURL
        )
        do {
            try onSave(updated, apiKey)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CustomOSDSettings: View {
    @Default(.enableCustomOSD) var enableCustomOSD
    @Default(.hasSeenOSDAlphaWarning) var hasSeenOSDAlphaWarning
    @Default(.enableOSDVolume) var enableOSDVolume
    @Default(.enableOSDBrightness) var enableOSDBrightness
    @Default(.enableOSDKeyboardBacklight) var enableOSDKeyboardBacklight
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.osdMaterial) var osdMaterial
    @Default(.osdLiquidGlassCustomizationMode) var osdLiquidGlassCustomizationMode
    @Default(.osdLiquidGlassVariant) var osdLiquidGlassVariant
    @Default(.osdIconColorStyle) var osdIconColorStyle
    @Default(.enableSystemHUD) var enableSystemHUD
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    @State private var showAlphaWarning = false
    @State private var previewValue: CGFloat = 0.65
    @State private var previewType: SneakContentType = .volume

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    private var hasAccessibilityPermission: Bool {
        accessibilityPermission.isAuthorized
    }

    private var availableOSDMaterials: [OSDMaterial] {
        if #available(macOS 26.0, *) {
            return OSDMaterial.allCases
        }
        return OSDMaterial.allCases.filter { $0 != .liquid }
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var osdLiquidVariantBinding: Binding<Double> {
        Binding(
            get: { Double(osdLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                osdLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    var body: some View {
        Group {
            if !enableThirdPartyDDCIntegration {
                Section {
                    AccessibilitySettingsPermissionRow(message: "Accessibility permission is needed to intercept system controls for the Custom OSD.")
                } header: {
                    Text("Accessibility")
                }
            }

            if hasAccessibilityPermission || enableThirdPartyDDCIntegration {
                Section {
                    Toggle("Show volume OSD", systemImage: "speaker.wave.2", isOn: $enableOSDVolume)
                        .settingsHighlight(id: highlightID("Show volume OSD"))
                    Toggle("Show brightness OSD", systemImage: "sun.max", isOn: $enableOSDBrightness)
                        .settingsHighlight(id: highlightID("Show brightness OSD"))
                    Toggle("Show keyboard backlight OSD", systemImage: "keyboard", isOn: $enableOSDKeyboardBacklight)
                        .settingsHighlight(id: highlightID("Show keyboard backlight OSD"))
                        .disabledWhileExternalAppOwnsKeys("Disabled while the external display app is running \u{2014} that app owns the keyboard backlight keys.")
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Choose which system controls should display custom OSD windows.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    HStack(spacing: 12) {
                        Label("Material", systemImage: "circle.lefthalf.filled").accessibilityHidden(true)
                        Spacer(minLength: 12)
                        Picker(selection: $osdMaterial) {
                            ForEach(availableOSDMaterials, id: \.self) { material in
                                Text(LocalizedStringKey(material.rawValue)).tag(material)
                            }
                        } label: {
                            Label("Material", systemImage: "circle.lefthalf.filled")
                        }
                            .labelsHidden()
                    }
                    .settingsHighlight(id: highlightID("Material"))
                    .onChange(of: osdMaterial) { _, _ in
                        previewValue = previewValue == 0.65 ? 0.651 : 0.65
                    }

                    if osdMaterial == .liquid {
                        if #available(macOS 26.0, *) {
                            SettingsSegmentedPicker(
                                "Glass mode",
                                selection: $osdLiquidGlassCustomizationMode,
                                items: Array(LockScreenGlassCustomizationMode.allCases)
                            ) { $0.rawValue }

                            if osdLiquidGlassCustomizationMode == .customLiquid {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Label("Custom liquid variant", systemImage: "drop")
                                        Spacer()
                                    }
                                    SettingsSlider(value: osdLiquidVariantBinding, in: liquidVariantRange, step: 1, valueLabel: Text("v\(osdLiquidGlassVariant.rawValue)"))
                                }
                            }
                        } else {
                            Text("Custom Liquid is available on macOS 26 or later.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Label("Icon & Progress Color", systemImage: "paintpalette").accessibilityHidden(true)
                        Spacer(minLength: 12)
                        Picker(selection: $osdIconColorStyle) {
                            ForEach(OSDIconColorStyle.allCases, id: \.self) { style in
                                Text(LocalizedStringKey(style.rawValue)).tag(style)
                            }
                        } label: {
                            Label("Icon & Progress Color", systemImage: "paintpalette")
                        }
                            .labelsHidden()
                    }
                    .settingsHighlight(id: highlightID("Icon & Progress Color"))
                    .onChange(of: osdIconColorStyle) { _, _ in
                        previewValue = previewValue == 0.65 ? 0.651 : 0.65
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Material Options:")
                        Text("• Frosted Glass: Translucent blur effect")
                        Text("• Liquid Glass: Modern glass effect (macOS 26+)")
                        Text("• Solid Dark/Light/Auto: Opaque backgrounds")
                        Text("")
                        Text("Color options control the icon and progress bar appearance. Auto adapts to system theme.")
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }

                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Text("Live Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            CustomOSDView(
                                type: .constant(previewType),
                                value: .constant(previewValue),
                                icon: .constant("")
                            )
                            .frame(width: 200, height: 200)

                            HStack(spacing: 8) {
                                Button("Volume") {
                                    previewType = .volume
                                }
                                .buttonStyle(.bordered)

                                Button("Brightness") {
                                    previewType = .brightness
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Backlight") {
                                    previewType = .backlight
                                }
                                .buttonStyle(.bordered)
                            }
                            .controlSize(.small)
                            
                            SettingsSlider(value: $previewValue, in: 0...1)
                                .frame(width: 190)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                } header: {
                    Text("Preview")
                } footer: {
                    Text("Adjust settings above to see changes in real-time. The actual OSD appears at the bottom center of your screen.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Custom OSD")
        .onAppear {
            accessibilityPermission.refreshStatus()
            if #unavailable(macOS 26.0), osdMaterial == .liquid {
                osdMaterial = .frosted
                osdLiquidGlassCustomizationMode = .standard
            }
        }
        .onChange(of: accessibilityPermission.isAuthorized) { _, granted in
            if !granted {
                enableCustomOSD = false
            }
        }
    }
}

#Preview {
    HUD()
}

struct NotesSettingsView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var appleNotesSync = AppleNotesSyncManager.shared
    @Default(.enableNotes) private var enableNotes
    @Default(.enableAppleNotesSync) private var enableAppleNotesSync
    @Default(.appleNotesLastSyncDate) private var appleNotesLastSyncDate

    private func highlightID(_ title: String) -> String {
        SettingsTab.notes.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableNotes) {
                    Label("Enable notes", systemImage: "power")
                }
            }

            Section("Permissions") {
                NotesSettingsPermissionRow()
            }

            Section {
                Group {
                    Defaults.Toggle(key: .enableNotePinning) {
                        Label("Enable note pinning", systemImage: "power")
                    }
                    Defaults.Toggle(key: .enableNoteSearch) {
                        Label("Enable note search", systemImage: "power")
                    }
                    Defaults.Toggle(key: .enableNoteColorFiltering) {
                        Label("Enable color filtering", systemImage: "paintpalette")
                    }
                    Defaults.Toggle(key: .enableCreateFromClipboard) {
                        Label("Enable creation from clipboard", systemImage: "doc.on.clipboard")
                    }
                    Defaults.Toggle(key: .enableNoteCharCount) {
                        Label("Show character count", systemImage: "power")
                    }
                }
                .disabled(!enableNotes)
            } header: {
                Text("General")
            } footer: {
                Text("Customize how you organize and create notes. Enabling color filtering and search helps manage large lists.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Group {
                Section {
                    Defaults.Toggle(key: .enableAppleNotesSync) {
                        Label("Sync with Apple Notes", systemImage: "slider.horizontal.3")
                    }
                    .settingsHighlight(id: highlightID("Sync with Apple Notes"))

                    Group {
                        Button {
                            Task {
                                let notes = Defaults[.savedNotes]
                                if let merged = await appleNotesSync.sync(localNotes: notes) {
                                    Defaults[.savedNotes] = merged
                                }
                            }
                        } label: {
                            HStack {
                                Label("Sync Now", systemImage: "slider.horizontal.3")
                                Spacer()
                                if appleNotesSync.isSyncing {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        }
                        .disabled(appleNotesSync.isSyncing)
                        .settingsHighlight(id: highlightID("Sync Now"))

                        if let lastSync = appleNotesLastSyncDate {
                            LabeledContent() {
                                Text(lastSync, style: .relative)
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label("Last synced", systemImage: "slider.horizontal.3")
                            }
                        }

                        if let error = appleNotesSync.lastError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .disabled(!enableAppleNotesSync)
                } header: {
                    Text("Apple Notes")
                } footer: {
                    Text("Two-way sync with the macOS Notes app. Notes created in Eave appear in the Eave folder in Notes, and your existing Apple Notes are imported into the notch. Grant Automation permission for Notes when prompted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!enableNotes)
        }
        .navigationTitle("Notes")
    }
}

// MARK: - Terminal Settings

struct TerminalSettings: View {
    @ObservedObject var terminalManager = TerminalManager.shared
    @Default(.enableTerminalFeature) var enableTerminalFeature
    @Default(.terminalShellPath) var terminalShellPath
    @Default(.terminalFontFamily) var terminalFontFamily
    @Default(.terminalFontSize) var terminalFontSize
    @Default(.terminalOpacity) var terminalOpacity
    @Default(.terminalMaxHeightFraction) var terminalMaxHeightFraction
    @Default(.terminalCursorStyle) var terminalCursorStyle
    @Default(.terminalScrollbackLines) var terminalScrollbackLines
    @Default(.terminalOptionAsMeta) var terminalOptionAsMeta
    @Default(.terminalMouseReporting) var terminalMouseReporting
    @Default(.terminalBoldAsBright) var terminalBoldAsBright
    @Default(.terminalBackgroundColor) var terminalBackgroundColor
    @Default(.terminalForegroundColor) var terminalForegroundColor
    @Default(.terminalCursorColor) var terminalCursorColor

    private func highlightID(_ title: String) -> String {
        SettingsTab.terminal.highlightID(for: title)
    }

    private var formattedMaxHeight: String {
        String(localized: "\(Int(terminalMaxHeightFraction * 100))% of screen")
    }

    /// All monospaced font families available on the system.
    private var monospacedFontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return font.isFixedPitch
                || font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        }
        .sorted()
    }

    /// Display name for the font picker — shows "System Monospaced" when no custom font is set.
    private var fontDisplayName: String {
        terminalFontFamily.isEmpty ? String(localized: "System Monospaced") : terminalFontFamily
    }

    private var cursorStyleBinding: Binding<TerminalCursorStyleOption> {
        Binding(
            get: { TerminalCursorStyleOption(rawValue: terminalCursorStyle) ?? .blinkBlock },
            set: { terminalCursorStyle = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableTerminalFeature) {
                    Label("Enable terminal", systemImage: "power")
                }
                .settingsHighlight(id: highlightID("Enable terminal"))

                Group {
                    Defaults.Toggle(key: .terminalStickyMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Keep terminal open until clicked outside", systemImage: "pin")
                            Text("Prevents the terminal from closing when the cursor accidentally leaves the notch area.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsHighlight(id: highlightID("Keep terminal open"))
                }
                .disabled(!enableTerminalFeature)
            } header: {
                Text("General")
            } footer: {
                Text("Adds a Guake-style dropdown terminal tab. The terminal session persists across notch open/close cycles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Group {
                // MARK: Shell
                Section {
                    HStack {
                        Label("Shell path", systemImage: "slider.horizontal.3")
                        Spacer()
                        TextField("", text: $terminalShellPath)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                            .multilineTextAlignment(.trailing)
                    }
                    .settingsHighlight(id: highlightID("Shell path"))
                } header: {
                    Label("Shell", systemImage: "terminal")
                }

                // MARK: Appearance
                Section {
                    HStack(spacing: 12) {
                        Label("Font family", systemImage: "textformat").accessibilityHidden(true)
                        Spacer(minLength: 12)
                        Picker(selection: $terminalFontFamily) {
                            Text("System Monospaced").tag("")
                            Divider()
                            ForEach(monospacedFontFamilies, id: \.self) { family in
                                Text(family)
                                    .font(.custom(family, size: 13))
                                    .tag(family)
                            }
                        } label: {
                            Label("Font family", systemImage: "textformat")
                        }
                            .labelsHidden()
                    }
                    .onChange(of: terminalFontFamily) { _, newValue in
                        terminalManager.applyFontFamily(newValue)
                    }
                    .settingsHighlight(id: highlightID("Font family"))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Font size", systemImage: "arrow.left.and.right")
                            Spacer()
                        }
                        SettingsSlider(value: $terminalFontSize, in: 8...24, step: 1, valueLabel: Text("\(Int(terminalFontSize)) pt"))
                            .onChange(of: terminalFontSize) { _, newValue in
                                terminalManager.applyFontSize(newValue)
                            }
                    }
                    .settingsHighlight(id: highlightID("Font size"))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Terminal opacity", systemImage: "circle.lefthalf.filled")
                            Spacer()
                        }
                        SettingsSlider(value: $terminalOpacity, in: 0.3...1.0, step: 0.05, valueLabel: Text("\(Int(terminalOpacity * 100))%"))
                            .onChange(of: terminalOpacity) { _, newValue in
                                terminalManager.applyOpacity(newValue)
                            }
                    }
                    .settingsHighlight(id: highlightID("Terminal opacity"))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Maximum height", systemImage: "arrow.left.and.right")
                            Spacer()
                        }
                        SettingsSlider(value: $terminalMaxHeightFraction, in: 0.2...0.5, step: 0.05, valueLabel: Text(formattedMaxHeight))
                    }
                    .settingsHighlight(id: highlightID("Maximum height"))
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Terminal opacity only affects the terminal backdrop; text stays fully opaque. Blur uses the system material behind the window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Colors
                Section {
                    HStack(spacing: 12) {
                        Label("Background", systemImage: "paintpalette").accessibilityHidden(true)
                        Spacer(minLength: 12)
                        ColorPicker(selection: $terminalBackgroundColor, supportsOpacity: false) { Label("Background", systemImage: "paintpalette") }
                            .labelsHidden()
                    }
                        .onChange(of: terminalBackgroundColor) { _, newValue in
                            terminalManager.applyBackgroundColor(newValue)
                        }
                        .settingsHighlight(id: highlightID("Background color"))

                    HStack(spacing: 12) {
                        Label("Foreground", systemImage: "paintpalette").accessibilityHidden(true)
                        Spacer(minLength: 12)
                        ColorPicker(selection: $terminalForegroundColor, supportsOpacity: false) { Label("Foreground", systemImage: "paintpalette") }
                            .labelsHidden()
                    }
                        .onChange(of: terminalForegroundColor) { _, newValue in
                            terminalManager.applyForegroundColor(newValue)
                        }
                        .settingsHighlight(id: highlightID("Foreground color"))

                    HStack(spacing: 12) {
                        Label("Cursor", systemImage: "paintpalette").accessibilityHidden(true)
                        Spacer(minLength: 12)
                        ColorPicker(selection: $terminalCursorColor, supportsOpacity: false) { Label("Cursor", systemImage: "paintpalette") }
                            .labelsHidden()
                    }
                        .onChange(of: terminalCursorColor) { _, newValue in
                            terminalManager.applyCursorColor(newValue)
                        }
                        .settingsHighlight(id: highlightID("Cursor color"))

                    Toggle("Use bright colors for bold text", systemImage: "paintpalette", isOn: $terminalBoldAsBright)
                        .onChange(of: terminalBoldAsBright) { _, newValue in
                            terminalManager.applyBoldAsBright(newValue)
                        }
                        .settingsHighlight(id: highlightID("Bold as bright"))
                } header: {
                    Text("Colors")
                } footer: {
                    Text("When bold-as-bright is off, bold text uses a heavier font weight instead of bright ANSI colors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Cursor
                Section {
                    HStack(spacing: 12) {
                        Label("Cursor style", systemImage: "circle.lefthalf.filled").accessibilityHidden(true)
                        Spacer(minLength: 12)
                        Picker(selection: cursorStyleBinding) {
                            ForEach(TerminalCursorStyleOption.allCases, id: \.self) { style in
                                Text(style.displayName).tag(style)
                            }
                        } label: {
                            Label("Cursor style", systemImage: "circle.lefthalf.filled")
                        }
                            .labelsHidden()
                    }
                    .onChange(of: terminalCursorStyle) { _, newValue in
                        if let style = TerminalCursorStyleOption(rawValue: newValue) {
                            terminalManager.applyCursorStyle(style)
                        }
                    }
                    .settingsHighlight(id: highlightID("Cursor style"))
                } header: {
                    Text("Cursor")
                }

                // MARK: Scrollback
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Scrollback lines", systemImage: "hand.draw")
                            Spacer()
                        }
                        SettingsSlider(
                            value: Binding(
                                get: { Double(terminalScrollbackLines) },
                                set: { terminalScrollbackLines = Int($0) }
                            ),
                            in: 100...10000,
                            step: 100,
                            valueLabel: Text("\(terminalScrollbackLines)")
                        )
                        .onChange(of: terminalScrollbackLines) { _, newValue in
                            terminalManager.applyScrollback(newValue)
                        }
                    }
                    .settingsHighlight(id: highlightID("Scrollback lines"))
                } header: {
                    Text("Scrollback")
                } footer: {
                    Text("Number of lines kept in the scrollback buffer. Higher values use more memory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Input
                Section {
                    Toggle("Use Option as Meta key", systemImage: "keyboard", isOn: $terminalOptionAsMeta)
                        .onChange(of: terminalOptionAsMeta) { _, newValue in
                            terminalManager.applyOptionAsMeta(newValue)
                        }
                        .settingsHighlight(id: highlightID("Option as Meta"))

                    Toggle("Allow mouse reporting", systemImage: "slider.horizontal.3", isOn: $terminalMouseReporting)
                        .onChange(of: terminalMouseReporting) { _, newValue in
                            terminalManager.applyMouseReporting(newValue)
                        }
                        .settingsHighlight(id: highlightID("Mouse reporting"))
                } header: {
                    Text("Input")
                } footer: {
                    Text("Option as Meta sends Esc+key instead of macOS special characters. Mouse reporting forwards mouse events to terminal applications like vim or tmux.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Actions
                Section {
                    Button("Restart Shell") {
                        terminalManager.restartShell()
                    }
                    .disabled(!terminalManager.isProcessRunning)
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Restarts the shell process. Any unsaved work in the terminal will be lost.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!enableTerminalFeature)
        }
        .navigationTitle("Terminal")
    }
}

// MARK: - Reusable App Icon View

/// Fetches the real app icon from the system using bundle identifiers,
/// falling back to an asset catalog image or an SF Symbol.
struct AppIconImage: View {
    let bundleIdentifiers: [String]
    var assetFallback: String? = nil
    var symbolFallback: String = "app.fill"
    var symbolColor: Color = .accentColor
    var size: CGFloat = 16
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let nsImage = icon {
                Image(nsImage: nsImage.fitted(toSide: size))
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else if let assetFallback, let nsImage = NSImage(named: NSImage.Name(assetFallback)) {
                Image(nsImage: nsImage.fitted(toSide: size))
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                Image(systemName: symbolFallback)
                    .foregroundColor(symbolColor)
            }
        }
        .frame(width: size, height: size)
        // Resolve once per identity/size, outside repeated body/layout passes.
        .task(id: bundleIdentifiers + [String(describing: size)]) {
            icon = resolvedIcon()
        }
    }

    private func resolvedIcon() -> NSImage? {
        for bundleID in bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                // NSWorkspace returns a valid icon even for generic apps;
                // redraw it small to keep memory low. At twice the size it is
                // asked for, so it stays sharp on a Retina display -- the old
                // flat 32 was being scaled *up* wherever this is drawn larger
                // than that, which is why the bigger icons looked soft.
                let side = max(32, size * 2)
                let thumb = NSImage(size: NSSize(width: side, height: side))
                thumb.lockFocus()
                icon.draw(in: NSRect(origin: .zero, size: NSSize(width: side, height: side)),
                          from: NSRect(origin: .zero, size: icon.size),
                          operation: .copy, fraction: 1.0)
                thumb.unlockFocus()
                return thumb
            }
        }
        return nil
    }
}

private struct QuickShareProviderIconImage: View {
    let provider: QuickShareProvider
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                Image(nsImage: nsImg.fitted(toSide: size))
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                AppIconImage(
                    bundleIdentifiers: provider.bundleIdentifiersFallback,
                    assetFallback: provider.assetFallbackName,
                    symbolFallback: provider.symbolFallbackName,
                    symbolColor: .accentColor,
                    size: size
                )
            }
        }
        .frame(width: size, height: size)
    }
}

private extension QuickShareProvider {
    var bundleIdentifiersFallback: [String] {
        switch id {
        case "LocalSend":
            return ["org.localsend.localsend_app", "org.localsend.localsend"]
        case "AirDrop":
            return ["com.apple.finder"]
        case "Mail":
            return ["com.apple.mail"]
        case "Messages":
            return ["com.apple.MobileSMS", "com.apple.iChat"]
        case "Notes":
            return ["com.apple.Notes"]
        case "Reminders":
            return ["com.apple.reminders"]
        case "Add to Safari Reading List":
            return ["com.apple.Safari"]
        default:
            return []
        }
    }

    var assetFallbackName: String? {
        id == "LocalSend" ? "LocalSend" : nil
    }

    var symbolFallbackName: String {
        id == "System Share Menu" ? "square.and.arrow.up.on.square" : "square.and.arrow.up"
    }
}
