import AppKit
import AVFoundation
import EaveStatus
import EventKit
import SwiftUI
import UserNotifications

func openPermissionSettings(_ pane: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") {
        NSWorkspace.shared.open(url)
    }
}

struct AccessibilitySettingsPermissionRow: View {
    @ObservedObject private var permission = AccessibilityPermissionStore.shared
    @AppStorage("accessibilityPermissionRequested") private var requested = false
    let message: String

    var body: some View {
        SettingsPermissionRow(title: "Accessibility", message: message,
                              state: permission.isAuthorized ? .granted : (requested ? .denied : .notDetermined),
                              request: {
            requested = true
            permission.requestAuthorizationPrompt()
        }, openSettings: {
            permission.openSystemSettings()
        })
        .onAppear { permission.refreshStatus() }
    }
}

struct CameraSettingsPermissionRow: View {
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    private var state: SettingsPermissionState {
        switch status {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unknown
        }
    }

    var body: some View {
        SettingsPermissionRow(title: "Camera", message: "Allows the mirror to show your camera preview.", state: state,
                              request: {
            AVCaptureDevice.requestAccess(for: .video) { _ in
                Task { @MainActor in
                    status = AVCaptureDevice.authorizationStatus(for: .video)
                    WebcamManager.shared.checkAndRequestVideoAuthorization()
                }
            }
        }, openSettings: { openPermissionSettings("Camera") })
        .onAppear { status = AVCaptureDevice.authorizationStatus(for: .video) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }
}

import Carbon

struct NotesSettingsPermissionRow: View {
    @State private var state: SettingsPermissionState = .unknown

    private func refresh(request: Bool = false) {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Notes")
        let result = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, request)
        switch result {
        case noErr: state = .granted
        case OSStatus(errAEEventWouldRequireUserConsent): state = .notDetermined
        case OSStatus(errAEEventNotPermitted): state = .denied
        default: state = .unknown
        }
    }

    var body: some View {
        SettingsPermissionRow(title: "Notes Automation", message: "Allows syncing with Apple Notes. Other note features work without it.", state: state,
                              request: { refresh(request: true) },
                              openSettings: { openPermissionSettings("Automation") })
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }
}

struct AudioSettingsPermissionRow: View {
    @ObservedObject private var manager = PerAppVolumeManager.shared

    var body: some View {
        // Core Audio exposes tap failures, not a queryable recording authorization status.
        SettingsPermissionRow(title: "Audio Recording", message: "Requested when you first change an app’s volume. Audio is never saved.",
                              state: manager.isPermissionBlocked ? .denied : .unknown,
                              openSettings: { openPermissionSettings("ScreenCapture") })
    }
}

struct NotificationsSettingsPermissionRow: View {
    @State private var state: SettingsPermissionState = .unknown
    @State private var requestError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingsPermissionRow(title: "Notifications", message: "Optional. Allows monitoring alerts. Basic monitoring works without it.",
                                  state: state, request: {
                Task {
                    requestError = nil
                    do {
                        _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                    } catch {
                        requestError = error.localizedDescription
                    }
                    await refresh()
                }
            }, openSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            })
            if let requestError {
                Text(requestError).font(.caption).foregroundStyle(.red)
            }
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        state = SettingsPermissionState(notification: settings.authorizationStatus)
    }
}
